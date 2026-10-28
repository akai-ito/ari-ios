import Foundation

/// Whether the server can hold a call: `ready` once it can both listen and speak, with memory's
/// vocabulary loaded. Ari offers Talk only while it's ready, and otherwise shows the reason.
public struct VoiceState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let loading = VoiceState(rawValue: "loading")
    public static let ready = VoiceState(rawValue: "ready")
    /// It can't, until the server restarts.
    public static let failed = VoiceState(rawValue: "failed")
    public static let known = [loading, ready, failed]
}

/// One of Ari's voices on the server.
public struct VoiceOption: Sendable, Equatable, Identifiable, Codable {
    /// Such as `af_heart`.
    public let id: String
    /// Such as Heart.
    public let name: String
    public let accent: VoiceAccent

    public init(id: String, name: String, accent: VoiceAccent) {
        self.id = id
        self.name = name
        self.accent = accent
    }
}

public struct VoiceAccent: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let american = VoiceAccent(rawValue: "american")
    public static let british = VoiceAccent(rawValue: "british")
    public static let known = [american, british]
}

/// Whether the server knows your voice from your calls, so that only a voice like yours holds a
/// turn open.
public struct VoiceprintState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Until it has heard about two minutes of you on calls.
    public static let learning = VoiceprintState(rawValue: "learning")
    public static let learnt = VoiceprintState(rawValue: "learnt")
    public static let known = [learning, learnt]
}

/// `GET /v0/voices`: every voice, the one chosen, whether the server can talk, and whether it
/// knows your voice.
public struct VoiceList: Sendable, Equatable, Codable {
    public let voices: [VoiceOption]
    /// The id of the voice Ari speaks in, for the whole server.
    public let chosen: String
    public let state: VoiceState
    /// Why it isn't ready, in a plain line to show.
    public let reason: String?
    public let voiceprint: VoiceprintState

    public init(
        voices: [VoiceOption], chosen: String, state: VoiceState, reason: String? = nil,
        voiceprint: VoiceprintState
    ) {
        self.voices = voices
        self.chosen = chosen
        self.state = state
        self.reason = reason
        self.voiceprint = voiceprint
    }

    /// The same list with some of it changed.
    func with(
        chosen: String? = nil, state: VoiceState? = nil, reason: String?? = nil,
        voiceprint: VoiceprintState? = nil
    ) -> VoiceList {
        VoiceList(
            voices: voices, chosen: chosen ?? self.chosen, state: state ?? self.state,
            reason: reason ?? self.reason, voiceprint: voiceprint ?? self.voiceprint)
    }
}

/// `PUT /v0/voice`, and its answer: the voice for the whole server.
public struct VoiceChoice: Sendable, Equatable, Codable {
    public let voice: String

    public init(voice: String) { self.voice = voice }
}

/// The body of `POST /v0/speech`: a line to say, in a voice or the chosen one.
public struct SpeechRequest: Sendable, Equatable, Codable {
    public let text: String
    public let voice: String?

    public init(text: String, voice: String? = nil) {
        self.text = text
        self.voice = voice
    }
}

/// `voice.status`: the server's voice changed.
public struct VoiceStatus: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let state: VoiceState
    public let reason: String?
}
