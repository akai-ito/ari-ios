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

    // MARK: - Full access and the dream's time (protocol 0.20, ahead of the pin)

    @Test("full access is read, turned on with a body that says it's meant, and turned off")
    func fullAccess() async throws {
        let server = ScriptedServer()
        let client = try client(server)

        let reading = Task { try await client.access() }
        let read = try await request(from: server)
        #expect(read.method == .get && read.path == "/v0/access")
        try await server.answer(200, json: #"{ "mode": "sandboxed" }"#)
        #expect(try await reading.value == .sandboxed)

        let giving = Task { try await client.giveFullAccess() }
        let give = try await request(from: server)
        #expect(give.method == .post && give.path == "/v0/access/full")
        #expect(give.headers["Content-Type"] == "application/json")
        #expect(try json(give) == JSONValue(json: #"{ "confirm": true }"#))
        try await server.answer(
            200, json: #"{ "mode": "full", "since": "2026-11-27T14:02:00.000Z" }"#)
        let full = try await giving.value
        #expect(full.isFull && full.since == Timestamp("2026-11-27T14:02:00.000Z"))

        let ending = Task { try await client.endFullAccess() }
        let end = try await request(from: server)
        #expect(end.method == .delete && end.path == "/v0/access/full" && end.body == nil)
        try await server.answer(200, json: #"{ "mode": "sandboxed" }"#)
        #expect(try await ending.value == .sandboxed)
    }

    @Test("a mode Ari doesn't know isn't full access, so no marker shows for it")
    func unknownAccessMode() throws {
        let access = try JSONDecoder().decode(
            Access.self, from: Data(#"{ "mode": "supervised" }"#.utf8))
        #expect(!access.isFull && access.mode.rawValue == "supervised")
    }

    @Test("the dream's time and latest dream are read, and the time is set as HH:mm")
    func dreamTime() async throws {
        let server = ScriptedServer()
        let client = try client(server)
        let state = #"""
            { "time": "04:00", "next_at": "2026-11-28T04:00:00.000Z",
              "latest": { "id": "d_1", "day": "2026-11-26", "trigger": "scheduled",
                "started_at": "2026-11-27T04:00:00.000Z", "ended_at": "2026-11-27T04:31:00.000Z",
                "headline": "A quiet Wednesday", "lines": [{ "group": "planned", "text": "Moved the run" }],
                "seen_at": "2026-11-27T07:40:00.000Z" } }
            """#

        let reading = Task { try await client.dreamSchedule() }
        let read = try await request(from: server)
        #expect(read.method == .get && read.path == "/v0/dream")
        try await server.answer(200, json: state)
        let schedule = try await reading.value
        #expect(schedule.time == .standard && schedule.dreaming == nil)
        #expect(schedule.latest?.trigger == .scheduled)
        #expect(schedule.latest?.endedAt == Timestamp("2026-11-27T04:31:00.000Z"))

        let setting = Task { try await client.changeDreamTime(to: try #require(.init("03:30"))) }
        let set = try await request(from: server)
        #expect(set.method == .put && set.path == "/v0/dream/time")
        #expect(try json(set) == JSONValue(json: #"{ "time": "03:30" }"#))
        try await server.answer(
            200, json: state.replacingOccurrences(of: "04:00\"", with: "03:30\""))
        #expect(try await setting.value.time.description == "03:30")
    }

    @Test("a dream under way decodes, and a dream time must be a real time of day")
    func dreaming() throws {
        let schedule = try JSONDecoder().decode(
            DreamSchedule.self,
            from: Data(
                #"""
                { "time": "23:45", "next_at": "2026-11-28T23:45:00.000Z",
                  "dreaming": { "since": "2026-11-27T14:20:00.000Z", "trigger": "manual" } }
                """#.utf8))
        #expect(schedule.dreaming?.trigger == .manual && schedule.latest == nil)
        #expect(DreamSchedule.Time("24:00") == nil && DreamSchedule.Time("4:00") == nil)
        #expect(DreamSchedule.Time(hour: 7, minute: 5)?.description == "07:05")
    }

    @Test("Last dream says the day, the start and how long: Today 04:00 · 31 min")
    func lastDreamSummary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        calendar.locale = Locale(identifier: "en_GB")
        func dream(_ start: String, _ end: String) throws -> DreamSchedule.LastDream {
            DreamSchedule.LastDream(
                trigger: .scheduled, startedAt: try #require(Timestamp(start)),
                endedAt: try #require(Timestamp(end)))
        }
        let now = try #require(Timestamp("2026-11-27T16:40:00.000Z")).date
        #expect(
            try dream("2026-11-27T04:00:00.000Z", "2026-11-27T04:31:00.000Z")
                .summary(now: now, calendar: calendar) == "Today 04:00 · 31 min")
        #expect(
            try dream("2026-11-26T04:00:00.000Z", "2026-11-26T06:05:00.000Z")
                .summary(now: now, calendar: calendar) == "Yesterday 04:00 · 2 hr 5 min")
        #expect(
            try dream("2026-11-27T14:20:00.000Z", "2026-11-27T14:20:20.000Z")
                .summary(now: now, calendar: calendar) == "Today 14:20 · 1 min")
        #expect(
            try dream("2026-11-23T04:00:00.000Z", "2026-11-23T05:00:00.000Z")
                .summary(now: now, calendar: calendar).hasSuffix("04:00 · 1 hr"))
    }
}
