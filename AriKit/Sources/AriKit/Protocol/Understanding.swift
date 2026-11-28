import Foundation

// Understanding you: the questions Kumo would like you to explain, on its learning tracks. Each says
// what Kumo already understands, the missing piece and why it would help. They're quiet and
// optional: nothing is due, nothing waits on the Desk, nothing notifies.

/// A question's id.
public struct QuestionID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Where a question stands. One Ari doesn't know counts as dropped.
public struct QuestionState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Waiting quietly for you, for as long as it takes.
    public static let open = QuestionState(rawValue: "open")
    /// You answered it.
    public static let answered = QuestionState(rawValue: "answered")
    /// Kumo learned the answer elsewhere, such as in the chat.
    public static let settled = QuestionState(rawValue: "settled")
    /// Kumo let it go because it no longer helps.
    public static let dropped = QuestionState(rawValue: "dropped")
    public static let known = [open, answered, settled, dropped]

    /// As Ari treats it: one it doesn't know is dropped.
    public var shown: QuestionState { isKnown ? self : .dropped }
}

/// Your answer to a question: the options you tapped, your own words, written or spoken, and whether
/// none fit or you're not sure.
public struct QuestionAnswer: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let picked: [String]
    /// Your words; for a spoken answer, what the server heard once it has.
    public let text: String?
    /// A spoken answer's recording.
    public let audio: AttachmentID?
    public let noneFit: Bool
    public let notSure: Bool

    public init(
        at: Timestamp, picked: [String] = [], text: String? = nil, audio: AttachmentID? = nil,
        noneFit: Bool = false, notSure: Bool = false
    ) {
        self.at = at
        self.picked = picked
        self.text = text
        self.audio = audio
        self.noneFit = noneFit
        self.notSure = notSure
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Timestamp.self, forKey: .at)
        picked = try container.decodeIfPresent([String].self, forKey: .picked) ?? []
        text = try container.decodeIfPresent(String.self, forKey: .text)
        audio = try container.decodeIfPresent(AttachmentID.self, forKey: .audio)
        noneFit = try container.decodeIfPresent(Bool.self, forKey: .noneFit) ?? false
        notSure = try container.decodeIfPresent(Bool.self, forKey: .notSure) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case at, picked, text, audio
        case noneFit = "none_fit"
        case notSure = "not_sure"
    }
}

/// Something Kumo would like you to explain, on one of its learning tracks.
public struct Question: Sendable, Equatable, Decodable, Identifiable {
    public let id: QuestionID
    /// The learning track it belongs to.
    public let track: TrackID
    public let state: QuestionState
    /// What Kumo already understands, in a sentence or two.
    public let understood: String
    /// The missing piece, asked as one question.
    public let missing: String
    /// Why it would help, in a line.
    public let why: String
    /// Quick answers to tap, one or several; empty when only your own words will do.
    public let options: [String]
    public let askedAt: Timestamp
    public let changedAt: Timestamp
    /// `open` only: the last time you said "Not now". Show it after the rest.
    public let laterAt: Timestamp?
    /// `open` only: your spoken answer couldn't be heard, and why.
    public let unheard: String?
    /// `answered` only: what you said.
    public let answer: QuestionAnswer?
    /// `answered` only, once Kumo has filed it: what it took from your answer.
    public let filed: String?
    /// `settled`: where Kumo learned the answer. `dropped`: why it let it go.
    public let note: String?

    public init(
        id: QuestionID, track: TrackID, state: QuestionState = .open, understood: String,
        missing: String, why: String, options: [String] = [], askedAt: Timestamp,
        changedAt: Timestamp? = nil, laterAt: Timestamp? = nil, unheard: String? = nil,
        answer: QuestionAnswer? = nil, filed: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.track = track
        self.state = state
        self.understood = understood
        self.missing = missing
        self.why = why
        self.options = options
        self.askedAt = askedAt
        self.changedAt = changedAt ?? askedAt
        self.laterAt = laterAt
        self.unheard = unheard
        self.answer = answer
        self.filed = filed
        self.note = note
    }

    /// Whether it's still waiting for you.
    public var isOpen: Bool { state.shown == .open }

    enum CodingKeys: String, CodingKey {
        case id, track, state, understood, missing, why, options, unheard, answer, filed, note
        case askedAt = "asked_at"
        case changedAt = "changed_at"
        case laterAt = "later_at"
    }
}

/// The answer to `GET /v0/understanding`: every track, the open questions (those set aside last) and
/// what was answered or settled in the last 14 days, newest first.
public struct Understanding: Sendable, Equatable, Decodable {
    public let tracks: [Track]
    public let questions: [Question]
    public let recent: [Question]

    public init(tracks: [Track] = [], questions: [Question] = [], recent: [Question] = []) {
        self.tracks = tracks
        self.questions = questions
        self.recent = recent
    }

    /// With a question as the server now has it: an open one in its place among the open ones (set
    /// aside ones last), one that moved on among the recent ones, newest first.
    public func with(_ question: Question) -> Understanding {
        var open = questions.filter { $0.id != question.id }
        var recent = recent.filter { $0.id != question.id }
        if question.isOpen {
            open.append(question)
            open = Self.ordered(open)
        } else if question.state.shown != .dropped {
            recent.insert(question, at: 0)
        }
        return Understanding(tracks: tracks, questions: open, recent: recent)
    }

    /// Those you haven't set aside, oldest first, then those you said "Not now" to.
    static func ordered(_ questions: [Question]) -> [Question] {
        questions.sorted { a, b in
            switch (a.laterAt, b.laterAt) {
            case (nil, nil): a.askedAt.date < b.askedAt.date
            case (nil, _): true
            case (_, nil): false
            case (let x?, let y?): x.date < y.date
            }
        }
    }
}

/// The body of `POST /v0/understanding/questions/{question}/answer`: options you tapped, your words
/// as text or a recording, and none fit or not sure. At least one; none fit doesn't go with picks.
public struct QuestionReply: Sendable, Equatable, Encodable {
    public var picked: [String]
    public var text: String?
    public var audio: AttachmentID?
    public var noneFit: Bool
    public var notSure: Bool

    public init(
        picked: [String] = [], text: String? = nil, audio: AttachmentID? = nil,
        noneFit: Bool = false, notSure: Bool = false
    ) {
        self.picked = picked
        self.text = text
        self.audio = audio
        self.noneFit = noneFit
        self.notSure = notSure
    }

    /// Whether it says anything at all.
    public var isEmpty: Bool {
        picked.isEmpty && (text ?? "").isEmpty && audio == nil && !noneFit && !notSure
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !picked.isEmpty { try container.encode(picked, forKey: .picked) }
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(audio, forKey: .audio)
        if noneFit { try container.encode(true, forKey: .noneFit) }
        if notSure { try container.encode(true, forKey: .notSure) }
    }

    enum CodingKeys: String, CodingKey {
        case picked, text, audio
        case noneFit = "none_fit"
        case notSure = "not_sure"
    }
}

extension QuestionReply: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        picked = try container.decodeIfPresent([String].self, forKey: .picked) ?? []
        text = try container.decodeIfPresent(String.self, forKey: .text)
        audio = try container.decodeIfPresent(AttachmentID.self, forKey: .audio)
        noneFit = try container.decodeIfPresent(Bool.self, forKey: .noneFit) ?? false
        notSure = try container.decodeIfPresent(Bool.self, forKey: .notSure) ?? false
    }
}

/// The answer to answering a question, or saying "Not now" to it: the question as it is now.
public struct QuestionResult: Sendable, Equatable, Decodable {
    public let question: Question
}

/// `question.changed`: a question was added or moved on. It carries the whole question, and never
/// notifies.
public struct QuestionChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let question: Question
}
