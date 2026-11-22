import Foundation

/// A recording you sent in a message, and where its transcript stands. The server transcribes every
/// audio attachment you send, on its own machine, with times and, as a best guess, who spoke.
public struct Recording: Sendable, Equatable, Decodable, Identifiable {
    public var attachment: AttachmentID
    /// The message that carries it.
    public var message: MessageID
    /// Its file name, as uploaded.
    public var name: String
    public var state: RecordingState
    /// `queued` only: why it hasn't started, such as the voice still loading.
    public var reason: String?
    /// `transcribing` only: how far through it the server is.
    public var progress: Progress?
    /// `ready` only: how long it is, in seconds.
    public var durationSeconds: Double?
    /// `ready` only: how many voices the server told apart, a best guess.
    public var speakers: Int?
    /// `failed` only: why.
    public var error: ServerError?
    public var changedAt: Timestamp

    public var id: AttachmentID { attachment }

    public struct Progress: Sendable, Equatable, Decodable {
        public var doneSeconds: Double
        public var totalSeconds: Double?

        /// How far, from 0 to 1, when the length is known.
        public var fraction: Double? {
            guard let totalSeconds, totalSeconds > 0 else { return nil }
            return min(1, max(0, doneSeconds / totalSeconds))
        }

        enum CodingKeys: String, CodingKey {
            case doneSeconds = "done_seconds"
            case totalSeconds = "total_seconds"
        }
    }

    enum CodingKeys: String, CodingKey {
        case attachment, message, name, state, reason, progress, speakers, error
        case durationSeconds = "duration_seconds"
        case changedAt = "changed_at"
    }
}

/// Where a recording's transcript stands. One Ari doesn't know shows as waiting.
public struct RecordingState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Waiting its turn, or for the server's voice to be ready.
    public static let queued = RecordingState(rawValue: "queued")
    public static let transcribing = RecordingState(rawValue: "transcribing")
    public static let ready = RecordingState(rawValue: "ready")
    public static let failed = RecordingState(rawValue: "failed")
    /// Its audio and transcript are gone.
    public static let deleted = RecordingState(rawValue: "deleted")
    public static let known = [queued, transcribing, ready, failed, deleted]
}

/// `recording.changed`: a recording moved on. It carries the whole recording; these are compacted,
/// so after a snapshot Ari fetches the recordings again.
public struct RecordingChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let recording: Recording
}

public struct RecordingList: Sendable, Equatable, Decodable {
    public let recordings: [Recording]
}

public struct RecordingResult: Sendable, Equatable, Decodable {
    public let recording: Recording
}

/// What was said, piece by piece, with times from the start and, where the server could tell, who
/// said it, with your corrections applied.
public struct Transcript: Sendable, Equatable, Decodable {
    public var attachment: AttachmentID
    public var name: String
    public var durationSeconds: Double
    public var language: String
    public var model: String
    /// The voices told apart, a best guess; empty when it couldn't tell.
    public var speakers: [Speaker]
    public var segments: [Segment]
    public var corrections: [Correction]
    public var madeAt: Timestamp

    public struct Speaker: Sendable, Equatable, Codable, Identifiable {
        /// `S1`, `S2`… in the order they first speak, or `you`.
        public var id: String
        /// What to call them, such as "Speaker 1", "You" or a name you gave.
        public var name: String
        public var seconds: Double
        public var you: Bool
    }

    public struct Segment: Sendable, Equatable, Codable {
        public var start: Double
        public var end: Double
        public var text: String
        /// The speaker's `id`, when the server could tell.
        public var speaker: String?
    }

    /// Words the model misheard, and what was really said.
    public struct Correction: Sendable, Equatable, Codable {
        public var heard: String
        public var meant: String

        public init(heard: String, meant: String) {
            self.heard = heard
            self.meant = meant
        }
    }

    public func speaker(_ id: String?) -> Speaker? {
        id.flatMap { id in speakers.first { $0.id == id } }
    }

    enum CodingKeys: String, CodingKey {
        case attachment, name, language, model, speakers, segments, corrections
        case durationSeconds = "duration_seconds"
        case madeAt = "made_at"
    }
}

public struct TranscriptResult: Sendable, Equatable, Decodable {
    public let transcript: Transcript
}

/// The body of `POST /v0/recordings/{attachment}/corrections`.
public struct CorrectTranscript: Sendable, Equatable, Encodable {
    public var replace: [Transcript.Correction]?
    public var speakers: [SpeakerName]?

    public init(replace: [Transcript.Correction]? = nil, speakers: [SpeakerName]? = nil) {
        self.replace = replace
        self.speakers = speakers
    }

    public struct SpeakerName: Sendable, Equatable, Encodable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
}
