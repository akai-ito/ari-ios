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
        let expected = try #require(
            Self.endStates[transcript.name], "no end state for \(transcript.name)")
        expect(conversation, holds: expected)
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
        "Scenario 7: Stop holds the cut until the turn ends, a late Stop doesn't, and Stop mid-step ends the step"
    )
    func stop() throws {
        var replay = Replay(try Fixtures.transcript("07-stop"))
        let reply: MessageID = "m_0002_81610"
        // You tap Stop with 209 units on screen, when 266 have arrived.
        try replay.play(throughLine: 32, expecting: "POST /v0/turns/t_0002_40331/stop")
        #expect(replay.conversation.pendingStop?.turn == "t_0002_40331")
        #expect(replay.conversation.pendingStop?.cut == Cut(message: reply, offset: 209))
        #expect(replay.conversation[reply]?.length == 266)
        #expect(try visible(reply, in: replay).hasSuffix("keep it light before"))
        #expect(try visible(reply, in: replay).utf16.count == 209)

        // The 202 says the turn is stopping; the reply still holds at the cut.
        try replay.play(throughLine: 33, expecting: "202")
        #expect(try visible(reply, in: replay).utf16.count == 209)
        try replay.play(throughLine: 34, expecting: "turn.status e_0027_65057")
        #expect(replay.conversation.turn?.status?.kind == .stopping)
        // Sent while stopping, so it waits as Next.
        let next: MessageID = "21d803b8-d67b-47dc-91c6-b540fb9b4972"
        try replay.play(throughLine: 38, expecting: "message.queued e_0029_21466")
        #expect(replay.conversation[next]?.mark == .next)
        #expect(try visible(reply, in: replay).utf16.count == 209)

        // The reply ends stopped at the cut; then the turn ends.
        try replay.play(throughLine: 40, expecting: "turn.ended e_0031_84439")
        #expect(replay.conversation[reply]?.outcome == .stopped)
        #expect(replay.conversation[reply]?.length == 209)
        #expect(replay.conversation.pendingStop == nil)
        #expect(replay.conversation.lastEndedTurn?.outcome == .stopped)
        // Next starts the following turn, and Stopped is gone.
        try replay.play(throughLine: 41, expecting: "turn.started e_0032_69133")
        #expect(replay.conversation[next]?.mark == nil)
        #expect(replay.conversation.lastEndedTurn == nil)

        // "And Sunday?" is answered in full; then you tap Stop, too late.
        try replay.play(throughLine: 65, expecting: "turn.ended e_0054_00574")
        try replay.play(throughLine: 66, expecting: "POST /v0/turns/t_0004_50773/stop")
        #expect(replay.conversation.pendingStop == nil)
        #expect(try visible("m_0004_08797", in: replay).utf16.count == 66)
        try replay.play(throughLine: 67, expecting: "200")
        #expect(replay.conversation["m_0004_08797"]?.outcome == .completed)

        // Stop while the second reply waits behind the first: the first is final, the second cut
        // at nothing.
        try replay.play(throughLine: 83, expecting: "POST /v0/turns/t_0005_27837/stop")
        #expect(replay.conversation.pendingStop?.cut == Cut(message: "m_0006_90669", offset: 0))
        try replay.play(throughLine: 87, expecting: "turn.ended e_0070_67956")
        #expect(replay.conversation["m_0005_12106"]?.outcome == .completed)
        #expect(replay.conversation["m_0006_90669"]?.length == 0)

        // Stop while a search runs: the step ends stopped, keeping its present-tense title.
        try replay.play(throughLine: 94, expecting: "POST /v0/turns/t_0006_31337/stop")
        #expect(replay.conversation.pendingStop?.cut == nil)
        try replay.play(throughLine: 98, expecting: "turn.ended e_0077_17737")
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

    @Test("Scenario 17: a gap report is a tool step that links to its issue")
    func reportingAGap() throws {
        var replay = Replay(try Fixtures.transcript("17-reporting-a-gap"))
        try replay.play()
        // The page that wouldn't load still ran, so it completed, with its exit code.
        let fetch = try #require(replay.conversation[step: "s_0003_94980"])
        #expect(fetch.outcome == .completed && fetch.exitCode == 22)
        let report = try #require(replay.conversation[step: "s_0004_29982"])
        #expect(report.kind == .tool && report.title == "Reported it to Ito")
        #expect(report.url == "https://github.com/akai-ito/ito-core/issues/42")
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

    @Test("Scenario 25: a secret answer keeps no text, here or on the server")
    func secret() throws {
        var replay = Replay(try Fixtures.transcript("25-a-secret"))
        let code: MessageID = "07fa34b1-a387-4687-bf4a-a9a7a40cc10f"
        try replay.play(throughLine: 21, expecting: "turn.ended e_0016_73484")
        #expect(replay.conversation.waitingAsk?.secret == true)
        try replay.play(throughLine: 22, expecting: "POST /v0/messages")
        #expect(
            replay.conversation[code]?.isSecret == true && replay.conversation[code]?.text == "")
        try replay.play(throughLine: 23, expecting: "message.accepted e_0017_04913")
        #expect(
            replay.conversation[code]?.isSecret == true && replay.conversation[code]?.text == "")
        #expect(replay.conversation[code]?.answers == "a_0001_49834")
    }

    private func visible(_ id: MessageID, in replay: Replay) throws -> String {
        replay.conversation.visibleText(of: try #require(replay.conversation[id]))
    }
}

extension Replay {
    /// Plays through the transcript's line `line`, which must hold the step `summary` names, so that
    /// a regenerated transcript can't quietly move a checkpoint.
    fileprivate mutating func play(
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
    var text: String?
    var length: Int?
    var ending: String?
    var outcome: Outcome?
    var shown = true
    /// The names of the photos and files it carries.
    var attachments: [String] = []
}

private func you(_ id: MessageID, _ text: String, attaching attachments: [String] = []) -> Expected
{
    Expected(id: id, text: text, attachments: attachments)
}

private func reply(
    _ id: MessageID, _ length: Int, _ ending: String, _ outcome: Outcome = .completed
) -> Expected {
    Expected(id: id, length: length, ending: ending, outcome: outcome)
}

private let bike = "Is it worth fixing the old bike or buying a new one?"
private let saturday = "Plan my Saturday: long run in the morning, then something calm."

private func bikeReply(_ id: MessageID) -> Expected {
    reply(id, 162, "If the gears still slip after that, revisit.")
}
private func saturdayReply(_ id: MessageID) -> Expected {
    reply(id, 318, "Early night: you're up at 7.")
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
        if let text = want.text {
            #expect(entry.text == text, "\(name)", sourceLocation: sourceLocation)
        }
        if let length = want.length {
            #expect(entry.text.utf16.count == length, "\(name)", sourceLocation: sourceLocation)
        }
        if let ending = want.ending {
            #expect(entry.text.hasSuffix(ending), "\(name)", sourceLocation: sourceLocation)
        }
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
    fileprivate static let endStates: [String: [Expected]] = [
        "01-first-connection": [],
        "02-open-ari": [
            you("63d6297e-90ec-494f-9bfe-c55b7d5c6f60", bike), bikeReply("m_0001_00810"),
            you("6549385e-4502-4bc3-9104-7c510ad2365a", "What time is sunrise on Saturday?"),
            reply("m_0002_32503", 68, "start a run by about 06:50."),
        ],
        "03-send": [
            you("32f17f68-5b4a-4c02-be38-bb55893a5c0d", bike), bikeReply("m_0001_76774"),
            you("69a52e25-a392-4a73-89f9-21eb36005baf", saturday), saturdayReply("m_0002_52784"),
        ],
        "04-the-agent-stirs": [
            you("d52e129f-e30a-4ce7-8622-4125b7edd868", bike), bikeReply("m_0001_21968"),
            you("f63df431-879e-46f0-9e6d-154323b2c9f4", saturday),
            Expected(
                id: "m_0002_90390", text: "I'll check which cafés by the river open early.",
                outcome: .completed,
                shown: false),
            saturdayReply("m_0003_29104"),
        ],
        "05-the-reply-streams": [
            you("d70174fb-30e1-44b3-bc42-ff74771f01e1", bike), bikeReply("m_0001_64933"),
            you("ca8f484f-3900-44f6-8fbf-85e7a258b7be", saturday), saturdayReply("m_0002_24233"),
        ],
        "06-you-scroll-up-mid-reply": [
            you("706d1565-244b-4a4b-b2ec-3f0815f1e742", bike), bikeReply("m_0001_89255"),
            you("d9fb1b9d-a66f-416c-b69c-ca730c2af417", saturday), saturdayReply("m_0002_55548"),
        ],
        "07-stop": [
            you("40fad84f-9c72-47ac-b2ce-b6152b68b0c0", bike), bikeReply("m_0001_79685"),
            you("f7f3de34-9d23-457f-a7b4-28d1818238fa", saturday),
            reply("m_0002_81610", 209, "Lunch at home; keep it light before", .stopped),
            you("21d803b8-d67b-47dc-91c6-b540fb9b4972", "Actually, just plan the morning."),
            reply("m_0003_68282", 120, "the café by the bridge; it opens at 9."),
            you("d07a73b5-68d9-4d34-8dfc-984eaaa36911", "And Sunday?"),
            reply("m_0004_08797", 66, "then lunch with friends if you're up for it."),
            you("e8d134af-23b2-4510-9360-ccd762695be8", "And Saturday evening?"),
            reply("m_0005_12106", 65, "then an early night before the long run."),
            reply("m_0006_90669", 0, "", .stopped),
            you("cdf4fa57-3822-4b94-b26f-b65fe93afdef", "Find a café for after the run."),
        ],
        "08-copy-and-share": [
            you("7f25eedd-f9f0-491d-8453-68489f9735a3", bike), bikeReply("m_0001_09845"),
            you(
                "c20b0e66-9057-46a7-960d-3ed802c5fbce",
                "How do I see what's using port 8080 on my Mac?"),
            Expected(
                id: "m_0002_38147",
                text: "Run this in Terminal:\n\n```sh\nlsof -nP -iTCP:8080 -sTCP:LISTEN\n```\n\n"
                    + "The second column is the process ID; `kill <PID>` stops it.",
                outcome: .completed),
        ],
        "09-scrolling-back": [
            you("0df2b4c3-c6d3-4b89-89b8-fe67f4bea5bc", "Any good running routes near Battersea?"),
            reply("m_0001_09453", 133, "Add Battersea Park's outer path for 8 km."),
            you("a32dbe01-f966-4894-820c-5b2262c77a43", "What's a good stretch after a long run?"),
            reply("m_0002_34334", 141, "Skip deep static stretches straight after a race."),
            you(
                "eedd4099-47f7-44de-b0fd-9b8b66c82323",
                "Somewhere quiet for dinner near Clapham, Thursday?"),
            reply("m_0003_64520", 129, "Thursday has space at 19:45."),
            you("b0474bdd-5955-432b-bb9f-7b7ce9ef2c5e", "Thanks, Juno was perfect."),
            reply("m_0004_61453", 72, "next time you want somewhere quiet."),
            you("8ac6f761-1cdc-45a8-bdc2-3c15e18d6d2f", bike), bikeReply("m_0005_84187"),
        ],
        "10-send-while-it-s-busy": [
            you("52054ffc-b7ec-4fc5-880c-287a139ae1d7", bike), bikeReply("m_0001_37089"),
            you("3a3e2f07-85f4-4f6c-95f1-200524c679a3", saturday), saturdayReply("m_0002_50552"),
            you("1b82d2aa-dba7-4c69-916c-d9fb4a0b94ec", "Make the calm part outdoors"),
            reply("m_0003_01349", 141, "Keep the botanic garden walk; it's outdoors already."),
            you(
                "eb14631a-a787-4821-87f4-a691adb5b11a",
                "Also find somewhere for breakfast by the river."),
            you("c64bf93c-0d54-4a21-8efa-f6ec351b62ef", "With outdoor seats, ideally."),
            reply("m_0004_56107", 93, "ten minutes' walk from where your run ends."),
            reply("m_0005_94194", 61, "terrace, first come, first served."),
        ],
        "11-signal-drops-mid-reply": [
            you("9ed912ac-5a04-42ff-84fd-f40d457ee86b", bike), bikeReply("m_0001_18318"),
            you("4be42a7e-e1a4-44ef-9f22-6388a62da6d2", saturday), saturdayReply("m_0002_62029"),
        ],
        "12-send-while-offline": [
            you("b77a7cfe-2ae5-4ebe-a784-822ec390f61c", bike), bikeReply("m_0001_60432"),
            you(
                "76c3ac95-83e0-45e9-a821-a12c08d956e9",
                "Also, can you check if Juno is open on Sunday?"),
            you("0c1566bf-a262-4595-b7a6-dd608ba8c3b0", "And book for two at 8 if so"),
            reply("m_0002_04718", 147, "their booking page is bistrojuno.example/book."),
        ],
        "13-ari-is-closed-mid-reply": [
            you("c300beab-27c9-4810-8dac-8f7f08e2b211", bike), bikeReply("m_0001_61139"),
            you("24ef3e8f-c321-4909-887d-3373262b777e", saturday), saturdayReply("m_0002_36640"),
        ],
        "14-the-server-restarts-or-is-restored": [
            you("bafdbba2-d851-4593-bc68-fdb68d9ab705", bike), bikeReply("m_0001_43076"),
        ],
        "15-something-fails": [
            you("49aa4561-aa73-4772-a218-9c9facc270ea", bike), bikeReply("m_0001_31347"),
            you("d9627c57-0b51-47c0-9cc6-e91c6bf56658", saturday),
            reply("m_0002_07750", 105, "flat, and the café opens at 9.", .failed),
            saturdayReply("m_0003_11459"),
            you("835616aa-d801-4a42-a976-cd02a6569b27", "And Sunday?"),
            reply("m_0004_67083", 0, "", .failed),
        ],
        "18-a-reply-while-you-re-away": [
            you("dfbbdf74-22ad-485a-8020-e54a243e67c9", bike), bikeReply("m_0001_81220"),
            you("d147cf4e-fc32-4395-aab9-f7b64c29be07", saturday),
            you(
                "0052f675-d6e7-42ef-8a4f-6c744e9b9f17",
                "Also, does the 37 bus run before 7 on Saturdays?"),
            saturdayReply("m_0002_88780"),
            reply("m_0003_13830", 0, "", .failed),
        ],
        "19-ari-asks-before-acting": [
            you("602d18e0-95e6-459a-9af4-9642703308e5", bike), bikeReply("m_0001_38572"),
            you(
                "bb0c651c-6f43-4f10-acb9-8956565e139a",
                "Book a table at Juno for Saturday at 7:30, for two."),
            you("5ce13252-2fa3-4462-a97b-c341b244f5f5", "Clapham"),
            reply("m_0002_19614", 73, "for two at 7:30 on Saturday. Shall I book it?"),
        ],
        "20-an-approval": [
            you("3209efd3-339f-4a33-a8be-dd3739ad0cb8", bike), bikeReply("m_0001_44818"),
            you(
                "68af8cd8-fbb9-4bd0-9cdf-9be2e3296d11",
                "Book Juno in Clapham for Saturday at 7:30, for two."),
            you("24cc9b91-dd36-4eba-8f55-b143861efea9", "Book it"),
            reply("m_0002_03242", 84, "30, a table for two. The reference is JC4821."),
        ],
        "21-an-ask-while-you-re-away": [
            you("1bd73a2b-843b-434b-8684-07a7bdf3a934", bike), bikeReply("m_0001_14784"),
            you(
                "de757056-edc5-4f6e-b5f8-b925c606fb15",
                "Book a table at Juno for Friday at 8, for two."),
            you("c2432f00-720f-4baf-bdd8-2d81439ca44f", "Soho"),
            reply("m_0002_06693", 51, ": Juno in Soho, Friday at 8, a table for two."),
        ],
        "22-waiting": [
            you("67d73edd-9fdd-4e0f-9681-cd1b4fc585e5", bike), bikeReply("m_0001_68901"),
            you("f23059bc-e46e-436e-99ec-e17a564b3587", "Book Juno for Saturday."),
        ],
        "23-your-own-way-then-stop": [
            you("ee60f6f5-f932-4d5f-9bb2-e954e533f662", bike), bikeReply("m_0001_04514"),
            you("e48048f8-e56f-4955-8ab8-7d976827fd7f", "Book Juno for Saturday."),
            you(
                "40364441-f13e-436f-9303-730eb0ad286a",
                "Actually, find somewhere new in Brixton instead."),
        ],
        "24-the-reminder": [
            you("a38ab63f-cd53-4185-8787-854cc00ddc02", bike), bikeReply("m_0001_16750"),
            you("d46a7bdd-6b3f-4d81-94a4-2393b548433b", "Book Juno for Saturday at 7:30, for two."),
            you("3c2171f0-3504-49fc-a75a-f7e7b7371229", "Clapham"),
            reply("m_0002_20811", 73, "for two at 7:30 on Saturday. Shall I book it?"),
        ],
        "25-a-secret": [
            you("3c745eaf-6fe9-43b0-8cd5-6d3e9027ecc8", bike), bikeReply("m_0001_44119"),
            you(
                "837231c9-ee97-474f-9657-13e0de8086cb",
                "Book Juno in Clapham for Saturday at 7:30, for two."),
            you("07fa34b1-a387-4687-bf4a-a9a7a40cc10f", ""),
            reply("m_0002_69009", 59, "n Clapham, Saturday at 7:30, a table for two."),
        ],
        "26-turning-on-notifications": [
            you("e650397d-2de5-4f6d-b54c-30865f70c9e6", bike), bikeReply("m_0001_63846"),
            you(
                "ec4d4743-f528-44cc-802c-c1c326b96ee5",
                "Go through my notes and tidy up the packing lists for the weekend."),
            reply("m_0002_07750", 95, "t and the bus card, and the old list is gone."),
        ],
        "17-reporting-a-gap": [
            you("61fffc2c-5f33-47dc-b94a-55c3dc0b0969", bike), bikeReply("m_0001_85723"),
            you(
                "ccb15bb0-ea37-49ed-9d33-d215acfcf881",
                "What time does the Battersea parkrun start?"),
            reply("m_0002_17163", 140, "Check the page before you go."),
        ],
        "27-send-a-photo": [
            you("b4f6841a-5ec9-401f-8bf7-1e043e7a49cb", bike), bikeReply("m_0001_24748"),
            you(
                "83d78220-f45e-449d-91b1-956a87478344",
                "Is this the Thames Path, near Hampton Court?", attaching: ["riverside.jpg"]),
            reply("m_0002_62579", 151, "you'll reach the bridge in about ten minutes."),
        ],
        "28-send-a-file": [
            you("91756d49-f3dc-45be-a919-b4b39f3b7ee0", bike), bikeReply("m_0001_95876"),
            you(
                "841b74ac-4148-43bd-b493-322ef3b1b956", "How far did I run this month?",
                attaching: ["running-log.csv"]),
            reply("m_0002_32098", 71, "he longest was 18 km on the 11th, in 1:39:37."),
        ],
        "29-an-upload-that-fails": [
            you("2a1ada6b-0c5c-4b94-ab31-9516bdaa2ec8", bike), bikeReply("m_0001_22838"),
            // Only the photo; the video was refused before anything was sent.
            you("772b92e3-c8ff-4820-8f79-9ff49401af20", "", attaching: ["riverside.jpg"]),
            reply("m_0002_60075", 81, "r morning. Want me to plan a walk from there?"),
            // Two days later the log's upload has expired: it goes again, then the message.
            you(
                "52be1db8-52e1-435f-82bd-a6b1849bca39", "Which of these runs had my fastest pace?",
                attaching: ["running-log.csv"]),
            reply("m_0003_46823", 49, "about 5:17 a kilometre."),
        ],
        "30-another-device-sees-an-attachment": [
            you(
                "bf204a91-5277-451f-96a9-c74349606d63",
                "Is this the Thames Path, near Hampton Court?", attaching: ["riverside.jpg"]),
            reply("m_0001_95267", 72, "the Surrey bank, just upstream of the palace."),
        ],
        "31-pair-with-a-qr-code": [],
        "16-working-through-a-task": [
            you("3ae1bdea-ef38-4834-82d0-5dae53d77f8c", bike), bikeReply("m_0001_73241"),
            you(
                "3b8a8184-5ac3-49d5-8d27-2929c23d6dcd",
                "Tidy up my packing list for Saturday, and check the weather."),
            reply("m_0002_86936", 120, "a rain jacket and added an umbrella to your list."),
        ],
    ]
}
