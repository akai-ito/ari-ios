import AriKit
import Testing

/// What the golden transcripts don't exercise: other devices, every answer to Stop, text outside the
/// Basic Multilingual Plane, snapshots taken mid-turn, a stream that breaks its promises, and what a
/// newer server might send.
@Suite("The store, beyond the transcripts")
struct ConversationEdgeTests {
    @Test(
        "events of types Ari doesn't know change nothing but the cursor",
        arguments: try Fixtures.transcripts())
    func unknownEvents(_ transcript: Transcript) throws {
        var plain = Replay(transcript)
        try plain.play()
        let mixed = try transcript.replacingSteps { step in
            guard case .event(let logged) = step, let id = logged.event.id else { return [step] }
            var json = try JSONValue(
                json: #"{"type":"future.thing","at":"2026-10-12T08:41:00.000Z"}"#)
            json["id"] = .string("\(id)-future")
            return [
                step,
                .event(.init(line: logged.line, json: json, event: try json.decode(Event.self))),
            ]
        }
        var replay = Replay(mixed)
        try replay.play()  // Replay checks that each unknown event's id became the cursor.
        #expect(replay.conversation.entries == plain.conversation.entries)
        #expect(replay.conversation.turn == plain.conversation.turn)
        #expect(replay.conversation.lastEndedTurn == plain.conversation.lastEndedTurn)
        #expect(replay.conversation.retriedTurns == plain.conversation.retriedTurns)
    }

    @Test("your message waits below the server's, even another device's, and appears once")
    func yourMessages() throws {
        var conversation = Conversation()
        conversation.send("mine", text: "From the iPhone")
        // The Mac's message is accepted while yours is on its way, so it goes above yours.
        try conversation.apply(.accepted("e_1", message: "mac", text: "From the Mac"))
        #expect(conversation.entries.map(\.id) == ["mac", "mine"])
        #expect(conversation["mine"]?.delivery == .sending)

        // The 201 confirms yours: Sending goes and the server's time arrives, but its place waits.
        conversation.confirm(try MessageResult.fixture(id: "mine", text: "From the iPhone"))
        #expect(conversation["mine"]?.delivery == .delivered)
        #expect(conversation["mine"]?.at?.rawValue == "2026-10-12T08:40:00.000Z")
        // A reply that begins before yours is accepted began first, so it goes above yours too.
        try conversation.apply(.started("e_2", message: "reply", turn: "t_1"))
        #expect(conversation.entries.map(\.id) == ["mac", "reply", "mine"])
        try conversation.apply(.accepted("e_3", message: "mine", text: "From the iPhone"))
        #expect(conversation.entries.map(\.id) == ["mac", "reply", "mine"])

        // One still Sending (its answer lost) that a snapshot includes appears once, as delivered.
        conversation.send("again", text: "Answer lost on the way")
        try conversation.apply(Fixture.event(Fixture.snapshotIncluding("again")))
        #expect(conversation.entries.map(\.id) == ["again"])
        #expect(conversation["again"]?.delivery == .delivered)
    }

    @Test("Stop holds the cut until the turn ends, however the server answers")
    func stopAnswers() throws {
        var conversation = try streaming(["Hello, ", "world, ", "and more."])
        try conversation.apply(
            .accepted("e_q", message: "question", text: "A question longer than the cut"))
        conversation.stop(turn: "t_1", cut: Cut(message: "m_1", revealed: "Hello, "))
        #expect(try visible("m_1", in: conversation) == "Hello, ")
        #expect(try visible("question", in: conversation) == "A question longer than the cut")

        conversation.confirm(try StopResult.fixture(state: "stopping"))
        #expect(try visible("m_1", in: conversation) == "Hello, ")
        // A Stop sent again after the signal dropped finds the turn already stopped: still frozen
        // until the stream says where the message ended.
        conversation.confirm(try StopResult.fixture(state: "ended", outcome: "stopped"))
        #expect(try visible("m_1", in: conversation) == "Hello, ")
        try conversation.apply(.ended("e_8", message: "m_1", outcome: "stopped", length: 7))
        try conversation.apply(.turnEnded("e_9", turn: "t_1", outcome: "stopped"))
        #expect(conversation.pendingStop == nil)
        #expect(try visible("m_1", in: conversation) == "Hello, ")

        // The reply had finished before the server got the Stop, so it shows in full at once.
        var finished = try streaming(["Hello, ", "world."])
        finished.stop(turn: "t_1", cut: Cut(message: "m_1", revealed: "Hello, "))
        finished.confirm(try StopResult.fixture(state: "ended", outcome: "completed"))
        #expect(finished.pendingStop == nil)
        #expect(try visible("m_1", in: finished) == "Hello, world.")

        // A snapshot without the stopped turn drops the Stop; one with it keeps it.
        var kept = try streaming(["Half a rep"])
        kept.stop(turn: "t_1", cut: Cut(message: "m_1", revealed: "Half"))
        try kept.apply(Fixture.event(Fixture.midTurnSnapshot))
        #expect(kept.pendingStop?.turn == "t_1")
        try kept.apply(Fixture.event(Fixture.snapshotIncluding("u_9")))
        #expect(kept.pendingStop == nil)
    }

    @Test("a retry started anywhere hides Try again, and a turn's end closes what it left open")
    func turns() throws {
        // Try again tapped on the Mac: the iPhone learns of it from turn.started alone.
        var conversation = Conversation()
        try conversation.apply(.turnStarted("e_1", turn: "t_2", inputs: ["u_1"], retryOf: "t_1"))
        #expect(conversation.retriedTurns == ["t_1"])
        // Or from a snapshot taken while the retry runs.
        var restored = Conversation()
        try restored.apply(Fixture.event(Fixture.midTurnSnapshot))
        #expect(restored.retriedTurns == ["t_0"])

        // Nothing about a turn follows its end, so a message it left open ends with it.
        var open = try streaming(["Half a"])
        try open.apply(.turnEnded("e_9", turn: "t_1", outcome: "failed"))
        #expect(open["m_1"]?.outcome == .failed)
        #expect(open["m_1"]?.text == "Half a")
        #expect(open.turn == nil)
    }

    @Test("a step finds its place by position, and a turn's end closes one it left running")
    func steps() throws {
        var conversation = try streaming(["Half a"])
        try conversation.apply(
            .step("e_5", "step.started", step: "s_2", position: 20, title: "Reading notes.md"))
        // One that arrives late still goes before it.
        try conversation.apply(
            .step("e_6", "step.started", step: "s_1", position: 10, title: "Thinking it through"))
        #expect(conversation.steps.map(\.id) == ["s_1", "s_2"])
        try conversation.apply(
            .step("e_7", "step.updated", step: "s_2", position: 20, title: "Reading notes.md"))
        #expect(conversation.steps.count == 2)

        try conversation.apply(.turnEnded("e_9", turn: "t_1", outcome: "stopped"))
        #expect(conversation[step: "s_2"]?.outcome == .stopped)
        #expect(conversation[step: "s_2"]?.title == "Reading notes.md")
    }

    /// Every transcript string has as many characters as UTF-16 units, so these are what would catch
    /// offsets counted in characters.
    @Test("offsets and lengths count UTF-16 units, not characters")
    func utf16() throws {
        let pieces = ["Thumbs 👍🏽 and ", "family 👨‍👩‍👧 at the ", "cafe\u{301}\r\n", "done."]
        #expect(pieces.joined().utf16.count == 51)
        #expect(pieces.joined().count == 39)  // "\r\n" is one character, two units.

        var conversation = try streaming(pieces)
        #expect(conversation["m_1"]?.length == 51)
        try conversation.apply(.ended("e_9", message: "m_1", outcome: "completed", length: 51))
        #expect(conversation["m_1"]?.text == pieces.joined())

        // Stopped after the second piece: exactly the first two, not a unit more.
        var stopped = try streaming(pieces)
        try stopped.apply(.ended("e_9", message: "m_1", outcome: "stopped", length: 39))
        #expect(stopped["m_1"]?.text == pieces[0] + pieces[1])
        #expect(stopped["m_1"]?.length == 39)

        // A length inside a surrogate pair rounds down rather than break the emoji.
        var split = try streaming(pieces)
        try split.apply(.ended("e_9", message: "m_1", outcome: "stopped", length: 8))
        #expect(split["m_1"]?.text == "Thumbs ")
        #expect(split["m_1"]?.length == 7)

        // An offset counted in characters is a gap.
        var counted = try streaming([pieces[0]])
        try counted.apply(.delta("e_6", message: "m_1", offset: pieces[0].count, text: pieces[1]))
        #expect(counted.needsSnapshot)

        // A cut made from the text on screen can't split a pair.
        #expect(Cut(message: "m_1", revealed: "Thumbs 👍🏽").offset == 11)
    }

    @Test("a snapshot taken mid-turn restores the turn, Read, Next and the reply so far")
    func snapshotMidTurn() throws {
        let late = "Confirmed after the snapshot was taken"
        var conversation = Conversation()
        conversation.send("unsent", text: "Still on its way")
        conversation.send("confirmed", text: late)
        conversation.confirm(try MessageResult.fixture(id: "confirmed", text: late))

        try conversation.apply(Fixture.event(Fixture.midTurnSnapshot))
        let restored: [MessageID] = ["u_1", "m_1", "u_3", "u_2", "unsent", "confirmed"]
        #expect(conversation.entries.map(\.id) == restored)
        #expect(conversation.cursor == "e_10")
        #expect(conversation.hasEarlierMessages)
        #expect(conversation.turn?.id == "t_1" && conversation.turn?.status?.label == "Writing")
        #expect(conversation["u_3"]?.mark == .read)
        #expect(conversation["u_2"]?.mark == .next)
        #expect(conversation["unsent"]?.delivery == .sending)
        #expect(conversation["confirmed"]?.delivery == .delivered)

        // The server accepted it after taking the snapshot, so now it takes its place.
        try conversation.apply(.accepted("e_11", message: "confirmed", text: late))
        let placed: [MessageID] = ["u_1", "m_1", "u_3", "u_2", "confirmed", "unsent"]
        #expect(conversation.entries.map(\.id) == placed)

        try conversation.apply(.delta("e_12", message: "m_1", offset: 10, text: "ly."))
        try conversation.apply(.ended("e_13", message: "m_1", outcome: "completed", length: 13))
        try conversation.apply(.turnEnded("e_14", turn: "t_1", outcome: "completed"))
        #expect(conversation["m_1"]?.text == "Half a reply.")
        #expect(conversation.turn == nil)
        #expect(conversation["u_3"]?.mark == nil)
        #expect(conversation["u_2"]?.mark == .next)

        try conversation.apply(.turnStarted("e_15", turn: "t_2", inputs: ["u_2"]))
        #expect(conversation["u_2"]?.mark == nil)
    }

    @Test("a piece it already has changes nothing; a gap stops everything until a snapshot")
    func replaysAndGaps() throws {
        var conversation = try streaming(["Hello, "])
        let before = conversation["m_1"]
        try conversation.apply(.delta("e_6", message: "m_1", offset: 0, text: "Hello, "))
        #expect(conversation["m_1"] == before)
        #expect(!conversation.needsSnapshot && conversation.cursor == "e_6")

        try conversation.apply(.delta("e_7", message: "m_1", offset: 0, text: "Howdy, "))
        #expect(conversation.needsSnapshot && conversation.cursor == nil)
        try conversation.apply(.delta("e_8", message: "m_1", offset: 7, text: "world"))
        #expect(conversation["m_1"]?.text == "Hello, ")
        #expect(conversation.cursor == nil)

        try conversation.apply(Fixture.event(Fixture.midTurnSnapshot))
        #expect(!conversation.needsSnapshot && conversation.cursor == "e_10")
    }

    @Test("what the server promises never to send changes nothing, or asks for a snapshot")
    func brokenPromises() throws {
        var conversation = try streaming(["Hello"])
        try conversation.apply(.accepted("e_u", message: "u_1", text: "Hi"))
        // A message that begins twice is still one message.
        try conversation.apply(Fixture.event(Fixture.started))
        #expect(conversation.entries.filter { $0.id == "m_1" }.count == 1)
        // Read is for your messages, and only for the running turn.
        try conversation.apply(.read("e_r1", message: "m_1", turn: "t_1"))
        try conversation.apply(.read("e_r2", message: "u_1", turn: "t_other"))
        #expect(conversation["m_1"]?.mark == nil && conversation["u_1"]?.mark == nil)
        #expect(!conversation.needsSnapshot)

        // Each of these asks for a snapshot instead of a guess, and none of them crashes.
        let broken: [FixtureEvent] = [
            .ended("e_9", message: "m_1", outcome: "completed", length: 50),
            .ended("e_9", message: "m_1", outcome: "completed", length: -1),
            .delta("e_9", message: "m_1", offset: Int.max, text: "x"),
            .delta("e_9", message: "nobody", offset: 0, text: "x"),
            .ended("e_9", message: "nobody", outcome: "completed", length: 0),
        ]
        for event in broken {
            var copy = try streaming(["Hello"])
            try copy.apply(event)
            #expect(copy.needsSnapshot, "\(event)")
        }
        // So does text after its message ended.
        var late = try streaming(["Hello"])
        try late.apply(.ended("e_8", message: "m_1", outcome: "completed", length: 5))
        try late.apply(.delta("e_9", message: "m_1", offset: 5, text: "!"))
        #expect(late.needsSnapshot)
    }

    @Test("roles and kinds Ari doesn't know keep their place, hidden")
    func unknownRolesAndKinds() throws {
        var conversation = Conversation()
        try conversation.apply(.accepted("e_1", message: "rule", text: "Be brief.", role: "system"))
        try conversation.apply(.started("e_2", message: "aside", turn: "t_1", kind: "aside"))
        try conversation.apply(.accepted("e_3", message: "you", text: "Hi"))
        #expect(conversation.entries.map(\.id) == ["rule", "aside", "you"])
        #expect(conversation.entries.map(\.isShown) == [false, false, true])
    }

    @Test("a page of earlier messages that no longer fits is dropped")
    func stalePage() throws {
        var conversation = Conversation()
        try conversation.apply(Fixture.event(Fixture.midTurnSnapshot))
        let page = try JSONValue(json: Fixture.page).decode(MessagePage.self)
        conversation.insertEarlier(page, before: "someone-else")
        #expect(conversation.entries.first?.id == "u_1")
        conversation.insertEarlier(page, before: "u_1")
        #expect(conversation.entries.first?.id == "u_0")
        #expect(!conversation.hasEarlierMessages)
    }

    /// A conversation whose agent reply `m_1`, in turn `t_1`, has streamed `pieces`, each at its
    /// UTF-16 offset.
    private func streaming(_ pieces: [String]) throws -> Conversation {
        var conversation = Conversation()
        try conversation.apply(.turnStarted("e_1", turn: "t_1", inputs: ["u_1"]))
        try conversation.apply(Fixture.event(Fixture.started))
        var offset = 0
        for (index, piece) in pieces.enumerated() {
            try conversation.apply(
                .delta("e_\(index + 2)", message: "m_1", offset: offset, text: piece))
            offset += piece.utf16.count
        }
        return conversation
    }

    private func visible(_ id: MessageID, in conversation: Conversation) throws -> String {
        conversation.visibleText(of: try #require(conversation[id]))
    }
}

private enum Fixture {
    static func event(_ json: String) throws -> Event {
        try JSONValue(json: json).decode(Event.self)
    }

    static let started = #"""
        {"id":"e_1b","type":"message.started","at":"2026-10-12T08:41:01.000Z",
         "message":{"id":"m_1","role":"agent","kind":"reply","turn":"t_1","text":"","at":"2026-10-12T08:41:01.000Z"}}
        """#

    static let midTurnSnapshot = #"""
        {"id":"e_10","type":"snapshot","at":"2026-10-12T08:41:05.000Z","reason":"too_far_behind","has_more":true,
         "messages":[
           {"id":"u_1","role":"user","text":"Plan my day","at":"2026-10-12T08:41:00.000Z"},
           {"id":"m_1","role":"agent","kind":"reply","turn":"t_1","text":"Half a rep","at":"2026-10-12T08:41:01.000Z"},
           {"id":"u_3","role":"user","text":"Also dinner","at":"2026-10-12T08:41:02.000Z"},
           {"id":"u_2","role":"user","text":"Also lunch","at":"2026-10-12T08:41:03.000Z"}],
         "steps":[],"asks":[],
         "turn":{"id":"t_1","inputs":["u_1"],"read":["u_3"],"retry_of":"t_0",
                 "status":{"kind":"writing","label":"Writing"}},
         "next":["u_2"]}
        """#

    /// A snapshot of an idle conversation holding one message of yours.
    static func snapshotIncluding(_ id: String) -> String {
        #"""
        {"id":"e_20","type":"snapshot","at":"2026-10-12T08:42:00.000Z","reason":"cursor_unknown","has_more":false,
         "messages":[{"id":"\#(id)","role":"user","text":"Answer lost on the way","at":"2026-10-12T08:41:50.000Z"}],
         "steps":[],"asks":[],"turn":null,"next":[]}
        """#
    }

    static let page = #"""
        {"has_more":false,"steps":[],"asks":[],"messages":[{"id":"u_0","role":"user","text":"Morning","at":"2026-10-11T08:00:00.000Z"}]}
        """#
}

extension MessageResult {
    fileprivate static func fixture(id: String, text: String) throws -> MessageResult {
        let message: JSONValue = .object([
            "id": .string(id), "role": "user", "text": .string(text),
            "at": "2026-10-12T08:40:00.000Z",
        ])
        return try JSONValue.object(["message": message]).decode(MessageResult.self)
    }
}

extension StopResult {
    fileprivate static func fixture(state: String, outcome: String? = nil) throws -> StopResult {
        var json: JSONValue = .object(["turn": "t_1", "state": .string(state)])
        if let outcome { json["outcome"] = .string(outcome) }
        return try json.decode(StopResult.self)
    }
}

extension Conversation {
    fileprivate mutating func apply(_ event: FixtureEvent) throws {
        apply(try event.decoded())
    }
}

/// Events for these tests, written out as the server would send them.
private enum FixtureEvent: CustomStringConvertible {
    case accepted(String, message: String, text: String, role: String = "user")
    case started(String, message: String, turn: String, kind: String = "reply")
    case read(String, message: String, turn: String)
    case turnStarted(String, turn: String, inputs: [String], retryOf: String? = nil)
    case delta(String, message: String, offset: Int, text: String)
    case ended(String, message: String, outcome: String, length: Int)
    case turnEnded(String, turn: String, outcome: String)
    /// A step of turn t_1, as it now stands.
    case step(String, String, step: String, position: Int, title: String)

    var description: String {
        "\(fields["type"]?.string ?? "event") \(fields["id"]?.string ?? "")"
    }

    func decoded() throws -> Event {
        try JSONValue.object(fields).decode(Event.self)
    }

    private var fields: [String: JSONValue] {
        let at: JSONValue = "2026-10-12T08:41:02.000Z"
        switch self {
        case .accepted(let id, let message, let text, let role):
            let body: JSONValue = .object([
                "id": .string(message), "role": .string(role), "text": .string(text), "at": at,
            ])
            return ["id": .string(id), "type": "message.accepted", "at": at, "message": body]
        case .started(let id, let message, let turn, let kind):
            let body: JSONValue = .object([
                "id": .string(message), "role": "agent", "kind": .string(kind),
                "turn": .string(turn),
                "text": "", "at": at,
            ])
            return ["id": .string(id), "type": "message.started", "at": at, "message": body]
        case .read(let id, let message, let turn):
            return [
                "id": .string(id), "type": "message.read", "at": at, "message": .string(message),
                "turn": .string(turn),
            ]
        case .turnStarted(let id, let turn, let inputs, let retryOf):
            var fields: [String: JSONValue] = [
                "id": .string(id), "type": "turn.started", "at": at, "turn": .string(turn),
                "inputs": .array(inputs.map(JSONValue.string)),
            ]
            if let retryOf { fields["retry_of"] = .string(retryOf) }
            return fields
        case .delta(let id, let message, let offset, let text):
            return [
                "id": .string(id), "type": "message.delta", "at": at, "message": .string(message),
                "offset": .int(offset), "text": .string(text),
            ]
        case .ended(let id, let message, let outcome, let length):
            return [
                "id": .string(id), "type": "message.ended", "at": at, "message": .string(message),
                "outcome": .string(outcome), "length": .int(length),
            ]
        case .turnEnded(let id, let turn, let outcome):
            return [
                "id": .string(id), "type": "turn.ended", "at": at, "turn": .string(turn),
                "outcome": .string(outcome),
            ]
        case .step(let id, let type, let step, let position, let title):
            let body: JSONValue = .object([
                "id": .string(step), "turn": "t_1", "kind": "command", "title": .string(title),
                "at": at, "position": .int(position),
            ])
            return ["id": .string(id), "type": .string(type), "at": at, "step": body]
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}
