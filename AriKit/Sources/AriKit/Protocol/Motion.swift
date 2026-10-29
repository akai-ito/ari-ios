import Foundation

/// A thing's id: readable, chosen by Ari, unique on the server, such as `florence-with-janki`.
public struct MotionID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A thing in motion: something going on that Ari keeps for you, such as a trip being planned. Its
/// content and your ticks come with its detail, from `GET /v0/motion/{id}`.
public struct Motion: Sendable, Equatable, Decodable, Identifiable {
    public let id: MotionID
    /// Which widget draws it. A kind Ari doesn't know shows as a plain card.
    public let kind: MotionKind
    /// Such as "Florence with Janki".
    public let title: String
    /// Where it stands, in one line, as Ari last wrote it, such as "6–9 Nov · 3 to book".
    public let summary: String
    public let status: MotionStatus
    /// Whether it's pinned above the composer. Ari pins what it starts, and pins or unpins on your
    /// word.
    public let pinned: Bool
    /// The cover photo, for the card.
    public let cover: AttachmentID?
    /// How many times it has changed, counting its start as 1.
    public let version: Int
    public let startedAt: Timestamp
    public let changedAt: Timestamp
    public let doneAt: Timestamp?
    /// The position of your message Ari was answering when it started the thing.
    public let position: Int

    public init(
        id: MotionID, kind: MotionKind, title: String, summary: String,
        status: MotionStatus = .active, pinned: Bool = true, cover: AttachmentID? = nil,
        version: Int = 1, startedAt: Timestamp, changedAt: Timestamp? = nil,
        doneAt: Timestamp? = nil, position: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.status = status
        self.pinned = pinned
        self.cover = cover
        self.version = version
        self.startedAt = startedAt
        self.changedAt = changedAt ?? startedAt
        self.doneAt = doneAt
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, status, pinned, cover, version, position
        case startedAt = "started_at"
        case changedAt = "changed_at"
        case doneAt = "done_at"
    }
}

/// Which widget draws a thing in motion. Show a plain card for a kind Ari doesn't know.
public struct MotionKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A day, a weekend or a longer trip.
    public static let trip = MotionKind(rawValue: "trip")
    /// A training block towards a goal, such as a sub-20 5K.
    public static let training = MotionKind(rawValue: "training")
    public static let known = [trip, training]
}

/// Whether a thing is going on, or done. Ari treats a status it doesn't know as going on.
public struct MotionStatus: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let active = MotionStatus(rawValue: "active")
    public static let done = MotionStatus(rawValue: "done")
    public static let known = [active, done]
}

/// One entry of "What changed".
public struct MotionChange: Sendable, Equatable, Decodable, Identifiable {
    public let version: Int
    public let at: Timestamp
    /// Ari's note, such as "Booked the Uffizi, 8:15 Saturday".
    public let note: String
    /// The position of your message Ari was answering when it made the change.
    public let position: Int

    public var id: Int { version }

    public init(version: Int, at: Timestamp, note: String, position: Int) {
        self.version = version
        self.at = at
        self.note = note
        self.position = position
    }
}

/// Your ticks, by list and then by item id, such as `todo` → `book-uffizi` → done. `[:]` until you
/// tick something. A tick here wins over how Ari wrote the item.
public typealias MotionState = [String: [String: MotionTick]]

/// Reads ticks, skipping any field that isn't a list of them, as from a newer server.
private struct TolerantState: Decodable {
    let state: MotionState

    init(from decoder: any Decoder) throws {
        let lists = try decoder.container(keyedBy: ItemKey.self)
        var state: MotionState = [:]
        for list in lists.allKeys {
            guard let items = try? lists.nestedContainer(keyedBy: ItemKey.self, forKey: list) else {
                continue
            }
            for item in items.allKeys {
                if let tick = try? items.decode(MotionTick.self, forKey: item) {
                    state[list.stringValue, default: [:]][item.stringValue] = tick
                }
            }
        }
        self.state = state
    }

    private struct ItemKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeState(forKey key: Key) -> MotionState {
        (try? decode(TolerantState.self, forKey: key).state) ?? [:]
    }
}

public struct MotionTick: Sendable, Equatable, Codable {
    public let done: Bool

    public init(done: Bool) { self.done = done }
}

/// `GET /v0/motion`: everything going on, then what's done, each newest first.
public struct MotionList: Sendable, Equatable, Decodable {
    public let motions: [Motion]
}

/// `GET /v0/motion/{id}`: one thing, with its content, your ticks and the newest of what changed.
public struct MotionDetail: Sendable, Equatable, Decodable {
    public let motion: Motion
    public let content: MotionContent
    public var state: MotionState
    /// The 20 newest entries of "What changed", newest first.
    public var changes: [MotionChange]

    public init(
        motion: Motion, content: MotionContent, state: MotionState = [:],
        changes: [MotionChange] = []
    ) {
        self.motion = motion
        self.content = content
        self.state = state
        self.changes = changes
    }

    enum CodingKeys: String, CodingKey { case motion, content, state, changes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        motion = try c.decode(Motion.self, forKey: .motion)
        changes = try c.decode([MotionChange].self, forKey: .changes)
        state = c.decodeState(forKey: .state)
        content =
            switch motion.kind {
            case .trip:
                (try? c.decode(Trip.self, forKey: .content)).map(MotionContent.trip)
                    ?? .unreadable
            case .training:
                (try? c.decode(Training.self, forKey: .content)).map(MotionContent.training)
                    ?? .unreadable
            default: .unknown
            }
    }
}

/// What a thing holds, as its kind describes.
public enum MotionContent: Sendable, Equatable {
    case trip(Trip)
    case training(Training)
    /// A kind this Ari doesn't know: it shows as a plain card.
    case unknown
    /// A kind Ari knows, in a shape it can't read, as from a newer server.
    case unreadable
}

/// The body of `PATCH /v0/motion/{id}/state`, and its answer: ticks by list and item.
public struct MotionStateBody: Sendable, Equatable, Codable {
    public let state: MotionState
}

/// `motion.started`, `motion.changed` and `motion.finished`: Ari started a thing, changed it (or
/// brought back an earlier version), or finished it. Fetch its content again.
public struct MotionEvent: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let motion: Motion
    /// This change, as it appears in "What changed".
    public let change: MotionChange
}

/// `motion.state`: a thing's ticks changed, from a tap on any device. It carries all of them.
public struct MotionStateChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let motion: MotionID
    public let state: MotionState

    enum CodingKeys: String, CodingKey { case at, motion, state }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Timestamp.self, forKey: .at)
        motion = try c.decode(MotionID.self, forKey: .motion)
        state = c.decodeState(forKey: .state)
    }
}

/// `motion.removed`: you let Ari forget a thing, so it's gone.
public struct MotionRemoved: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let motion: MotionID
}
