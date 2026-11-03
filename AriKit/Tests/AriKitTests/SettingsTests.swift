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

    @Test("whereabouts go with the time zone and a place rounded to about 10 km")
    func whereabouts() async throws {
        let server = ScriptedServer()
        let place = Area(latitude: 51.5072, longitude: -0.1276, name: "London")
        let telling = Task { [client = try client(server)] in
            try await client.setWhereabouts(
                "phone", Whereabouts(timeZone: "Europe/London", area: place))
        }
        let sent = try await request(from: server)
        #expect(sent.method == .put)
        #expect(sent.path == "/v0/devices/phone/whereabouts")
        #expect(
            try json(sent)
                == JSONValue(
                    json: #"""
                        { "time_zone": "Europe/London",
                          "area": { "latitude": 51.5, "longitude": -0.1, "name": "London" } }
                        """#))
        try await server.answer(204)
        try await telling.value
    }

    @Test("the time zone alone goes without a place")
    func timeZoneAlone() throws {
        let body = try JSONValue(encoding: Whereabouts(timeZone: "Europe/Rome"))
        #expect(body == (try JSONValue(json: #"{ "time_zone": "Europe/Rome" }"#)))
    }

    @Test("a plan moves, turns into a one-off, and is cancelled")
    func changesAPlan() async throws {
        let server = ScriptedServer()
        let moving = Task { [client = try client(server)] in
            try await client.changeWakeUp(
                "w_1",
                WakeUpChange(at: Timestamp("2026-11-11T10:00:00.000Z"), repeat: .some(nil)))
        }
        let sent = try await request(from: server)
        #expect(sent.method == .patch)
        #expect(sent.path == "/v0/wakeups/w_1")
        #expect(
            try json(sent)
                == JSONValue(json: #"{ "at": "2026-11-11T10:00:00.000Z", "repeat": null }"#))
        try await server.answer(
            200,
            json: #"""
                { "wake_up": { "id": "w_1", "at": "2026-11-11T10:00:00.000Z", "what": "Plan the day",
                  "why": "You asked.", "by": "you", "source": { "kind": "chat", "title": "Chat" },
                  "set_at": "2026-11-10T19:00:00.000Z" } }
                """#)
        let moved = try await moving.value
        #expect(moved.repeat == nil && moved.by == .you && moved.what == "Plan the day")

        let cancelling = Task { [client = try client(server)] in
            try await client.cancelWakeUp("w_1")
        }
        let cancel = try await request(from: server)
        #expect(cancel.method == .delete)
        #expect(cancel.path == "/v0/wakeups/w_1")
        #expect(cancel.body == nil)
        try await server.answer(204)
        try await cancelling.value
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

    @Test("the server's info carries the lead, the time zone and where you roughly are")
    func serverInfo() throws {
        let info = try JSONDecoder().decode(
            ServerInfo.self,
            from: Data(
                """
                { "name": "box", "version": "0.18.0", "protocol": "0.18", "agent": { "model": "gpt" },
                  "setup": { "notifications": true }, "capabilities": [],
                  "lead": { "name": "Tess" }, "time_zone": "Europe/Rome",
                  "whereabouts": { "time_zone": "Europe/Rome",
                    "area": { "latitude": 41.9, "longitude": 12.5, "name": "Rome" },
                    "as_of": "2026-11-12T09:00:00.000Z" } }
                """.utf8))
        #expect(info.leadName == "Tess")
        #expect(info.timeZone == "Europe/Rome")
        #expect(info.whereabouts?.area?.name == "Rome")
    }
}
