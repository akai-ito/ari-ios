import AriKit
import Foundation
import Testing

/// Ari's voice on the server, through `Voices` and the real client: Settings' list, previews and
/// choice, and Talk following whether the server can talk.
@MainActor
@Suite("Ari's voice")
struct VoicesTests {
    @Test("plays transcript 42: list, preview, choose, and a voice the server doesn't have")
    func choose() async throws {
        let transcript = try Fixtures.transcript("42-choose-ari-s-voice")
        let server = TranscriptServer(transcript)
        let voices = Voices(client: server.client)

        await voices.refresh()
        #expect(voices.canTalk)
        #expect(voices.chosen?.id == "af_heart")
        #expect(
            voices.list?.voices.contains { $0.id == "bf_emma" && $0.accent == .british } == true)

        _ = try await voices.preview("Hi, I'm Ari. This is how I sound.", voice: "bf_emma")
        try await voices.choose("bf_emma")
        #expect(voices.chosen?.id == "bf_emma")

        await voices.refresh()
        _ = try await voices.preview("Hi, I'm Ari. This is how I sound.")
        do {
            try await voices.choose("zz_nobody")
            Issue.record("a voice the server doesn't have was chosen")
        } catch {
            #expect(error.status == 400)
            #expect(voices.chosen?.id == "bf_emma", "a refused choice mustn't stick")
        }
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("plays transcript 56: the server knows your voice, and relearns it when you ask")
    func relearn() async throws {
        let transcript = try Fixtures.transcript("56-relearn-my-voice")
        let server = TranscriptServer(transcript)
        let voices = Voices(client: server.client)

        await voices.refresh()
        #expect(voices.voiceprint == .learnt)
        try await voices.relearn()
        #expect(voices.voiceprint == .learning)
        #expect(voices.canTalk, "relearning leaves the voice ready")
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("plays transcript 43: no Talk while the voice loads, then Talk once it's ready")
    func loading() async throws {
        let transcript = try Fixtures.transcript("43-before-the-voice-is-ready")
        let server = TranscriptServer(transcript, only: { [.voices, .speech].contains($0) })
        let voices = Voices(client: server.client)

        await voices.refresh()
        #expect(voices.state == .loading && !voices.canTalk)
        #expect(voices.reason == "The voice models are still loading.")
        do {
            _ = try await voices.preview("Hi, I'm Ari. This is how I sound.")
            Issue.record("a preview played before the voice was ready")
        } catch {
            #expect(error.status == 503)
        }
        voices.apply(try Self.status(in: transcript))
        #expect(voices.canTalk && voices.reason == nil)
        _ = try await voices.preview("Hi, I'm Ari. This is how I sound.")
        #expect(await server.unanswered == 0)
    }

    @Test("plays transcript 44: the voice fails, so Talk goes and the reason shows")
    func failed() async throws {
        let transcript = try Fixtures.transcript("44-when-the-server-can-t-talk")
        let server = TranscriptServer(transcript, only: { [.voices, .speech].contains($0) })
        let voices = Voices(client: server.client)

        voices.apply(try Self.status(in: transcript))
        #expect(voices.state == .failed && !voices.canTalk)
        #expect(voices.reason == "The GPU ran out of memory loading the voice.")
        await voices.refresh()
        #expect(voices.state == .failed)
        do {
            _ = try await voices.preview("Hi, I'm Ari. This is how I sound.", voice: "am_michael")
            Issue.record("a preview played while the voice had failed")
        } catch {
            #expect(error.status == 503)
        }
        #expect(await server.unanswered == 0)
    }

    @Test("the session keeps the stream's latest voice status")
    func session() async throws {
        let bench = try Rehearsal(try Fixtures.transcript("44-when-the-server-can-t-talk"))
        defer { bench.close() }
        try await bench.play()
        #expect(bench.session.voiceStatus?.state == .failed)
    }

    private static func status(in transcript: Transcript) throws -> VoiceStatus {
        let status = transcript.events.lazy.compactMap { logged -> VoiceStatus? in
            if case .voiceStatus(let status) = logged.event.payload { status } else { nil }
        }.first
        return try #require(status)
    }
}
