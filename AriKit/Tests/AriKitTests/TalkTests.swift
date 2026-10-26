import AriKit
import Foundation
import Testing

/// Talk mode's half of the contract: calls in the conversation, spoken messages, and the
/// vocabulary that steers recognition.
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

        try replay.play(throughLine: 11, expecting: "message.accepted e_0002_43013")
        let spoken = try #require(
            replay.conversation["3dc7eae9-5c32-46d8-b0a5-5e61c1bfe0bb"]?.spoken)
        #expect(spoken.call == call)
        #expect(spoken.audio?.kind == .audio)
        #expect(
            spoken.corrections == [
                Correction(offset: 9, length: 4, heard: "Bara"),
                Correction(offset: 28, length: 3, heard: "cutie"),
            ])

        try replay.play()
        #expect(replay.conversation.callOn == nil)
        #expect(replay.conversation[call: call]?.durationMs == 1_449_180)
        // The block opens the stretch, above what you said.
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        #expect(items.first == "call \(call)")
        #expect(items.dropFirst().first == "3dc7eae9-5c32-46d8-b0a5-5e61c1bfe0bb")
    }

    @Test("Scenario 40: deleting a call's audio keeps its words")
    func deleteAudio() throws {
        var replay = Replay(try Fixtures.transcript("40-delete-a-call-s-audio"))
        let call: CallID = "77429675-c07e-4b87-aa08-044fa314791d"
        let mine: MessageID = "4ebb2673-f9f9-4c6e-9719-11403eec63de"
        try replay.play(throughLine: 22, expecting: "call.ended e_0011_64773")
        #expect(replay.conversation[mine]?.spoken?.audio != nil)

        try replay.play(throughLine: 25, expecting: "call.audio_deleted e_0012_76782")
        #expect(replay.conversation[call: call]?.audioDeleted == true)
        #expect(replay.conversation[mine]?.spoken?.audio == nil)
        #expect(replay.conversation[mine]?.spoken?.call == call)
        #expect(replay.conversation[mine]?.text == "Today was a good day. The long run felt easy.")
    }

    @Test("Paging back brings the calls of the older messages, and forgetting keeps the one on")
    func history() throws {
        var replay = Replay(try Fixtures.transcript("38-a-walk-with-ari"))
        try replay.play(throughLine: 28, expecting: "turn.ended e_0018_33535")
        var conversation = replay.conversation
        conversation.forgetMessages(before: "m_0002_05333")
        #expect(conversation.callOn?.id == "c40b7f14-bcb1-451e-8d2a-797ec1b00d4c")
    }

    /// The contract's transcript, through the real client: the vocabulary from memory, then
    /// teaching two fixes, then the vocabulary carrying the mishearing.
    @Test("plays transcript 39")
    func vocabulary() async throws {
        let transcript = try Fixtures.transcript("39-ari-learns-a-name")
        let server = TranscriptServer(transcript)
        var vocabularies: [Vocabulary] = []
        for case .app(let request) in transcript.steps {
            switch request.route {
            case .vocabulary:
                vocabularies.append(try await server.client.vocabulary())
            case .teachVocabulary:
                let taught = try await server.client.teach(
                    try #require(request.body).decode(VocabularyCorrections.self))
                #expect(taught.corrections.map(\.address) == ["memory:people/bora", nil])
            default:
                Issue.record("no action for \(request.method) \(request.path)")
            }
        }
        let first = try #require(vocabularies.first)
        let bora = try #require(first.terms.first { $0.text == "Bora" })
        #expect(bora.kind == .person && bora.weight == 1 && bora.address == "memory:people/bora")
        #expect(bora.heard.isEmpty && bora.phrases.count == 2)
        let last = try #require(vocabularies.last)
        #expect(last.terms.first { $0.text == "Bora" }?.heard == ["Bara"])
        #expect(last.terms.contains { $0.text == "QRT" && $0.kind == .term })
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("A spoken message waits for its call to start, and the call ends after it")
    func order() async throws {
        let bench = try Rehearsal(try Fixtures.transcript("04-the-agent-stirs"))
        defer { bench.close() }
        bench.session.start()
        _ = try await bench.nextRequest()
        try await bench.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await bench.settle()

        let call = bench.session.startCall(id: "0b4e0c2a-6f0e-4d7e-9a35-3f1d2b8c7e61")
        let start = try await bench.nextRequest()
        #expect(start.method == .put && start.path == "/v0/calls/\(call)")

        // The start hangs; what you said waits for it.
        let mine: MessageID = "5f0c7d2e-3a41-4b8e-8c9d-1e2f3a4b5c6d"
        bench.session.send("Hello from the river", id: mine, spoken: SendSpoken(call: call))
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil, "the message went before its call")

        try await bench.server.answer(201, json: Self.started(call))
        let send = try await bench.nextRequest()
        #expect(send.path == "/v0/messages")
        #expect(
            try send.body.map { try JSONValue(data: $0) }?["spoken"]
                == JSONValue(json: #"{"call":"\#(call)"}"#))

        // You end the call while the message is still on its way: the end waits for it.
        bench.session.endCall(call)
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil, "the call ended before its message")

        try await bench.server.answer(
            201,
            json:
                #"{"message":{"id":"\#(mine)","role":"user","text":"Hello from the river","at":"2026-10-26T07:30:07.700Z"}}"#
        )
        let end = try await bench.nextRequest()
        #expect(end.method == .post && end.path == "/v0/calls/\(call)/end")
    }

    @Test("Talk decodes as the contract says, and a kind Ari doesn't know is kept")
    func decoding() throws {
        let call = try JSONValue(
            json: #"{"id":"c1","started_at":"2026-10-26T07:30:01.500Z","position":3}"#
        ).decode(Call.self)
        #expect(call.isOn && !call.audioDeleted && call.durationMs == nil)
        let term = try JSONValue(
            json: #"{"text":"Kew","kind":"garden","weight":0.4,"phrases":[],"heard":[]}"#
        ).decode(Vocabulary.Term.self)
        #expect(term.kind.rawValue == "garden" && term.address == nil)
        #expect(
            try JSONValue(encoding: SendSpoken(call: "c1"))
                == JSONValue(json: #"{"call":"c1"}"#))
    }

    private static func started(_ call: CallID) -> String {
        #"{"call":{"id":"\#(call)","started_at":"2026-10-26T07:30:01.500Z","position":1}}"#
    }
}
