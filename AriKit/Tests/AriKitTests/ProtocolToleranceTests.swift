import AriKit
import Testing

/// The protocol's tolerance rules, tried on real transcript lines changed to carry what a newer server
/// might send.
@Suite("Tolerating what Ari doesn't know")
struct ProtocolToleranceTests {
    @Test(
        "fields it doesn't know are ignored, at every level", arguments: try Fixtures.transcripts())
    func unknownFields(_ transcript: Transcript) throws {
        for logged in transcript.events {
            let extended = logged.json.addingUnknownFields()
            #expect(
                try extended.decode(Event.self) == logged.event,
                "\(transcript.name).jsonl line \(logged.line)")
        }
    }

    @Test(
        "a type it doesn't know decodes, keeping its id for the cursor",
        arguments: try Fixtures.transcripts())
    func unknownTypes(_ transcript: Transcript) throws {
        for logged in transcript.events {
            var renamed = logged.json
            renamed["type"] = .string("future." + (logged.json["type"]?.string ?? "thing"))
            let event = try renamed.decode(Event.self)
            #expect(event.payload == .unknown, "\(transcript.name).jsonl line \(logged.line)")
            #expect(event.id == logged.event.id, "\(transcript.name).jsonl line \(logged.line)")
        }
    }

    @Test("a type it doesn't know needs nothing but its envelope")
    func bareUnknownType() throws {
        let event = try JSONValue(json: #"{"id":"e_0099_00001","type":"future.thing"}"#).decode(
            Event.self)
        #expect(event.payload == .unknown)
        #expect(event.id == "e_0099_00001")
        #expect(try JSONValue(json: #"{"type":"future.thing"}"#).decode(Event.self).id == nil)
    }

    @Test("values it doesn't know decode and keep their text")
    func unknownValues() throws {
        let status = try changed("04-the-agent-stirs", "turn.status") {
            $0["kind"] = .string("dreaming")
        }
        guard case .turnStatus(let update) = status.payload else {
            throw TranscriptError("not a status")
        }
        #expect(update.kind == StatusKind(rawValue: "dreaming") && !update.kind.isKnown)
        #expect(update.label == "Thinking")

        let ended = try changed("05-the-reply-streams", "message.ended") {
            $0["outcome"] = .string("abandoned")
        }
        guard case .messageEnded(let end) = ended.payload else {
            throw TranscriptError("not an end")
        }
        #expect(end.outcome.rawValue == "abandoned" && !end.outcome.isKnown)

        let started = try changed("04-the-agent-stirs", "message.started") {
            $0["message"]?["kind"] = .string("aside")
        }
        guard case .messageStarted(let start) = started.payload else {
            throw TranscriptError("not a start")
        }
        #expect(start.message.kind?.rawValue == "aside")

        let accepted = try changed("03-send", "message.accepted") {
            $0["message"]?["role"] = .string("system")
        }
        guard case .messageAccepted(let accept) = accepted.payload else {
            throw TranscriptError("not accepted")
        }
        #expect(accept.message.role.rawValue == "system" && !accept.message.role.isKnown)

        let snapshot = try changed("14-the-server-restarts-or-is-restored", "snapshot") {
            $0["reason"] = .string("server_moved")
        }
        guard case .snapshot(let view) = snapshot.payload else {
            throw TranscriptError("not a snapshot")
        }
        #expect(view.reason.rawValue == "server_moved")

        let failed = try changed("15-something-fails", "message.ended", outcome: "failed") {
            $0["error"]?["code"] = .string("disk_on_fire")
        }
        guard case .messageEnded(let failure) = failed.payload else {
            throw TranscriptError("not an end")
        }
        #expect(failure.error?.code.rawValue == "disk_on_fire")
        #expect(failure.error?.message == "The model didn't respond for 60 seconds.")

        let stop = try JSONValue(json: #"{"turn":"t_0002_40331","state":"pondering"}"#).decode(
            StopResult.self)
        #expect(stop.state.rawValue == "pondering" && !stop.state.isKnown)
    }

    @Test("an error without its optional detail decodes")
    func errorWithoutDetail() throws {
        let failed = try changed("15-something-fails", "message.ended", outcome: "failed") {
            $0["error"]?["detail"] = nil
        }
        guard case .messageEnded(let failure) = failed.payload else {
            throw TranscriptError("not an end")
        }
        #expect(failure.error?.code == .modelTimeout)
        #expect(failure.error?.detail == nil)
    }

    /// No transcript has a snapshot taken mid-turn, so this one is made from scenario 14's.
    @Test("a snapshot taken mid-turn carries the turn, its status, Read and Next")
    func liveTurn() throws {
        let snapshot = try changed("14-the-server-restarts-or-is-restored", "snapshot") {
            $0["has_more"] = .bool(true)
            $0["next"] = .array([.string("next-message")])
            $0["turn"] = try JSONValue(
                json: #"""
                    {"id":"t_0009_00001","inputs":["bafdbba2-d851-4593-bc68-fdb68d9ab705"],"read":["read-message"],
                     "retry_of":"t_0008_00001","status":{"kind":"working","label":"Searching the web","detail":"cafés"}}
                    """#)
        }
        guard case .snapshot(let view) = snapshot.payload else {
            throw TranscriptError("not a snapshot")
        }
        let turn = try #require(view.turn)
        #expect(
            turn.id == "t_0009_00001" && turn.inputs == ["bafdbba2-d851-4593-bc68-fdb68d9ab705"])
        #expect(turn.read == ["read-message"] && turn.retryOf == "t_0008_00001")
        #expect(turn.status == Status(kind: .working, label: "Searching the web", detail: "cafés"))
        #expect(view.hasMore && view.next == ["next-message"])

        let quiet = try changed("14-the-server-restarts-or-is-restored", "snapshot") {
            $0["turn"] = try JSONValue(
                json: #"{"id":"t_1","inputs":["m"],"read":[],"status":null}"#)
        }
        guard case .snapshot(let early) = quiet.payload else {
            throw TranscriptError("not a snapshot")
        }
        #expect(early.turn?.status == nil)
    }

    /// The first event of `type` in a transcript (with `outcome`, if given), changed by `change` and
    /// decoded again.
    private func changed(
        _ name: String, _ type: String, outcome: String? = nil,
        _ change: (inout JSONValue) throws -> Void
    ) throws -> Event {
        let transcript = try Fixtures.transcript(name)
        let logged = transcript.events.first {
            $0.json["type"]?.string == type
                && (outcome == nil || $0.json["outcome"]?.string == outcome)
        }
        var json = try #require(logged).json
        try change(&json)
        return try json.decode(Event.self)
    }
}

extension JSONValue {
    /// This value with a field no version of the protocol defines added to every object in it.
    func addingUnknownFields() -> JSONValue {
        switch self {
        case .object(let object):
            var extended = object.mapValues { $0.addingUnknownFields() }
            extended["x_from_the_future"] = .object([
                "nested": .array([.int(1), .string("two"), .null])
            ])
            return .object(extended)
        case .array(let array):
            return .array(array.map { $0.addingUnknownFields() })
        default:
            return self
        }
    }
}
