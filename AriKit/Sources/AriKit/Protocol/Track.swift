import Foundation

// The areas Kumo is getting to know you in, or learning to do well: each a track with a stage, and
// the evidence it stands on. Kumo opens and moves them by judgement; a correction always steps one
// back.

/// A track's id.
public struct TrackID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// An area Kumo is getting to know you in, or learning to do well, such as sorting your mail,
/// writing as you or planning your weekends.
public struct Track: Sendable, Equatable, Decodable, Identifiable {
    public let id: TrackID
    /// Such as "Writing as you".
    public let name: String
    public let stage: TrackStage
    /// When it reached this stage.
    public let since: Timestamp
    /// Kumo's line on where it stands, such as "Three weeks of drafts you sent as I wrote them."
    public let note: String?
    /// How many times you've confirmed Kumo got it right.
    public let confirmed: Int
    /// How many times you've corrected it, such as with "That was wrong".
    public let corrected: Int
    /// What it stands on, newest first, the latest ten.
    public let evidence: [TrackEvidence]

    public init(
        id: TrackID, name: String, stage: TrackStage, since: Timestamp, note: String? = nil,
        confirmed: Int = 0, corrected: Int = 0, evidence: [TrackEvidence] = []
    ) {
        self.id = id
        self.name = name
        self.stage = stage
        self.since = since
        self.note = note
        self.confirmed = confirmed
        self.corrected = corrected
        self.evidence = evidence
    }
}

/// How far Kumo has come in an area. One Ari doesn't know shows as Learning.
public struct TrackStage: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Kumo shows you its calls and asks when unsure.
    public static let learning = TrackStage(rawValue: "learning")
    /// Kumo checks with you now and then.
    public static let spotChecks = TrackStage(rawValue: "spot_checks")
    /// Kumo brings only what needs you.
    public static let trusted = TrackStage(rawValue: "trusted")
    public static let known = [learning, spotChecks, trusted]

    /// Where it stands, from 0 for Learning to 2 for Trusted.
    public var rung: Int { Self.known.firstIndex(of: self) ?? 0 }
}

/// One thing a track stands on: a time you confirmed Kumo got it right, corrected it, or Kumo moved
/// it to another stage, with why.
public struct TrackEvidence: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let kind: Kind
    /// In a line, such as "You sent the Tess draft as I wrote it".
    public let text: String
    /// The stage it moved to, or stepped back to after a correction.
    public let stage: TrackStage?
    /// The call it was about, in Done.
    public let done: DoneID?

    public init(
        at: Timestamp, kind: Kind, text: String, stage: TrackStage? = nil, done: DoneID? = nil
    ) {
        self.at = at
        self.kind = kind
        self.text = text
        self.stage = stage
        self.done = done
    }

    /// What happened. One Ari doesn't know shows its text alone.
    public struct Kind: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let confirmed = Kind(rawValue: "confirmed")
        public static let corrected = Kind(rawValue: "corrected")
        public static let moved = Kind(rawValue: "moved")
        public static let known = [confirmed, corrected, moved]
    }
}
