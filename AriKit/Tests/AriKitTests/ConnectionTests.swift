import Foundation
import Testing

@testable import AriKit

@Suite("Server addresses and tokens")
struct AddressTests {
    @Test("HTTPS by default, and plain HTTP only to this device")
    func addresses() throws {
        #expect(
            try ServerAddress("studio.tail1234.ts.net:8787").description
                == "https://studio.tail1234.ts.net:8787")
        #expect(
            try ServerAddress(" https://studio.example/ ").description == "https://studio.example")
        #expect(
            try ServerAddress("https://studio.example/ito/").description
                == "https://studio.example/ito")
        #expect(try ServerAddress("http://localhost:8787").description == "http://localhost:8787")
        #expect(try ServerAddress("http://127.0.0.1:8787").description == "http://127.0.0.1:8787")
        #expect(try ServerAddress("HTTP://[::1]:8787").description == "http://[::1]:8787")
        #expect(throws: ServerAddress.Problem.insecure) {
            try ServerAddress("http://studio.example")
        }
        #expect(throws: ServerAddress.Problem.empty) { try ServerAddress("  ") }
        #expect(throws: ServerAddress.Problem.notAnAddress) { try ServerAddress("ftp://studio") }
        #expect(throws: ServerAddress.Problem.notAnAddress) {
            try ServerAddress("https://studio?x=1")
        }
    }

    @Test("a token never shows in full: not printed, not debugged, not dumped")
    func tokenStaysSecret() {
        let token = Token(" ito_example_not_a_real_token_f3a9\n")
        #expect(token.secret == "ito_example_not_a_real_token_f3a9")
        #expect(token.lastFour == "…f3a9")
        var dumped = ""
        dump(token, to: &dumped)
        for shown in [String(describing: token), String(reflecting: token), "\(token)", dumped] {
            #expect(!shown.contains("not_a_real"), "\(shown)")
        }
    }
}

@Suite("The first connection")
struct ConnectorTests {
    @Test("scenario 1: a mistyped token is named, and the right one connects without asking again")
    func firstConnection() async throws {
        let transcript = try Fixtures.transcript("01-first-connection")
        let server = ScriptedServer()
        let connector = Connector(transport: server)
        var steps = transcript.steps[...]
        func next() -> Transcript.Step { steps.removeFirst() }
        func answerNext() async throws {
            guard case .server(let response) = next() else {
                throw TranscriptError("expected an answer")
            }
            try await server.answer(response)
        }
        func request() async throws -> HTTPRequest {
            for _ in 0..<1_000 {
                if let request = await server.takeRequest() { return request }
                await Task.yield()
            }
            throw TranscriptError("no request")
        }

        let mistyped = Token("ito_example_mistyped_token_0000000000000000000")
        let firstTry = Task { try await connector.connect(to: "studio.example", token: mistyped) }
        guard case .app(let discovery) = next() else { return }
        let made = try await request()
        #expect(made.path == discovery.path)
        #expect(made.headers["Authorization"] == nil)
        try await answerNext()
        guard case .app(let check) = next() else { return }
        #expect(try await request().headers["Authorization"] == check.headers["Authorization"])
        try await answerNext()
        let result = await firstTry.result
        #expect(throws: ConnectError.self) { try result.get() }
        guard case .failure(let error as ConnectError) = result,
            case .tokenRejected(let refusal) = error
        else {
            Issue.record("expected the token to be rejected, not \(result)")
            return
        }
        #expect(refusal?.code == ErrorCode(rawValue: "token_rejected"))

        let right = Token("ito_example_not_a_real_token_00000000000000000000")
        let address = try ServerAddress("studio.example")
        let secondTry = Task { try await connector.check(right, at: address) }
        guard case .app(let recheck) = next() else { return }
        #expect(try await request().headers["Authorization"] == recheck.headers["Authorization"])
        try await answerNext()
        let connection = try await secondTry.value
        #expect(connection.server.name == "studio")
        #expect(connection.token == right)
    }

    @Test("scenario 31: a pairing code becomes a token of this device's own, and works once")
    func pairing() async throws {
        let transcript = try Fixtures.transcript("31-pair-with-a-qr-code")
        let server = ScriptedServer()
        let connector = Connector(transport: server)
        var steps = transcript.steps[...]
        guard case .world(let shown) = steps.removeFirst(),
            let code = shown.json?["code"]?.string
        else {
            throw TranscriptError("expected the pairing code first")
        }
        func play(_ count: Int) async throws {
            for _ in 0..<count {
                guard case .app(let expected) = steps.removeFirst(),
                    case .server(let response) = steps.removeFirst()
                else { throw TranscriptError("expected a request and its answer") }
                var made: HTTPRequest?
                for _ in 0..<1_000 where made == nil {
                    made = await server.takeRequest()
                    await Task.yield()
                }
                let request = try #require(made)
                #expect(request.path == expected.path)
                #expect(request.headers["Authorization"] == expected.headers["Authorization"])
                #expect(try request.body.map { try JSONValue(data: $0) } == expected.body)
                try await server.answer(response)
            }
        }

        #expect(Connector.isPairingCode(code))
        let pairing = Task {
            try await connector.pair(address: "studio.example", code: code, deviceName: "iPhone")
        }
        try await play(3)
        let connection = try await pairing.value
        #expect(connection.token == Token("ito_paired_example_not_a_real_token_000000000000000"))
        #expect(connection.server.setup?.notifications == false)

        let again = Task {
            try await connector.pair(
                code: code, deviceName: "iPad", at: try ServerAddress("studio.example"))
        }
        try await play(1)
        let result = await again.result
        guard case .failure(let error as ConnectError) = result,
            case .pairingCodeRejected(let refusal) = error
        else {
            Issue.record("expected the used code to be refused, not \(result)")
            return
        }
        #expect(refusal?.code == .pairingCodeRejected)
    }

    @Test("a pairing link from the QR code gives the address and the code")
    func pairingLink() throws {
        let link = try #require(
            URL(string: "ito://pair?address=studio.tail1234.ts.net&code=7F3K-92QD"))
        let pairing = try #require(Connector.pairing(from: link))
        #expect(pairing.address == "studio.tail1234.ts.net" && pairing.code == "7F3K-92QD")
        #expect(Connector.pairing(from: try #require(URL(string: "https://studio.example"))) == nil)
        #expect(Connector.isPairingCode("7f3k92qd"))
        #expect(!Connector.isPairingCode("ito_example_not_a_real_token_00000000000000000000"))
    }

    @Test("a protocol mismatch says which side to update")
    func mismatch() async throws {
        for (versions, side) in [(#"["0.14"]"#, ProtocolMismatch.Side.ari), (#"["0.9"]"#, .server)]
        {
            let server = ScriptedServer()
            let discovering = Task {
                try await Connector(transport: server).discover("studio.example")
            }
            while await server.takeRequest() == nil { await Task.yield() }
            try await server.answer(200, json: #"{"product":"ito","protocol":\#(versions)}"#)
            let result = await discovering.result
            guard case .failure(let error as ConnectError) = result,
                case .protocolMismatch(let mismatch) = error
            else {
                Issue.record("expected a mismatch for \(versions), not \(result)")
                continue
            }
            #expect(mismatch.update == side)
        }
    }

    @Test(
        "an address that isn't usable, or a server that isn't there, is named before anything else")
    func unreachable() async throws {
        await #expect(throws: ConnectError.address(.insecure)) {
            try await Connector(transport: ScriptedServer()).discover("http://studio.example")
        }
        let server = ScriptedServer()
        await server.setOnline(false)
        await #expect(throws: ConnectError.unreachable(.notConnectedToInternet)) {
            try await Connector(transport: server).discover("studio.example")
        }
    }
}

@Suite("Refusals")
struct RequestErrorTests {
    @Test("which refusals are worth trying again, and how long the server asked Ari to wait")
    func temporary() {
        #expect(RequestError.network(.timedOut).isTemporary)
        #expect(RequestError.refused(status: 429, error: nil, retryAfter: .seconds(5)).isTemporary)
        #expect(RequestError.refused(status: 503, error: nil, retryAfter: nil).isTemporary)
        #expect(!RequestError.refused(status: 400, error: nil, retryAfter: nil).isTemporary)
        #expect(!RequestError.refused(status: 409, error: nil, retryAfter: nil).isTemporary)
        #expect(
            RequestError.refused(status: 429, error: nil, retryAfter: .seconds(5)).retryAfter
                == .seconds(5))
    }
}

@Suite("The Keychain")
struct KeychainTests {
    @Test("saves, replaces, reads and deletes a server's token")
    func roundTrip() throws {
        let store = KeychainTokenStore(service: "io.github.akai-ito.ari.tests.\(UUID().uuidString)")
        let address = try ServerAddress("studio.example")
        defer { try? store.delete(for: address) }
        #expect(try store.token(for: address) == nil)
        try store.save(Token("ito_first"), for: address)
        try store.save(Token("ito_second"), for: address)
        #expect(try store.token(for: address) == Token("ito_second"))
        try store.delete(for: address)
        #expect(try store.token(for: address) == nil)
    }
}
