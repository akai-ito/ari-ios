import Foundation

/// A made page's id: readable, chosen by Kumo, unique on the server, such as `va-guide`.
public struct MadeID: OpaqueIdentifier, Identifiable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }
}

/// A page Kumo made: a rich, lasting answer, such as a gallery guide, shown in the chat as a card
/// and kept on the Made shelf. Kumo keeps it current. Its content and your ticks come with its
/// detail, from `GET /v0/made/{id}`.
public struct Made: Sendable, Equatable, Decodable, Identifiable {
    public let id: MadeID
    /// Such as "Your guide to the V&A".
    public let title: String
    /// What's in it, in one line, such as "4 rooms · 9 things to spot".
    public let summary: String
    /// The picture at its top and on its card.
    public let cover: Photo?
    /// The day it's for, such as the visit, as `YYYY-MM-DD`.
    public let forDay: String?
    /// How many times it has changed, counting its making as 1.
    public let version: Int
    public let madeAt: Timestamp
    /// When Kumo last changed it: "Updated 2h ago".
    public let changedAt: Timestamp
    /// The position of your message Kumo was answering when it made the page.
    public let position: Int
    /// The side thread it was made in, which "From your thread" opens; `nil` for the main chat.
    public let thread: ThreadID?

    public init(
        id: MadeID, title: String, summary: String, cover: Photo? = nil, forDay: String? = nil,
        version: Int = 1, madeAt: Timestamp, changedAt: Timestamp? = nil, position: Int = 1,
        thread: ThreadID? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.cover = cover
        self.forDay = forDay
        self.version = version
        self.madeAt = madeAt
        self.changedAt = changedAt ?? madeAt
        self.position = position
        self.thread = thread
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, cover, version, position, thread
        case forDay = "for_day"
        case madeAt = "made_at"
        case changedAt = "changed_at"
    }
}

/// One change to a made page, such as "The Raphael Cartoons reopened this morning, so they're
/// back in."
public struct MadeChange: Sendable, Equatable, Decodable, Identifiable {
    public let version: Int
    public let at: Timestamp
    public let note: String
    public let position: Int

    public var id: Int { version }

    public init(version: Int, at: Timestamp, note: String, position: Int) {
        self.version = version
        self.at = at
        self.note = note
        self.position = position
    }
}

/// Your ticks: when you ticked each item, by its id.
public struct MadeState: Sendable, Equatable, Codable {
    public var ticks: [String: Timestamp]

    public init(ticks: [String: Timestamp] = [:]) { self.ticks = ticks }

    enum CodingKeys: String, CodingKey { case ticks }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A tick that doesn't read, as from a newer server, is skipped rather than losing the rest.
        guard c.contains(.ticks),
            let items = try? c.nestedContainer(keyedBy: ItemKey.self, forKey: .ticks)
        else {
            ticks = [:]
            return
        }
        var ticks: [String: Timestamp] = [:]
        for key in items.allKeys {
            if let time = try? items.decode(Timestamp.self, forKey: key) {
                ticks[key.stringValue] = time
            }
        }
        self.ticks = ticks
    }

    private struct ItemKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// The page under its title: an opening, then its sections in order, as `MadeContent` in the made
/// schema describes.
public struct MadeContent: Sendable, Equatable, Decodable {
    /// A few sentences under the title, in Markdown, which may hold `ari:` blocks.
    public let intro: String?
    /// The word for ticking an item off, such as "Spotted"; `nil` when nothing ticks.
    public let check: String?
    public let sections: [MadeSection]

    public init(intro: String? = nil, check: String? = nil, sections: [MadeSection]) {
        self.intro = intro
        self.check = check
        self.sections = sections
    }

    enum CodingKeys: String, CodingKey { case intro, check, sections }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intro = try c.decodeIfPresent(String.self, forKey: .intro)
        check = try c.decodeIfPresent(String.self, forKey: .check)
        // A section this Ari can't read is left out, not the page.
        sections = (try c.decodeIfPresent([Lenient<MadeSection>].self, forKey: .sections) ?? [])
            .compactMap(\.value)
    }
}

/// One part of a page, such as a room. A numbered one folds; an unnumbered one is a small heading
/// over what it holds, always open.
public struct MadeSection: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let title: String
    /// Such as "Room 46a–b · 25 min".
    public let detail: String?
    /// A word or two Kumo wants seen, such as "Back in".
    public let badge: String?
    public let numbered: Bool
    public let image: Photo?
    /// Markdown, which may hold `ari:` blocks.
    public let text: String?
    public let items: [MadeItem]

    public init(
        id: String, title: String, detail: String? = nil, badge: String? = nil,
        numbered: Bool = true, image: Photo? = nil, text: String? = nil, items: [MadeItem] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.badge = badge
        self.numbered = numbered
        self.image = image
        self.text = text
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case id, title, detail, badge, numbered, image, text, items
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        badge = try c.decodeIfPresent(String.self, forKey: .badge)
        numbered = try c.decodeIfPresent(Bool.self, forKey: .numbered) ?? true
        image = try? c.decodeIfPresent(Photo.self, forKey: .image)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        items = (try c.decodeIfPresent([Lenient<MadeItem>].self, forKey: .items) ?? []).compactMap(
            \.value)
    }
}

/// One thing in a section, such as something to spot.
public struct MadeItem: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String?
    public let image: Photo?

    public init(id: String, title: String, detail: String? = nil, image: Photo? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.image = image
    }

    enum CodingKeys: String, CodingKey { case id, title, detail, image }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        image = try? c.decodeIfPresent(Photo.self, forKey: .image)
    }
}

/// A value that may not read, as from a newer server: `nil` instead of failing what holds it.
private struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// `GET /v0/made`: the Made shelf, most recently changed first.
public struct MadeList: Sendable, Equatable, Decodable {
    public let made: [Made]
}

/// `GET /v0/made/{id}`: one page, with its content, your ticks and the newest of what changed.
public struct MadeDetail: Sendable, Equatable, Decodable {
    public let made: Made
    public let content: MadeContent
    public var state: MadeState
    /// The 20 newest changes, newest first.
    public let changes: [MadeChange]

    public init(
        made: Made, content: MadeContent, state: MadeState = MadeState(), changes: [MadeChange] = []
    ) {
        self.made = made
        self.content = content
        self.state = state
        self.changes = changes
    }
}

/// The answer to ticking: the whole state.
public struct MadeStateBody: Sendable, Equatable, Decodable {
    public let state: MadeState
}

/// `made.created` and `made.changed`: Kumo made a page, or kept one current.
public struct MadeEvent: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let made: Made
    public let change: MadeChange
}

/// `made.state`: your ticks on a page changed, from any device. It carries all of them.
public struct MadeStateChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let made: MadeID
    public let state: MadeState
}

/// `made.removed`: you let Kumo forget a page.
public struct MadeRemoved: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let made: MadeID
}
