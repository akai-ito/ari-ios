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
        try replay.play(throughLine: 10, expecting: "POST /v0/messages")
        #expect(replay.conversation.entries.last?.id == mine)
        #expect(replay.conversation[mine]?.delivery == .sending)
        #expect(replay.conversation[mine]?.at == nil)

        // Accepted on the stream before the 201 arrives.
        try replay.play(throughLine: 11, expecting: "message.accepted e_0007_22264")
        #expect(replay.conversation[mine]?.delivery == .delivered)
        #expect(replay.conversation[mine]?.at?.rawValue == "2026-10-12T08:41:02.055Z")

        try replay.play(throughLine: 14, expecting: "turn.status e_0009_04488")
        #expect(replay.conversation.turn?.id == "t_0002_71172")
        #expect(replay.conversation.turn?.inputs == [mine])
        #expect(replay.conversation.turn?.status == Status(kind: .thinking, label: "Thinking"))
    }

    @Test("Scenario 4: a note is live detail, not a message, and each status replaces the last")
    func agentStirs() throws {
        var replay = Replay(try Fixtures.transcript("04-the-agent-stirs"))
        try replay.play(throughLine: 17, expecting: "message.delta e_0012_54122")
        let note = try #require(replay.conversation.noteInProgress)
        #expect(note.text == "I'll check which cafés " && !note.isShown)
        #expect(replay.conversation.turn?.status?.detail == "Sketching a calm Saturday")

        try replay.play(throughLine: 19, expecting: "message.ended e_0014_48522")
        #expect(replay.conversation.noteInProgress == nil)

        try replay.play(throughLine: 21, expecting: "turn.status e_0016_77110")
        let thinking = Status(
            kind: .thinking, label: "Thinking", detail: "Fitting the day around the run")
        #expect(replay.conversation.turn?.status == thinking)
        // Writing comes with no detail, and the old one mustn't linger.
        try replay.play(throughLine: 22, expecting: "turn.status e_0017_72268")
        #expect(replay.conversation.turn?.status == Status(kind: .writing, label: "Writing"))
    }

    @Test(
        "Scenario 7: Stop holds the reply at the cut until the turn ends, and a late Stop doesn't")
    func stop() throws {
        var replay = Replay(try Fixtures.transcript("07-stop"))
        let reply: MessageID = "m_0002_81610"
        // You tap Stop with 209 units on screen, when 266 have arrived.
        try replay.play(throughLine: 27, expecting: "POST /v0/turns/t_0002_40331/stop")
        #expect(replay.conversation.pendingStop?.turn == "t_0002_40331")
        #expect(replay.conversation.pendingStop?.cut == Cut(message: reply, offset: 209))
        #expect(replay.conversation[reply]?.length == 266)
        #expect(try visible(reply, in: replay).hasSuffix("keep it light before"))
        #expect(try visible(reply, in: replay).utf16.count == 209)

        // The 202 says the turn is stopping; the reply still holds at the cut.
        try replay.play(throughLine: 28, expecting: "202")
        #expect(try visible(reply, in: replay).utf16.count == 209)
        try replay.play(throughLine: 29, expecting: "turn.status e_0022_95718")
        #expect(replay.conversation.turn?.status?.kind == .stopping)
        // Sent while stopping, so it waits as Next.
        let next: MessageID = "21d803b8-d67b-47dc-91c6-b540fb9b4972"
        try replay.play(throughLine: 33, expecting: "message.queued e_0024_88127")
        #expect(replay.conversation[next]?.mark == .next)
        #expect(try visible(reply, in: replay).utf16.count == 209)

        // The reply ends stopped at the cut; then the turn ends.
        try replay.play(throughLine: 35, expecting: "turn.ended e_0026_74053")
        #expect(replay.conversation[reply]?.outcome == .stopped)
        #expect(replay.conversation[reply]?.length == 209)
        #expect(replay.conversation.pendingStop == nil)
        #expect(replay.conversation.lastEndedTurn?.outcome == .stopped)
        // Next starts the following turn, and Stopped is gone.
        try replay.play(throughLine: 36, expecting: "turn.started e_0027_65057")
        #expect(replay.conversation[next]?.mark == nil)
        #expect(replay.conversation.lastEndedTurn == nil)

        // "And Sunday?" is answered in full; then you tap Stop, too late.
        try replay.play(throughLine: 58, expecting: "turn.ended e_0047_20739")
        try replay.play(throughLine: 59, expecting: "POST /v0/turns/t_0004_50773/stop")
        #expect(replay.conversation.pendingStop == nil)
        #expect(try visible("m_0004_08797", in: replay).utf16.count == 66)
        try replay.play(throughLine: 60, expecting: "200")
        #expect(replay.conversation["m_0004_08797"]?.outcome == .completed)
    }

    @Test("Scenario 9: earlier pages slot in above, until there are none")
    func scrollingBack() throws {
        var replay = Replay(try Fixtures.transcript("09-scrolling-back"))
        #expect(replay.conversation.entries.count == 4)
        #expect(replay.conversation.hasEarlierMessages)
        try replay.play(throughLine: 35, expecting: "200")
        #expect(replay.conversation.entries.count == 8)
        #expect(replay.conversation.hasEarlierMessages)
        try replay.play(throughLine: 37, expecting: "200")
        #expect(replay.conversation.entries.count == 10)
        #expect(!replay.conversation.hasEarlierMessages)
        #expect(replay.conversation.cursor == "e_0030_79739")
    }

    @Test("Scenario 10: Read while the turn runs, Next while the agent can't listen")
    func sendWhileBusy() throws {
        var replay = Replay(try Fixtures.transcript("10-send-while-it-s-busy"))
        let adjust: MessageID = "1b82d2aa-dba7-4c69-916c-d9fb4a0b94ec"
        // Accepted while the reply streams, so the reply stays above it.
        try replay.play(throughLine: 25, expecting: "message.accepted e_0019_70762")
        #expect(replay.conversation.entries.map(\.id).suffix(2) == ["m_0002_50552", adjust])

        try replay.play(throughLine: 35, expecting: "turn.status e_0028_52683")
        #expect(replay.conversation[adjust]?.mark == .read)
        #expect(replay.conversation.turn?.status?.label == "Adjusting to your message")
        // The turn ends, and Read went with it.
        try replay.play(throughLine: 45, expecting: "turn.ended e_0038_62891")
        #expect(replay.conversation[adjust]?.mark == nil)

        let waiting: MessageID = "c64bf93c-0d54-4a21-8efa-f6ec351b62ef"
        try replay.play(throughLine: 55, expecting: "message.queued e_0043_61190")
        #expect(replay.conversation[waiting]?.mark == .next)
        // The turn it waits behind ends, but its own hasn't started yet.
        try replay.play(throughLine: 64, expecting: "turn.ended e_0052_26911")
        #expect(replay.conversation[waiting]?.mark == .next)
        try replay.play(throughLine: 65, expecting: "turn.started e_0053_28086")
        #expect(replay.conversation[waiting]?.mark == nil)
        #expect(replay.conversation.turn?.inputs == [waiting])
    }

    @Test("Scenario 12: a lost answer and a resend leave one message, in order")
    func sendWhileOffline() throws {
        var replay = Replay(try Fixtures.transcript("12-send-while-offline"))
        let first: MessageID = "76c3ac95-83e0-45e9-a821-a12c08d956e9"
        let second: MessageID = "0c1566bf-a262-4595-b7a6-dd608ba8c3b0"
        try replay.play(throughLine: 14, expecting: "POST /v0/messages")
        #expect(replay.conversation[first]?.delivery == .sending)
        // Accepted on the stream, though the 201 is lost.
        try replay.play(throughLine: 16, expecting: "201 lost")
        #expect(replay.conversation[first]?.delivery == .delivered)
        // The resend's 200, then the second message.
        try replay.play(throughLine: 21, expecting: "POST /v0/messages")
        #expect(replay.conversation.entries.filter { $0.id == first }.count == 1)
        #expect(replay.conversation.entries.last?.id == second)
        #expect(replay.conversation[second]?.delivery == .sending)
        try replay.play(throughLine: 24, expecting: "message.read e_0011_23252")
        #expect(replay.conversation[second]?.mark == .read)
    }

    @Test("Scenario 14: a restart keeps the cut-off reply; a restore matches the server")
    func restartAndRestore() throws {
        var replay = Replay(try Fixtures.transcript("14-the-server-restarts-or-is-restored"))
        try replay.play(throughLine: 28, expecting: "turn.ended e_0020_12669")
        let reply = try #require(replay.conversation["m_0002_05742"])
        #expect(reply.outcome == .interrupted)
        #expect(reply.length == 162 && reply.text.hasSuffix("your book.\n"))
        #expect(replay.conversation.lastEndedTurn?.outcome == .interrupted)

        // Restored from a backup, the snapshot is all there is.
        try replay.play(throughLine: 32, expecting: "snapshot e_0006_60524")
        let ids: [MessageID] = ["bafdbba2-d851-4593-bc68-fdb68d9ab705", "m_0001_43076"]
        #expect(replay.conversation.entries.map(\.id) == ids)
        #expect(replay.conversation.cursor == "e_0006_60524")
        #expect(replay.conversation.lastEndedTurn == nil)
    }

    @Test("Scenario 15: a failure keeps the text and its reason; Try again starts one attempt")
    func somethingFails() throws {
        var replay = Replay(try Fixtures.transcript("15-something-fails"))
        let failedTurn: TurnID = "t_0002_56862"
        let error = ServerError(
            code: .modelTimeout, message: "The model didn't respond for 60 seconds.",
            detail: "No progress from Codex for 60 seconds while it was writing; "
                + "the request to the model was still open.")
        try replay.play(throughLine: 24, expecting: "turn.ended e_0018_42314")
        #expect(replay.conversation["m_0002_07750"]?.outcome == .failed)
        #expect(replay.conversation["m_0002_07750"]?.error == error)
        let ended = try #require(replay.conversation.lastEndedTurn)
        #expect(ended.id == failedTurn && ended.outcome == .failed && ended.error == error)
        #expect(!replay.conversation.retriedTurns.contains(failedTurn))

        try replay.play(throughLine: 25, expecting: "POST /v0/turns/t_0002_56862/retry")
        #expect(replay.conversation.retriedTurns.contains(failedTurn))
        // The new attempt starts, and Couldn't finish is gone.
        try replay.play(throughLine: 26, expecting: "turn.started e_0019_81354")
        #expect(replay.conversation.turn?.retryOf == failedTurn)
        #expect(replay.conversation.lastEndedTurn == nil)
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
}

private func you(_ id: MessageID, _ text: String) -> Expected {
    Expected(id: id, text: text)
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
        ],
    ]
}
