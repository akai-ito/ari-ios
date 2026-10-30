import AriKit
import Testing

/// Each golden transcript played against the store. ``Replay`` checks the rules that hold at every
/// step; these tests check where each scenario ends, and the moments in between that matter.
@Suite("The store, scenario by scenario")
struct ConversationTranscriptTests {
    @Test(
        "every transcript ends in the state its scenario describes",
        arguments: try Fixtures.transcripts())
    func endState(_ transcript: Transcript) throws {
        var replay = Replay(transcript)
        try replay.play()
        let conversation = replay.conversation

        #expect(conversation.turn == nil, "the agent is still working")
        #expect(conversation.pendingStop == nil, "a Stop is still pending")
        for entry in conversation.entries {
            if entry.role == .agent { #expect(entry.outcome != nil, "\(entry.id) never ended") }
            if let streamed = replay.streamed[entry.id] {
                #expect(
                    Array(entry.text.utf16) == streamed, "\(entry.id) isn't the text that streamed")
            }
        }
        expect(conversation, holds: Self.end(of: transcript))
    }

    @Test("Scenario 3: your message shows at once, and Sending goes when the server has it")
    func send() throws {
        var replay = Replay(try Fixtures.transcript("03-send"))
        let mine: MessageID = "69a52e25-a392-4a73-89f9-21eb36005baf"
        try replay.play(throughLine: 13, expecting: "POST /v0/messages")
        #expect(replay.conversation.entries.last?.id == mine)
        #expect(replay.conversation[mine]?.delivery == .sending)
        #expect(replay.conversation[mine]?.at == nil)
        #expect(replay.conversation[mine]?.position == nil)

        // Accepted on the stream before the 201 arrives, and placed in the server's order.
        try replay.play(throughLine: 14, expecting: "message.accepted e_0010_63492")
        #expect(replay.conversation[mine]?.delivery == .delivered)
        #expect(replay.conversation[mine]?.at?.rawValue == "2026-10-12T08:41:02.000Z")
        #expect(replay.conversation[mine]?.position != nil)

        try replay.play(throughLine: 18, expecting: "turn.status e_0013_95540")
        #expect(replay.conversation.turn?.id == "t_0002_71172")
        #expect(replay.conversation.turn?.inputs == [mine])
        let thinking = Status(kind: .thinking, label: "Thinking it through")
        #expect(replay.conversation.turn?.status == thinking)
        #expect(replay.conversation[step: "s_0002_94009"]?.outcome == nil)

        try replay.play(throughLine: 19, expecting: "step.ended e_0014_91139")
        let step = try #require(replay.conversation[step: "s_0002_94009"])
        #expect(step.outcome == .completed && step.title == "Thought it through")
        #expect(step.durationMs == 1500)
    }

    @Test("Scenario 4: steps and a note arrive in order, each status replacing the last")
    func agentStirs() throws {
        var replay = Replay(try Fixtures.transcript("04-the-agent-stirs"))
        try replay.play(throughLine: 19, expecting: "step.updated e_0014_48522")
        let thinking = try #require(replay.conversation[step: "s_0002_61308"])
        #expect(thinking.heading == "Sketching a calm Saturday" && thinking.outcome == nil)

        try replay.play(throughLine: 23, expecting: "message.delta e_0018_15772")
        let note = try #require(replay.conversation.noteInProgress)
        #expect(note.text == "I'll check which cafés " && !note.isShown)
        #expect(replay.conversation.turn?.status?.detail == "Sketching a calm Saturday")

        try replay.play(throughLine: 25, expecting: "message.ended e_0020_06983")
        #expect(replay.conversation.noteInProgress == nil)

        try replay.play(throughLine: 26, expecting: "step.started e_0021_18999")
        let search = try #require(replay.conversation[step: "s_0003_50731"])
        #expect(search.kind == .webSearch && search.query == "riverside cafés open at 9am")
        #expect(search.title == "Searching the web for riverside cafés open at 9am")
        try replay.play(throughLine: 28, expecting: "step.ended e_0023_06854")
        #expect(
            replay.conversation[step: "s_0003_50731"]?.title
                == "Searched the web for riverside cafés open at 9am")

        try replay.play(throughLine: 31, expecting: "step.ended e_0026_77306")
        let read = try #require(replay.conversation[step: "s_0004_53063"])
        #expect(read.kind == .command && read.command == "cat notes/saturday.md")
        #expect(read.actions?.map(\.type) == [.read])
        #expect(read.actions?.first?.path == "notes/saturday.md")
        #expect(read.exitCode == 0 && read.output?.isEmpty == false)

        try replay.play(throughLine: 35, expecting: "turn.status e_0030_27212")
        let fitting = Status(
            kind: .thinking, label: "Thinking it through", detail: "Fitting the day around the run")
        #expect(replay.conversation.turn?.status == fitting)
        // Writing comes with no detail, and the old one mustn't linger.
        try replay.play(throughLine: 37, expecting: "turn.status e_0032_25074")
        #expect(replay.conversation.turn?.status == Status(kind: .writing, label: "Writing"))

        // The note sits between the first thought and the search, where it was written.
        try replay.play()
        let steps = replay.conversation.steps.filter { $0.turn == "t_0002_22663" }
        #expect(
            steps.map(\.id) == ["s_0002_61308", "s_0003_50731", "s_0004_53063", "s_0005_21239"])
        let noted = try #require(replay.conversation["m_0002_90390"]?.position)
        #expect(steps[0].position < noted && noted < steps[1].position)
    }

    @Test(
        "Scenario 7: Stop ends the turn, the reply keeps what Ari wrote, and a step ends stopped"
    )
    func stop() throws {
        var replay = Replay(try Fixtures.transcript("07-stop"))
        let reply: MessageID = "m_0002_81610"
        try replay.play(throughLine: 32, expecting: "POST /v0/turns/t_0002_40331/stop")
        #expect(replay.conversation.pendingStop == "t_0002_40331")

        // The 202 says the turn is stopping.
        try replay.play(throughLine: 34, expecting: "turn.status e_0027_65057")
        #expect(replay.conversation.turn?.status?.kind == .stopping)
        // Sent while stopping, so it waits as Next.
        let next: MessageID = "21d803b8-d67b-47dc-91c6-b540fb9b4972"
        try replay.play(throughLine: 38, expecting: "message.queued e_0029_21466")
        #expect(replay.conversation[next]?.mark == .next)

        // The reply ends stopped with everything Ari had written; then the turn ends.
        try replay.play(throughLine: 40, expecting: "turn.ended e_0031_84439")
        #expect(replay.conversation[reply]?.outcome == .stopped)
        #expect(replay.conversation[reply]?.length == 266)
        #expect(replay.conversation.pendingStop == nil)
        #expect(replay.conversation.lastEndedTurn?.outcome == .stopped)
        // Next starts the following turn, and Stopped is gone.
        try replay.play(throughLine: 41, expecting: "turn.started e_0032_69133")
        #expect(replay.conversation[next]?.mark == nil)
        #expect(replay.conversation.lastEndedTurn == nil)

        // Stop just after the second reply began: the first is final, the second keeps what
        // little it had.
        try replay.play(throughLine: 73, expecting: "turn.ended e_0060_44071")
        #expect(replay.conversation["m_0004_08797"]?.outcome == .completed)
        #expect(replay.conversation["m_0005_12106"]?.outcome == .stopped)
        #expect(replay.conversation["m_0005_12106"]?.length == 35)

        // Stop while a search runs: the step ends stopped, keeping its present-tense title.
        try replay.play(throughLine: 84, expecting: "turn.ended e_0067_16351")
        let search = try #require(replay.conversation[step: "s_0004_54646"])
        #expect(search.outcome == .stopped)
        #expect(search.title == "Searching the web for cafés near Battersea Park open at 9")
    }

    @Test("Scenario 9: earlier pages slot in above, with their steps, until there are none")
    func scrollingBack() throws {
        var replay = Replay(try Fixtures.transcript("09-scrolling-back"))
        #expect(replay.conversation.entries.count == 4)
        #expect(replay.conversation.hasEarlierMessages)
        let before = replay.conversation.steps.count
        try replay.play(throughLine: 50, expecting: "200")
        #expect(replay.conversation.entries.count == 8)
        #expect(replay.conversation.hasEarlierMessages)
        #expect(replay.conversation.steps.count == before + 2)
        try replay.play(throughLine: 52, expecting: "200")
        #expect(replay.conversation.entries.count == 10)
        #expect(!replay.conversation.hasEarlierMessages)
        #expect(replay.conversation.cursor == "e_0045_34314")
        let positions = replay.conversation.steps.map(\.position)
        #expect(positions == positions.sorted() && positions.count == before + 3)
    }

    @Test("Scenario 10: Read while the turn runs, Next while the agent can't listen")
    func sendWhileBusy() throws {
        var replay = Replay(try Fixtures.transcript("10-send-while-it-s-busy"))
        let adjust: MessageID = "1b82d2aa-dba7-4c69-916c-d9fb4a0b94ec"
        // Accepted while the reply streams, so the reply stays above it.
        try replay.play(throughLine: 30, expecting: "message.accepted e_0024_28708")
        #expect(replay.conversation.entries.map(\.id).suffix(2) == ["m_0002_50552", adjust])

        try replay.play(throughLine: 40, expecting: "turn.status e_0033_01023")
        #expect(replay.conversation[adjust]?.mark == .read)
        #expect(replay.conversation.turn?.status?.label == "Adjusting to your message")
        // The turn ends, and Read went with it.
        try replay.play(throughLine: 50, expecting: "turn.ended e_0043_61190")
        #expect(replay.conversation[adjust]?.mark == nil)

        let waiting: MessageID = "c64bf93c-0d54-4a21-8efa-f6ec351b62ef"
        try replay.play(throughLine: 61, expecting: "message.queued e_0049_78207")
        #expect(replay.conversation[waiting]?.mark == .next)
        #expect(replay.conversation[step: "s_0003_28118"]?.kind == .compacting)
        // The turn it waits behind ends, but its own hasn't started yet.
        try replay.play(throughLine: 73, expecting: "turn.ended e_0061_56015")
        #expect(replay.conversation[waiting]?.mark == .next)
        try replay.play(throughLine: 74, expecting: "turn.started e_0062_61462")
        #expect(replay.conversation[waiting]?.mark == nil)
        #expect(replay.conversation.turn?.inputs == [waiting])
    }

    @Test("Scenario 12: a lost answer and a resend leave one message, in order")
    func sendWhileOffline() throws {
        var replay = Replay(try Fixtures.transcript("12-send-while-offline"))
        let first: MessageID = "76c3ac95-83e0-45e9-a821-a12c08d956e9"
        let second: MessageID = "0c1566bf-a262-4595-b7a6-dd608ba8c3b0"
        try replay.play(throughLine: 17, expecting: "POST /v0/messages")
        #expect(replay.conversation[first]?.delivery == .sending)
        // Accepted on the stream, though the 201 is lost.
        try replay.play(throughLine: 19, expecting: "201 lost")
        #expect(replay.conversation[first]?.delivery == .delivered)
        // The resend's 200, then the second message.
        try replay.play(throughLine: 25, expecting: "POST /v0/messages")
        #expect(replay.conversation.entries.filter { $0.id == first }.count == 1)
        #expect(replay.conversation.entries.last?.id == second)
        #expect(replay.conversation[second]?.delivery == .sending)
        try replay.play(throughLine: 28, expecting: "message.read e_0015_68521")
        #expect(replay.conversation[second]?.mark == .read)
    }

    @Test("Scenario 14: a restart keeps the cut-off reply; a restore matches the server")
    func restartAndRestore() throws {
        var replay = Replay(try Fixtures.transcript("14-the-server-restarts-or-is-restored"))
        try replay.play(throughLine: 33, expecting: "turn.ended e_0025_12269")
        let reply = try #require(replay.conversation["m_0002_05742"])
        #expect(reply.outcome == .interrupted)
        #expect(reply.length == 162 && reply.text.hasSuffix("your book.\n"))
        #expect(replay.conversation.lastEndedTurn?.outcome == .interrupted)

        // Restored from a backup, the snapshot is all there is, its steps included.
        try replay.play(throughLine: 37, expecting: "snapshot e_0009_45546")
        let ids: [MessageID] = ["bafdbba2-d851-4593-bc68-fdb68d9ab705", "m_0001_43076"]
        #expect(replay.conversation.entries.map(\.id) == ids)
        #expect(replay.conversation.steps.count == 1)
        #expect(replay.conversation.cursor == "e_0009_45546")
        #expect(replay.conversation.lastEndedTurn == nil)
    }

    @Test(
        "Scenario 15: a failure keeps its text and reason, Try again starts one attempt, and a failure before any text leaves an empty reply"
    )
    func somethingFails() throws {
        var replay = Replay(try Fixtures.transcript("15-something-fails"))
        let failedTurn: TurnID = "t_0002_56862"
        let error = ServerError(
            code: .modelTimeout, message: "The model didn't respond for 60 seconds.",
            detail: "No progress from the engine for 60 seconds while it was writing.")
        try replay.play(throughLine: 29, expecting: "turn.ended e_0023_62373")
        #expect(replay.conversation["m_0002_07750"]?.outcome == .failed)
        #expect(replay.conversation["m_0002_07750"]?.error == error)
        let ended = try #require(replay.conversation.lastEndedTurn)
        #expect(ended.id == failedTurn && ended.outcome == .failed && ended.error == error)
        #expect(!replay.conversation.retriedTurns.contains(failedTurn))

        try replay.play(throughLine: 30, expecting: "POST /v0/turns/t_0002_56862/retry")
        #expect(replay.conversation.retriedTurns.contains(failedTurn))
        // The new attempt starts, and Couldn't finish is gone.
        try replay.play(throughLine: 31, expecting: "turn.started e_0024_98002")
        #expect(replay.conversation.turn?.retryOf == failedTurn)
        #expect(replay.conversation.lastEndedTurn == nil)

        // The model is down before a word: the step failed, still in the present tense, and an
        // empty reply carries the reason.
        try replay.play()
        let thinking = try #require(replay.conversation[step: "s_0004_48692"])
        #expect(thinking.outcome == .failed && thinking.title == "Thinking it through")
        let empty = try #require(replay.conversation["m_0004_67083"])
        #expect(empty.outcome == .failed && empty.length == 0)
        #expect(empty.error?.code == .modelUnavailable)
    }

    @Test("Scenario 16: a working turn's steps carry their specifics, and the plan keeps up")
    func workingThroughATask() throws {
        var replay = Replay(try Fixtures.transcript("16-working-through-a-task"))
        let plan: StepID = "s_0003_54216"
        try replay.play(throughLine: 25, expecting: "step.updated e_0020_74721")
        #expect(
            replay.conversation[step: plan]?.items?.map(\.state) == [.done, .inProgress, .pending])

        try replay.play()
        let conversation = replay.conversation
        let read = try #require(conversation[step: "s_0004_64661"])
        #expect(read.actions?.map(\.type) == [.read, .search])
        // A search that finds nothing exits 1, and still completed.
        let search = try #require(conversation[step: "s_0005_72445"])
        #expect(search.exitCode == 1 && search.outcome == .completed)
        let tool = try #require(conversation[step: "s_0006_50225"])
        #expect(tool.capability == "weather" && tool.operation == "forecast")
        #expect(tool.arguments?.contains(#""place" : "London""#) == true)
        #expect(conversation[step: "s_0007_91795"]?.waitMs == 2000)
        let edit = try #require(conversation[step: "s_0008_27329"]?.files?.first)
        #expect(edit.path == "packing.md" && edit.change == .modified)
        #expect(edit.linesAdded == 2 && edit.linesRemoved == 1)
        // The plan ran the whole turn, so it ends last but keeps its early place.
        let planned = try #require(conversation[step: plan])
        #expect(
            planned.title == "Planned 3 steps"
                && planned.items?.allSatisfy { $0.state == .done } == true)
        let turn = conversation.steps.filter { $0.turn == "t_0002_12217" }
        #expect(turn.map(\.id).prefix(2) == ["s_0002_84756", plan])
    }

    @Test("Scenario 17: a report waits for your yes, shows its screenshots, and links its issue")
    func reporting() throws {
        var replay = Replay(try Fixtures.transcript("17-reporting-a-gap"))
        try replay.play()
        // Nothing left the box before you agreed, and the draft showed the screenshot it would share.
        let draft = try #require(replay.conversation.asks.first { $0.id == "a_0001_65902" })
        #expect(draft.kind == .approval && draft.preview != nil)
        #expect(draft.attachments == ["ccb15bb0-ea37-49ed-9d33-d215acfcf881"])
        #expect(draft.outcome == .answered)
        let report = try #require(replay.conversation[step: "s_0002_13555"])
        #expect(report.kind == .tool && report.title == "Reported it to Ito")
        #expect(report.url == "https://github.com/akai-ito/ito-core/issues/42")
        // A follow-up adds to the same issue.
        let followUp = try #require(replay.conversation[step: "s_0003_94980"])
        #expect(followUp.url?.hasPrefix("https://github.com/akai-ito/ito-core/issues/42#") == true)
    }

    @Test("Scenario 19: Ari asks and waits; a tapped option answers it, settling it at once")
    func askBeforeActing() throws {
        var replay = Replay(try Fixtures.transcript("19-ari-asks-before-acting"))
        let ask: AskID = "a_0001_32034"
        let clapham: MessageID = "5ce13252-2fa3-4462-a97b-c341b244f5f5"
        // Asking ends the turn; the ask waits.
        try replay.play(throughLine: 21, expecting: "turn.ended e_0016_01740")
        #expect(replay.conversation.turn == nil)
        let waiting = try #require(replay.conversation.waitingAsk)
        #expect(waiting.id == ask && waiting.kind == .question && !waiting.options.isEmpty)
        #expect(waiting.question == "Which Juno did you mean?")

        // You tap Clapham: the ask settles before the server says so.
        try replay.play(throughLine: 22, expecting: "POST /v0/messages")
        #expect(replay.conversation.waitingAsk == nil)
        #expect(replay.conversation.settling[ask] == .answering(clapham))

        try replay.play(throughLine: 24, expecting: "ask.ended e_0018_21843")
        #expect(replay.conversation[ask: ask]?.outcome == .answered)
        #expect(replay.conversation[ask: ask]?.answer == clapham)
        #expect(replay.conversation.settling.isEmpty)
        #expect(replay.conversation[clapham]?.answers == ask)
    }

    @Test("Scenario 20: an approval shows what would happen, and one option goes ahead")
    func approval() throws {
        var replay = Replay(try Fixtures.transcript("20-an-approval"))
        try replay.play()
        let ask = try #require(replay.conversation.asks.last)
        #expect(ask.kind == .approval && ask.preview?.isEmpty == false)
        #expect(ask.options.filter(\.acts).map(\.label) == ["Book it"])
        #expect(ask.outcome == .answered)
    }

    @Test("Scenario 22: an ask waits through the app closing and a restart; Stop cancels it")
    func waiting() throws {
        var replay = Replay(try Fixtures.transcript("22-waiting"))
        let ask: AskID = "a_0001_05580"
        try replay.play(throughLine: 21, expecting: "turn.ended e_0016_10629")
        #expect(replay.conversation.waitingAsk?.id == ask)
        try replay.play(throughLine: 26, expecting: "200")
        #expect(replay.conversation.waitingAsk?.id == ask)

        try replay.play(throughLine: 27, expecting: "POST /v0/asks/a_0001_05580/cancel")
        #expect(replay.conversation.settling[ask] == .cancelling)
        #expect(replay.conversation.waitingAsk == nil)
        try replay.play(throughLine: 28, expecting: "ask.ended e_0017_61169")
        #expect(replay.conversation[ask: ask]?.outcome == .cancelled)
        #expect(replay.conversation.settling.isEmpty)
    }

    @Test("Scenario 23: whatever you send answers the ask; then Stop cancels the next one")
    func yourOwnWay() throws {
        var replay = Replay(try Fixtures.transcript("23-your-own-way-then-stop"))
        let typed: MessageID = "40364441-f13e-436f-9303-730eb0ad286a"
        try replay.play(throughLine: 24, expecting: "ask.ended e_0018_83796")
        #expect(replay.conversation[ask: "a_0001_57535"]?.answer == typed)
        try replay.play(throughLine: 31, expecting: "turn.ended e_0024_07382")
        #expect(replay.conversation.waitingAsk?.question == "Same time, Saturday at 7:30?")
        try replay.play()
        #expect(replay.conversation[ask: "a_0002_64299"]?.outcome == .cancelled)
        #expect(replay.conversation.waitingAsk == nil)
    }
}

extension Replay {
    /// Plays through the transcript's line `line`, which must hold the step `summary` names, so that
    /// a regenerated transcript can't quietly move a checkpoint.
    mutating func play(
        throughLine line: Int, expecting summary: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let step = try play(throughLine: line)
        #expect(
            step?.line == line && step?.summary == summary,
            "\(transcript.name).jsonl line \(line) isn't \"\(summary)\"",
            sourceLocation: sourceLocation)
    }
}

// MARK: - Where each scenario ends

private struct Expected {
    let id: MessageID
    let text: String
    let outcome: Outcome?
    let shown: Bool
    /// The names of the photos and files it carries.
    let attachments: [String]
}

private func expect(
    _ conversation: Conversation, holds expected: [Expected],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        conversation.entries.map(\.id) == expected.map(\.id), "the messages, or their order",
        sourceLocation: sourceLocation)
    for (entry, want) in zip(conversation.entries, expected) {
        let name = entry.id
        #expect(entry.text == want.text, "\(name)", sourceLocation: sourceLocation)
        #expect(entry.outcome == want.outcome, "\(name)", sourceLocation: sourceLocation)
        #expect(entry.isShown == want.shown, "\(name)", sourceLocation: sourceLocation)
        #expect(
            entry.attachments.map(\.name) == want.attachments, "\(name)",
            sourceLocation: sourceLocation)
        #expect(entry.mark == nil, "\(name)", sourceLocation: sourceLocation)
        if entry.role == .user {
            #expect(entry.delivery == .delivered, "\(name)", sourceLocation: sourceLocation)
        }
    }
}

extension ConversationTranscriptTests {
    /// What a transcript's conversation ends as, read from its raw JSON rather than through Ari:
    /// every message the server announced (given, in a snapshot, an event or a page of history), in
    /// position order, with the text it ended with, its outcome and its attachments. A snapshot
    /// starts the conversation again.
    fileprivate static func end(of transcript: Transcript) -> [Expected] {
        struct Seen {
            var position: Int
            var role: String
            var kind: String?
            var text: [UInt16]
            var outcome: String?
            var attachments: [String]
        }
        var seen: [String: Seen] = [:]
        func record(_ message: JSONValue) {
            guard let id = message["id"]?.string else { return }
            seen[id] = Seen(
                position: message["position"]?.int ?? seen[id]?.position ?? .max,
                role: message["role"]?.string ?? "agent", kind: message["kind"]?.string,
                text: Array((message["text"]?.string ?? "").utf16),
                outcome: message["outcome"]?.string,
                attachments: message["attachments"]?.array?.compactMap { $0["name"]?.string } ?? [])
        }
        var asked: Transcript.Request?
        // The app's cache when the scenario starts, then everything that happens.
        for step in transcript.given.map(Transcript.Step.event) + transcript.steps {
            switch step {
            case .app(let request):
                asked = request
            case .server(let response):
                if case .earlierMessages = asked?.route {
                    for message in response.body?["messages"]?.array ?? []
                    where seen[message["id"]?.string ?? ""] == nil {
                        record(message)
                    }
                }
            case .event(let logged):
                let json = logged.json
                switch json["type"]?.string {
                case "snapshot":
                    seen = [:]
                    for message in json["messages"]?.array ?? [] { record(message) }
                case "message.accepted", "message.amended", "message.started":
                    if let message = json["message"] { record(message) }
                case "message.delta":
                    if let id = json["message"]?.string, let text = json["text"]?.string {
                        seen[id]?.text += Array(text.utf16)
                    }
                case "message.ended":
                    if let id = json["message"]?.string {
                        seen[id]?.outcome = json["outcome"]?.string
                        if let length = json["length"]?.int, let text = seen[id]?.text {
                            seen[id]?.text = Array(text.prefix(length))
                        }
                    }
                default:
                    break
                }
            default:
                break
            }
        }
        return seen.sorted { $0.value.position < $1.value.position }.map { id, message in
            Expected(
                id: MessageID(id), text: String(decoding: message.text, as: UTF16.self),
                outcome: message.outcome.map(Outcome.init(rawValue:)),
                shown: message.role == "user" || message.kind == "reply",
                attachments: message.attachments)
        }
    }
}
