import Foundation

/// A chapter of your life that Kumo noticed and named, such as "Florence with Mira", as the
/// Library's row shows it: its name, when, and the photo it opens with. The chapter itself is a page
/// on the `chapters` shelf.
public struct Chapter: Sendable, Equatable, Identifiable, Decodable {
    public let address: PageAddress
    public let title: String
    public let gist: String?
    public let began: LocalTime
    /// The day it ended; `nil` while it's still going.
    public let ended: LocalTime?
    /// The first photo its story shows.
    public let cover: MemoryPhoto?
    public let changedAt: Timestamp

    public var id: PageAddress { address }
    public var isGoing: Bool { ended == nil }

    public init(
        address: PageAddress, title: String, gist: String? = nil, began: LocalTime,
        ended: LocalTime? = nil, cover: MemoryPhoto? = nil, changedAt: Timestamp
    ) {
        self.address = address
        self.title = title
        self.gist = gist
        self.began = began
        self.ended = ended
        self.cover = cover
        self.changedAt = changedAt
    }

    enum CodingKeys: String, CodingKey {
        case address, title, gist, began, ended, cover
        case changedAt = "changed_at"
    }
}

/// `GET /v0/memory/chapters`: those still going first, then the latest to end.
public struct ChapterList: Sendable, Equatable, Decodable {
    public let chapters: [Chapter]
}

/// What a chapter's page says about the chapter: when, when Kumo noticed it, and what it drew on,
/// as the server counted it.
public struct ChapterFacts: Sendable, Equatable, Codable {
    public let began: LocalTime
    public let ended: LocalTime?
    /// The day Kumo first wrote it; `nil` for a chapter that came from outside.
    public let noticed: LocalTime?
    public let drawnFrom: DrawnFrom

    public struct DrawnFrom: Sendable, Equatable, Codable {
        public let journalDays: Int
        public let photos: Int

        public init(journalDays: Int, photos: Int) {
            self.journalDays = journalDays
            self.photos = photos
        }

        enum CodingKeys: String, CodingKey {
            case photos
            case journalDays = "journal_days"
        }
    }

    public init(
        began: LocalTime, ended: LocalTime? = nil, noticed: LocalTime? = nil, drawnFrom: DrawnFrom
    ) {
        self.began = began
        self.ended = ended
        self.noticed = noticed
        self.drawnFrom = drawnFrom
    }

    enum CodingKeys: String, CodingKey {
        case began, ended, noticed
        case drawnFrom = "drawn_from"
    }
}

/// Something Kumo learnt about you, in its own words to you, with when and the page whose change
/// taught it.
public struct LearntLine: Sendable, Hashable, Identifiable, Decodable {
    public let text: String
    public let at: Timestamp
    public let address: PageAddress
    public let change: String

    public var id: String { change }

    public init(text: String, at: Timestamp, address: PageAddress, change: String) {
        self.text = text
        self.at = at
        self.address = address
        self.change = change
    }
}

/// `GET /v0/memory/learnt`: the newest few, newest first.
public struct LearntLines: Sendable, Equatable, Decodable {
    public let lines: [LearntLine]
}

/// A day writes back as it was sent, so a page holding a chapter can be kept as it came.
extension LocalTime: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
