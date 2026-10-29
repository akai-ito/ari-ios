import Foundation

/// Where a page of Ari's memory lives, such as `memory:people/alex` or `memory:journal/2026-10-25`.
/// Opaque: Ari never builds one, only passes back what the server gave.
public struct PageAddress: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A page of what Ari knows: Portrait, Now, How to help you, a page on a shelf, or a day of the
/// journal. Ari writes every page; the app only reads them.
public struct MemoryPage: Sendable, Equatable, Identifiable, Codable {
    public let address: PageAddress
    public let title: String
    /// Its shelf (`people`, `goals`, `projects`, `places`, `topics`, `journal`), or `portrait`,
    /// `now` or `helping-you` for the three pages always in mind.
    public let shelf: String
    /// Other names Ari knows it by.
    public let aliases: [String]
    /// The related pages that exist, in Ari's order.
    public let links: [MemoryLink]
    /// What the page is now, in a line Ari keeps current; absent until Ari has written one.
    public let gist: String?
    public let changedAt: Timestamp
    /// The page as Ari wrote it, in Markdown without its front matter: the present first, then
    /// *Earlier* with dates.
    public let markdown: String

    public var id: PageAddress { address }

    public init(
        address: PageAddress, title: String, shelf: String, aliases: [String] = [],
        links: [MemoryLink] = [], gist: String? = nil, changedAt: Timestamp, markdown: String
    ) {
        self.address = address
        self.title = title
        self.shelf = shelf
        self.aliases = aliases
        self.links = links
        self.gist = gist
        self.changedAt = changedAt
        self.markdown = markdown
    }

    enum CodingKeys: String, CodingKey {
        case address, title, shelf, aliases, links, gist, markdown
        case changedAt = "changed_at"
    }
}

/// A page another links to, as it is now: its name, and the other names it goes by, for finding
/// where the words mention it.
public struct MemoryLink: Sendable, Hashable, Codable {
    public let address: PageAddress
    public let title: String
    public let aliases: [String]

    public init(address: PageAddress, title: String, aliases: [String] = []) {
        self.address = address
        self.title = title
        self.aliases = aliases
    }
}

/// A page named without its words: a row in a list, or a page on a memory step, where
/// `changedAt` is absent.
public struct PageSummary: Sendable, Hashable, Identifiable, Codable {
    public let address: PageAddress
    public let title: String
    /// What the page is now, in a line: a journal day's headline, who someone is to you.
    public let gist: String?
    /// People pages only: who they are to you, in Ari's words, such as `family` or `work`, the
    /// same words across people, so they group.
    public let circle: String?
    public let changedAt: Timestamp?

    public var id: PageAddress { address }

    public init(
        address: PageAddress, title: String, gist: String? = nil, circle: String? = nil,
        changedAt: Timestamp? = nil
    ) {
        self.address = address
        self.title = title
        self.gist = gist
        self.circle = circle
        self.changedAt = changedAt
    }

    enum CodingKeys: String, CodingKey {
        case address, title, gist, circle
        case changedAt = "changed_at"
    }
}

/// One change Ari made to memory, with its note on what changed.
public struct RecentChange: Sendable, Hashable, Identifiable, Codable {
    public let change: String
    public let address: PageAddress
    /// The page's title when it changed.
    public let title: String
    public let at: Timestamp
    /// What the change did, in a few words, such as "Florence together 6–9 Nov". Absent for pages
    /// that came from outside, and for changes from before Ari wrote notes.
    public let note: String?

    public var id: String { change }
}

/// `GET /v0/memory/recent`: the newest changes, newest first, one row per change.
public struct RecentChanges: Sendable, Equatable, Codable {
    public let changes: [RecentChange]
}

/// A shelf and how many pages are on it.
public struct Shelf: Sendable, Equatable, Identifiable, Codable {
    public let shelf: String
    public let count: Int

    public var id: String { shelf }

    public init(shelf: String, count: Int) {
        self.shelf = shelf
        self.count = count
    }
}

/// `GET /v0/memory/shelves`.
public struct ShelfList: Sendable, Equatable, Codable {
    public let shelves: [Shelf]
}

/// `GET /v0/memory/pages?shelf=…`: a shelf's pages, most recently changed first.
public struct PageList: Sendable, Equatable, Codable {
    public let pages: [PageSummary]
}

/// `GET /v0/memory/in-mind`: the pages that go into every reply, in full.
public struct MemoryPages: Sendable, Equatable, Codable {
    public let pages: [MemoryPage]
}

/// `GET /v0/memory/changes/{change}`: one update to a page, as its Markdown before and after.
public struct PageChange: Sendable, Equatable, Codable {
    public let change: String
    public let address: PageAddress
    public let title: String
    public let at: Timestamp
    /// The page before, or `nil` when the update created it.
    public let before: String?
    /// The page after, or `nil` when the update deleted it.
    public let after: String?

    public init(
        change: String, address: PageAddress, title: String, at: Timestamp, before: String?,
        after: String?
    ) {
        self.change = change
        self.address = address
        self.title = title
        self.at = at
        self.before = before
        self.after = after
    }

    /// The present as the page now reads: everything above its *Earlier* section.
    public var present: String { Self.split(after ?? "").present }

    /// The lines that moved into *Earlier* with this update.
    public var movedToEarlier: [String] {
        let old = Set(Self.split(before ?? "").earlier)
        return Self.split(after ?? "").earlier.filter { !old.contains($0) }
    }

    /// A page's Markdown, cut at its `## Earlier` heading.
    static func split(_ markdown: String) -> (present: String, earlier: [String]) {
        var present: [Substring] = []
        var earlier: [String] = []
        var inEarlier = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).lowercased() == "## earlier" {
                inEarlier = true
            } else if inEarlier {
                let item = line.trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { earlier.append(item) }
            } else {
                present.append(line)
            }
        }
        return (
            present.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), earlier
        )
    }
}

extension PageAddress: Identifiable {
    public var id: String { rawValue }
}

extension PageAddress {
    /// Past conversations, as a memory step names them: not a page you can open.
    public static let pastConversations = PageAddress("conversation:past")

    /// Whether it's a page of memory, which can be opened.
    public var isPage: Bool { rawValue.hasPrefix("memory:") }

    /// A readable name from the address alone, for a link whose page isn't loaded:
    /// `memory:places/lisbon-trip` reads "Lisbon trip".
    public var plainName: String {
        let last = rawValue.split(separator: "/").last ?? Substring(rawValue)
        let words = last.split(separator: ":").last.map(String.init) ?? String(last)
        let spaced = words.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
