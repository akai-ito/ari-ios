import AriKit
import Foundation
import Testing

/// Kumo's own settings through the real client, against the scripted server: what each call sends,
/// and how it reads the answer.
@Suite("Kumo's settings")
struct SettingsTests {
    private func client(_ server: ScriptedServer) throws -> ItoClient {
        ItoClient(
            address: try ServerAddress("https://studio.example"),
            token: Token("ito_example_not_a_real_token_00000000000000000000"), transport: server)
    }

    private func request(from server: ScriptedServer) async throws -> HTTPRequest {
        for _ in 0..<500 {
            if let request = await server.takeRequest() { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TranscriptError("no request within 5 seconds")
    }

    private func json(_ request: HTTPRequest) throws -> JSONValue {
        try JSONValue(data: #require(request.body))
    }

    @Test("renaming the lead puts its name, and reads the lead back")
    func renamesTheLead() async throws {
        let server = ScriptedServer()
        let renaming = Task { [client = try client(server)] in
            try await client.renameLead(to: "Tess")
        }
        let sent = try await request(from: server)
        #expect(sent.method == .put)
        #expect(sent.path == "/v0/lead")
        #expect(sent.headers["Content-Type"] == "application/json")
        #expect(sent.headers["Authorization"]?.hasPrefix("Bearer ") == true)
        #expect(try json(sent) == JSONValue(json: #"{ "name": "Tess" }"#))
        try await server.answer(200, json: #"{ "name": "Tess" }"#)
        #expect(try await renaming.value == Lead(name: "Tess"))
    }

    @Test("the morning time goes as HH:mm, and comes back as saved")
    func setsTheMorning() async throws {
        let server = ScriptedServer()
        let setting = Task { [client = try client(server)] in
            try await client.setMorning(MorningTime(hour: 6, minute: 5))
        }
        let sent = try await request(from: server)
        #expect(sent.method == .put)
        #expect(sent.path == "/v0/morning")
        #expect(try json(sent) == JSONValue(json: #"{ "not_before": "06:05" }"#))
        try await server.answer(200, json: #"{ "not_before": "06:05" }"#)
        let saved = try await setting.value
        #expect(saved.notBefore == "06:05")
        #expect(saved.time?.hour == 6 && saved.time?.minute == 5)
    }

    @Test("a refusal keeps the server's reason")
    func refuses() async throws {
        let server = ScriptedServer()
        let renaming = Task { [client = try client(server)] in
            try await client.renameLead(to: "")
        }
        _ = try await request(from: server)
        try await server.answer(
            400,
            json:
                #"{ "error": { "code": "invalid_request", "message": "A name needs a letter." } }"#)
        do {
            _ = try await renaming.value
            Issue.record("a refusal was accepted")
        } catch let error as RequestError {
            #expect(error.status == 400)
            #expect(error.serverError?.message == "A name needs a letter.")
        }
    }

    @Test("an answer in another protocol version is refused")
    func checksTheVersion() async throws {
        let server = ScriptedServer()
        let renaming = Task { [client = try client(server)] in
            try await client.renameLead(to: "Tess")
        }
        _ = try await request(from: server)
        try await server.answer(
            200, headers: ["Ito-Protocol": "9.9"], json: #"{ "name": "Tess" }"#)
        do {
            _ = try await renaming.value
            Issue.record("a mismatched version was accepted")
        } catch let error as RequestError {
            #expect(error == .protocolMismatch(server: try #require(ProtocolVersion("9.9"))))
        }
    }

    @Test("the server's info carries the lead and the morning time")
    func serverInfo() throws {
        let info = try JSONDecoder().decode(
            ServerInfo.self,
            from: Data(
                """
                { "name": "box", "version": "0.17.0", "protocol": "0.17", "agent": { "model": "gpt" },
                  "setup": { "notifications": true }, "capabilities": [],
                  "lead": { "name": "Tess" }, "morning": { "not_before": "08:15" } }
                """.utf8))
        #expect(info.leadName == "Tess")
        #expect(info.morning.time?.hour == 8 && info.morning.time?.minute == 15)
    }

    @Test("a morning time that isn't HH:mm reads as no time")
    func oddTimes() {
        #expect(MorningTime(notBefore: "7:30").time?.hour == 7)
        #expect(MorningTime(notBefore: "24:00").time == nil)
        #expect(MorningTime(notBefore: "soon").time == nil)
        #expect(MorningTime.standard.notBefore == "07:30")
    }
}
