import Foundation

/// A call's id: a random UUID Ari makes when you start one, which is also its retry key.
public struct CallID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A call with Ari, shown in the conversation as a block that opens and closes the stretch it
/// covered.
public struct Call: Hashable, Sendable, Identifiable, Decodable {
    public var id: CallID
    public var startedAt: Timestamp
    /// Where the call started in the conversation, in one order with messages and steps.
    public var position: Int
    /// When it ended; `nil` while it's on.
    public var endedAt: Timestamp?
    public var durationMs: Int?
    /// You deleted the audio of its spoken messages; their text stays.
    public var audioDeleted: Bool

    public var isOn: Bool { endedAt == nil }

    public init(id: CallID, startedAt: Timestamp, position: Int) {
        self.id = id
        self.startedAt = startedAt
        self.position = position
        self.audioDeleted = false
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(CallID.self, forKey: .id)
        startedAt = try c.decode(Timestamp.self, forKey: .startedAt)
        position = try c.decode(Int.self, forKey: .position)
        endedAt = try c.decodeIfPresent(Timestamp.self, forKey: .endedAt)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        audioDeleted = try c.decodeIfPresent(Bool.self, forKey: .audioDeleted) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case id, position
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case audioDeleted = "audio_deleted"
    }
}

/// `call.started`, `call.ended` and `call.audio_deleted`: the call as it now stands.
public struct CallEvent: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let call: Call
}

/// The answer to starting, ending or deleting the audio of a call.
public struct CallResult: Sendable, Equatable, Decodable {
    public let call: Call
}

/// How a message you spoke on a call came to be.
public struct Spoken: Hashable, Sendable, Codable {
    public var call: CallID
    /// Your recording, while it's kept.
    public var audio: Attachment?
    /// The words the phone corrected in the message's text.
    public var corrections: [Correction]?

    public init(call: CallID, audio: Attachment? = nil, corrections: [Correction]? = nil) {
        self.call = call
        self.audio = audio
        self.corrections = corrections
    }
}

/// A word the phone corrected in a spoken message: the text from `offset` for `length` (UTF-16 code
/// units, as message deltas count) is what it meant; `heard` is what the recogniser heard.
public struct Correction: Hashable, Sendable, Codable {
    public var offset: Int
    public var length: Int
    public var heard: String

    public init(offset: Int, length: Int, heard: String) {
        self.offset = offset
        self.length = length
        self.heard = heard
    }
}

/// The `spoken` part of `POST /v0/messages`: the call, the recording's attachment (uploaded first)
/// and the corrections.
public struct SendSpoken: Hashable, Sendable, Codable {
    public var call: CallID
    public var audio: AttachmentID?
    public var corrections: [Correction]?

    public init(call: CallID, audio: AttachmentID? = nil, corrections: [Correction] = []) {
        self.call = call
        self.audio = audio
        self.corrections = corrections.isEmpty ? nil : corrections
    }
}

/// `GET /v0/vocabulary`: words to steer speech recognition, heaviest first.
public struct Vocabulary: Sendable, Equatable, Codable {
    public let terms: [Term]

    public init(terms: [Term]) { self.terms = terms }

    public struct Term: Sendable, Equatable, Codable {
        /// As it should be written.
        public let text: String
        public let kind: TermKind
        /// How much it's used, 0 to 1.
        public let weight: Double
        /// Up to three short phrases that use it, from real use.
        public let phrases: [String]
        /// Mishearings learnt for it.
        public let heard: [String]
        public let address: PageAddress?

        public init(
            text: String, kind: TermKind, weight: Double, phrases: [String] = [], heard: [String] = [],
            address: PageAddress? = nil
        ) {
            self.text = text
            self.kind = kind
            self.weight = weight
            self.phrases = phrases
            self.heard = heard
            self.address = address
        }
    }
}

/// Where a vocabulary term comes from. Ari treats one it doesn't know as a plain term.
public struct TermKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let person = TermKind(rawValue: "person")
    public static let place = TermKind(rawValue: "place")
    public static let project = TermKind(rawValue: "project")
    public static let goal = TermKind(rawValue: "goal")
    public static let topic = TermKind(rawValue: "topic")
    /// A word from conversation, or one you taught it.
    public static let term = TermKind(rawValue: "term")
    public static let known = [person, place, project, goal, topic, term]
}

/// `POST /v0/vocabulary/corrections`, and its answer: what the recogniser heard and what you meant.
public struct VocabularyCorrections: Sendable, Equatable, Codable {
    public let corrections: [Pair]

    public init(corrections: [Pair]) { self.corrections = corrections }

    public struct Pair: Sendable, Equatable, Codable {
        public let heard: String
        public let meant: String
        /// In an answer, the page the mishearing joined, if any.
        public let address: PageAddress?

        public init(heard: String, meant: String, address: PageAddress? = nil) {
            self.heard = heard
            self.meant = meant
            self.address = address
        }
    }
}
