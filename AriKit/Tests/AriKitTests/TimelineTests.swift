import AriKit
import Foundation
import Testing

@Suite("The trail")
struct TimelineTests {
    @Test("while the turn runs, each step shows, and the running one shows its specifics")
    func live() throws {
        var replay = Replay(try Fixtures.transcript("04-the-agent-stirs"))
        try replay.play(throughLine: 30)
        let timeline = caughtUp(replay.conversation)
        // The first turn only thought, without a heading, so it left no trail.
        #expect(timeline.items.map(\.kind) == ["message", "message", "message", "trail"])
        let parts = try #require(trails(timeline).first?.parts)
        #expect(parts.count == 3)
        #expect(try lines(parts[0]).map(\.title) == ["Sketching a calm Saturday"])
        guard case .note(let note) = parts[1] else { throw TranscriptError("no note") }
        #expect(note.text == "I'll check which cafés by the river open early.")
        let run = try lines(parts[2])
        #expect(
            run.map(\.title) == [
                "Searched the web for riverside cafés open at 9am", "Reading saturday.md",
            ])
        #expect(run.map(\.isRunning) == [false, true])
        #expect(run[1].specifics == "cat notes/saturday.md")
        #expect(run[0].specifics == nil)
    }

    @Test("once the turn is over, a run of lines folds into one; a lone line stays as it is")
    func folds() throws {
        var replay = Replay(try Fixtures.transcript("04-the-agent-stirs"))
        try replay.play()
        let timeline = caughtUp(replay.conversation)
        #expect(
            timeline.items.map(\.kind) == ["message", "message", "message", "trail", "message"])
        let runs = try #require(trails(timeline).first).parts.compactMap(\.run)
        #expect(runs.map(\.isFolded) == [false, true])
        #expect(runs[1].summary == "Searched the web, read saturday.md, thought it through")
        #expect(runs[1].lines.allSatisfy { !$0.isRunning && $0.specifics == nil })
    }

    @Test("a step waits until the note before it is fully on screen")
    func waitsForTheNote() throws {
        var replay = Replay(try Fixtures.transcript("04-the-agent-stirs"))
        try replay.play(throughLine: 26)
        let conversation = replay.conversation
        let note = try #require(conversation["m_0002_90390"])
        let now = try #require(note.endedAt?.date)
        let reading = Timeline(conversation, reveal: Reveal(), at: now)
        let titles = trails(reading).flatMap(\.parts).compactMap(\.run).flatMap(\.lines).map(
            \.title)
        #expect(titles == ["Sketching a calm Saturday"])

        let titlesLater = trails(caughtUp(conversation)).flatMap(\.parts).compactMap(\.run)
            .flatMap(\.lines).map(\.title)
        #expect(titlesLater.last == "Searching the web for riverside cafés open at 9am")
    }

    @Test("a step stopped midway keeps its present tense, marked Stopped")
    func stopped() throws {
        var replay = Replay(try Fixtures.transcript("07-stop"))
        try replay.play()
        let timeline = caughtUp(replay.conversation)
        // The reply stopped before its first word shows nothing at all.
        #expect(!timeline.items.contains { $0.id == "m_0006_90669" })
        let last = try #require(trails(timeline).last)
        let line = try #require(last.parts.first?.run?.lines.first)
        #expect(line.title == "Searching the web for cafés near Battersea Park open at 9")
        #expect(line.mark == "Stopped" && !line.isRunning)
        #expect(last.parts.first?.run?.isFolded == false)
    }

    @Test("a working turn: the plan runs alongside the other steps, then everything folds")
    func workingTurn() throws {
        var replay = Replay(try Fixtures.transcript("16-working-through-a-task"))
        try replay.play(throughLine: 33)
        let live = try #require(trails(caughtUp(replay.conversation)).last?.parts.first?.run)
        #expect(
            live.lines.map(\.title) == [
                "Planning 3 steps", "Read packing.md", "Searched for “umbrella”", "Used weather",
                "Waiting 2 seconds",
            ])
        #expect(live.lines.map(\.isRunning) == [true, false, false, false, true])
        #expect(live.lines[0].steps[0].items?.count == 3)

        try replay.play()
        let done = try #require(trails(caughtUp(replay.conversation)).last?.parts.first?.run)
        #expect(done.isFolded)
        #expect(
            done.summary == "Planned 3 steps, read packing.md, searched for “umbrella” and 3 more")
    }

    @Test("similar steps in a row share a line, counted")
    func groups() throws {
        var story = TrailStory()
        story.read("s_1", 2, "a.md", ended: true)
        story.read("s_2", 3, "b.md", ended: true)
        story.read("s_3", 4, "c.md", ended: false)
        let running = try #require(trails(caughtUp(try story.build())).first?.parts.first?.run)
        #expect(running.lines.count == 1)
        #expect(running.lines[0].title == "Reading 3 files")
        #expect(running.lines[0].specifics == "cat c.md")

        story.end("s_3", 4)
        story.endTurn()
        let done = try #require(trails(caughtUp(try story.build())).first?.parts.first?.run)
        #expect(done.lines[0].title == "Read 3 files")
        // One counted line is already short, so it doesn't fold into a summary saying the same.
        #expect(!done.isFolded)
    }

    @Test("a long note stands as a message of its own, and the trail carries on after it")
    func longNote() throws {
        var story = TrailStory()
        story.read("s_1", 2, "a.md", ended: true)
        story.note("m_1", 3, #"Here's a poem:\n\nRoses by the river,\nrunners in the rain."#)
        story.read("s_2", 4, "b.md", ended: false)
        let timeline = caughtUp(try story.build())
        #expect(timeline.items.map(\.kind) == ["message", "trail", "message", "trail"])
        #expect(timeline.items.map(\.id)[2] == "m_1")
    }

    @Test("what Ari asks sits on the trail, and the trail stays open while it waits")
    func asks() throws {
        var replay = Replay(try Fixtures.transcript("19-ari-asks-before-acting"))
        try replay.play(throughLine: 21)
        let waiting = try #require(trails(caughtUp(replay.conversation)).last)
        guard case .ask(let ask) = waiting.parts.last else {
            throw TranscriptError("the ask isn't on the trail")
        }
        #expect(ask.outcome == nil && ask.question == "Which Juno did you mean?")
        #expect(waiting.parts.compactMap(\.run).allSatisfy { !$0.isFolded })

        try replay.play()
        let parts = trails(caughtUp(replay.conversation)).flatMap(\.parts)
        let settled = parts.compactMap { part -> Ask? in
            if case .ask(let ask) = part { ask } else { nil }
        }
        #expect(settled.map(\.outcome) == [.answered])
    }

    // MARK: - Helpers

    /// The timeline with every message already on screen.
    private func caughtUp(_ conversation: Conversation) -> Timeline {
        var reveal = Reveal()
        reveal.showAll(conversation)
        return Timeline(conversation, reveal: reveal)
    }

    private func trails(_ timeline: Timeline) -> [Trail] {
        timeline.items.compactMap {
            if case .trail(let trail) = $0 { trail } else { nil }
        }
    }

    private func lines(_ part: Trail.Part) throws -> [StepLine] {
        try #require(part.run).lines
    }
}

extension Timeline.Item {
    fileprivate var kind: String {
        switch self {
        case .message: "message"
        case .trail: "trail"
        case .call: "call"
        case .topic: "topic"
        }
    }
}

extension Trail.Part {
    fileprivate var run: StepRun? {
        if case .steps(let run) = self { run } else { nil }
    }
}

/// One turn, built from events: your message at position 1, then steps and notes.
private struct TrailStory {
    private let at = "2026-10-12T08:41:00.000Z"
    private var events: [String] = []

    init() {
        add(
            #""type":"message.accepted","message":{"id":"u_1","role":"user","text":"Hi","at":"\#(at)","position":1}"#
        )
        add(#""type":"turn.started","turn":"t_1","inputs":["u_1"]"#)
    }

    mutating func read(_ id: String, _ position: Int, _ path: String, ended: Bool) {
        add(step(id, position, ended: false, path: path))
        if ended { end(id, position, path: path) }
    }

    mutating func end(_ id: String, _ position: Int, path: String? = nil) {
        let path = path ?? ["s_1": "a.md", "s_2": "b.md", "s_3": "c.md"][id] ?? "x.md"
        add(step(id, position, ended: true, path: path))
    }

    mutating func note(_ id: String, _ position: Int, _ text: String) {
        add(
            #""type":"message.started","message":{"id":"\#(id)","role":"agent","kind":"note","turn":"t_1","text":"","at":"\#(at)","position":\#(position)}"#
        )
        add(#""type":"message.delta","message":"\#(id)","offset":0,"text":"\#(text)""#)
        let length = text.replacingOccurrences(of: #"\n"#, with: "\n").utf16.count
        add(
            #""type":"message.ended","message":"\#(id)","outcome":"completed","length":\#(length)"#
        )
    }

    mutating func endTurn() {
        add(#""type":"turn.ended","turn":"t_1","outcome":"completed""#)
    }

    func build() throws -> Conversation {
        var conversation = Conversation()
        for (index, body) in events.enumerated() {
            let json = #"{"id":"e_\#(index + 1)","at":"\#(at)",\#(body)}"#
            conversation.apply(try JSONValue(json: json).decode(Event.self))
        }
        return conversation
    }

    private func step(_ id: String, _ position: Int, ended: Bool, path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let title = ended ? "Read \(name)" : "Reading \(name)"
        let end = ended ? #","outcome":"completed","ended_at":"\#(at)""# : ""
        return
            #""type":"step.\#(ended ? "ended" : "started")","step":{"id":"\#(id)","turn":"t_1","kind":"command","title":"\#(title)","at":"\#(at)","position":\#(position),"command":"cat \#(path)","actions":[{"type":"read","path":"\#(path)"}]\#(end)}"#
    }

    private mutating func add(_ body: String) {
        events.append(body)
    }
}
