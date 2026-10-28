import Foundation
import Observation

/// Ari's voice on the server: its voices, the one chosen, and whether the server can talk. Talk is
/// offered only while it's `ready`; otherwise the reason shows. It's fetched on connect and kept up
/// to date from `voice.status` events.
@MainActor
@Observable
public final class Voices {
    public private(set) var list: VoiceList?
    /// The voice's state: from the last fetch or event; `nil` until the first.
    public private(set) var state: VoiceState?
    /// Why it isn't ready, in a plain line to show.
    public private(set) var reason: String?
    /// A choice on its way to the server.
    public private(set) var choosing: String?
    /// Forgetting your voice is on its way to the server.
    public private(set) var relearning = false

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// Whether Ari can offer Talk now.
    public var canTalk: Bool { state == .ready }

    /// The chosen voice, as Settings names it.
    public var chosen: VoiceOption? {
        guard let list else { return nil }
        return list.voices.first { $0.id == list.chosen }
    }

    /// Fetches the voices and the state, such as on connect. A failed fetch keeps what was there.
    public func refresh() async {
        guard let list = try? await client.voices() else { return }
        self.list = list
        state = list.state
        reason = list.reason
    }

    /// Whether the server knows your voice; `nil` until the first fetch.
    public var voiceprint: VoiceprintState? { list?.voiceprint }

    /// The server said its voice changed.
    public func apply(_ status: VoiceStatus) {
        state = status.state
        reason = status.reason
        list = list?.with(state: status.state, reason: .some(status.reason))
    }

    /// Chooses Ari's voice for the whole server.
    public func choose(_ voice: String) async throws(RequestError) {
        choosing = voice
        defer { choosing = nil }
        let saved = try await client.choose(voice: VoiceChoice(voice: voice))
        list = list?.with(chosen: saved.voice)
    }

    /// Forgets your voice, so the server learns it again from your next calls, starting with one
    /// on now.
    public func relearn() async throws(RequestError) {
        relearning = true
        defer { relearning = false }
        let list = try await client.forgetVoiceprint()
        self.list = list
        state = list.state
        reason = list.reason
    }

    /// A line in a voice, or the chosen one, as a WAV: for previews.
    public func preview(_ text: String, voice: String? = nil) async throws(RequestError) -> Data {
        try await client.speak(SpeechRequest(text: text, voice: voice))
    }
}
