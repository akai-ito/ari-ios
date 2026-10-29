import AriKit
import Foundation
import Testing

/// Talk mode's half of the contract in the conversation: calls, and the spoken messages the server
/// posts for what you said, with teaching Ari a word.
@MainActor
@Suite("Talk")
struct TalkTests {
    @Test("Scenario 38: the call opens a stretch of the conversation, and closes with its length")
    func walk() throws {
        var replay = Replay(try Fixtures.transcript("38-a-walk-with-ari"))
        let call: CallID = "c40b7f14-bcb1-451e-8d2a-797ec1b00d4c"
        try replay.play(throughLine: 6, expecting: "call.started e_0001_69536")
        #expect(replay.conversation.callOn?.id == call)
        #expect(replay.conversation[call: call]?.position == 1)

        // The server posts what you said, as a spoken message with its recording.
        try replay.play(throughLine: 17, expecting: "message.accepted e_0002_43013")
        let spoken = try #require(replay.conversation["m_0001_72021"]?.spoken)
        #expect(spoken.call == call)
        #expect(spoken.audio?.kind == .audio)

        try replay.play()
        #expect(replay.conversation.callOn == nil)
        #expect(replay.conversation[call: call]?.durationMs == 1_458_100)
        // The block opens the stretch, above what you said.
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        #expect(items.first == "call \(call)")
        #expect(items.dropFirst().first == "m_0001_72021")
    }

    @Test("Scenario 40: deleting a call's audio keeps its words")
    func deleteAudio() throws {
        var replay = Replay(try Fixtures.transcript("40-delete-a-call-s-audio"))
        let call: CallID = "77429675-c07e-4b87-aa08-044fa314791d"
        let mine: MessageID = "m_0001_90849"
        try replay.play(throughLine: 33, expecting: "call.ended e_0009_54098")
        #expect(replay.conversation[mine]?.spoken?.audio != nil)

        try replay.play(throughLine: 36, expecting: "call.audio_deleted e_0010_64795")
        #expect(replay.conversation[call: call]?.audioDeleted == true)
        #expect(replay.conversation[mine]?.spoken?.audio == nil)
        #expect(replay.conversation[mine]?.spoken?.call == call)
        #expect(replay.conversation[mine]?.text == "Today was a good day. The long run felt easy.")
    }

    @Test("Scenario 41: another device's first snapshot carries the call before what was said")
    func anotherDevice() throws {
        var replay = Replay(try Fixtures.transcript("41-another-device-sees-the-call"))
        try replay.play()
        let call: CallID = "e1a0a4da-4694-4924-95f4-f91185ff711e"
        #expect(replay.conversation[call: call]?.durationMs == 307_502)
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        #expect(items.first == "call \(call)")
        #expect(items.dropFirst().first == "914f3838-aaa0-49a3-89cd-57b1b6391d24")
    }

    @Test("Forgetting older messages keeps the call that's on")
    func history() throws {
        var replay = Replay(try Fixtures.transcript("38-a-walk-with-ari"))
        try replay.play(throughLine: 41, expecting: "turn.ended e_0014_69065")
        var conversation = replay.conversation
        conversation.forgetMessages(before: "m_0003_60545")
        #expect(conversation.callOn?.id == "c40b7f14-bcb1-451e-8d2a-797ec1b00d4c")
    }

    @Test(
        "Scenario 53: an app's approval waits inside the running turn, which carries on after Allow"
    )
    func approvalInsideTurn() throws {
        var replay = Replay(try Fixtures.transcript("53-an-app-asks-first"))
        try replay.play(throughLine: 12, expecting: "turn.status e_0006_98446")
        #expect(replay.conversation.turn != nil, "the turn is still running")
        #expect(replay.conversation.waitingAsk?.kind == .approval)
        #expect(replay.conversation.turn?.status?.kind == .waiting)
        try replay.play()
        #expect(replay.conversation.waitingAsk == nil && replay.conversation.turn == nil)
        #expect(replay.conversation[ask: "a_0001_06578"]?.outcome == .answered)
    }

    @Test("Scenario 55: Stop cancels an app's approval that waits inside the turn")
    func stoppedApproval() throws {
        var replay = Replay(try Fixtures.transcript("55-stopped-while-an-app-waits"))
        try replay.play()
        #expect(replay.conversation[ask: "a_0001_72312"]?.outcome == .cancelled)
        #expect(replay.conversation.waitingAsk == nil && replay.conversation.turn == nil)
    }

    @Test("Scenario 61: words carried on before Ari answers join the message you'd just spoken")
    func carryOn() throws {
        var replay = Replay(try Fixtures.transcript("61-you-carry-on"))
        let mine: MessageID = "m_0001_92355"
        try replay.play(throughLine: 15, expecting: "message.accepted e_0002_70150")
        #expect(replay.conversation[mine]?.text == "I keep thinking about Florence.")
        let first = replay.conversation[mine]?.spoken?.audio?.id
        try replay.play(throughLine: 23, expecting: "message.amended e_0004_34331")
        #expect(
            replay.conversation[mine]?.text
                == "I keep thinking about Florence. Should we take a day for Pisa, or stay put?")
        #expect(
            replay.conversation[mine]?.spoken?.audio?.id != first, "one recording of both parts")
        #expect(replay.conversation.entries.filter { $0.role == .user }.count == 1)
    }

    @Test("a call decodes as the contract says")
    func decoding() throws {
        let call = try JSONValue(
            json: #"{"id":"c1","started_at":"2026-10-26T07:30:01.500Z","position":3}"#
        ).decode(Call.self)
        #expect(call.isOn && !call.audioDeleted && call.durationMs == nil)
    }
}
