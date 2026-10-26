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
    /// The addresses of related pages.
    public let links: [PageAddress]
    public let changedAt: Timestamp
    /// The page as Ari wrote it, in Markdown without its front matter: the present first, then
    /// *Earlier* with dates.
    public let markdown: String

    public var id: PageAddress { address }

    public init(
        address: PageAddress, title: String, shelf: String, aliases: [String] = [],
        links: [PageAddress] = [], changedAt: Timestamp, markdown: String
    ) {
        self.address = address
        self.title = title
        self.shelf = shelf
        self.aliases = aliases
        self.links = links
        self.changedAt = changedAt
        self.markdown = markdown
    }

    enum CodingKeys: String, CodingKey {
        case address, title, shelf, aliases, links, markdown
        case changedAt = "changed_at"
    }
}

/// A page named without its words: a row in a list, or a page on a memory step, where
/// `changedAt` is absent.
public struct PageSummary: Sendable, Hashable, Identifiable, Codable {
    public let address: PageAddress
    public let title: String
    public let changedAt: Timestamp?

    public var id: PageAddress { address }

    public init(address: PageAddress, title: String, changedAt: Timestamp? = nil) {
        self.address = address
        self.title = title
        self.changedAt = changedAt
    }

    enum CodingKeys: String, CodingKey {
        case address, title
        case changedAt = "changed_at"
    }
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

/// `GET /v0/memory/pages?shelf=…` and `GET /v0/memory/recent`: pages, most recently changed first.
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
