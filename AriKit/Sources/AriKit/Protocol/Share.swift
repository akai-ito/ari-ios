import Foundation

// The share inbox: what the phone's share sheet sends with `POST /v0/shares`. Kumo puts each share
// in the side thread it belongs in, or a new one it names, where it becomes your message, with
// `share` holding the link and text, and answers it there.

/// On a message you shared from the share sheet: what you shared besides your note, which is the
/// message's text, and its photos and files, which are its attachments. Empty for a photo or file
/// shared with nothing else.
public struct Shared: Sendable, Hashable, Codable {
    public var link: SharedLink?
    /// Text you shared from another app, such as a passage you selected, exactly as it came.
    public var text: String?

    public init(link: SharedLink? = nil, text: String? = nil) {
        self.link = link
        self.text = text
    }
}

/// A link you shared, with what the server read from the page where it could. The app draws it as
/// a card from these alone and never goes to the site.
public struct SharedLink: Sendable, Hashable, Codable {
    /// The link, exactly as you shared it.
    public var url: String
    /// The page's title.
    public var title: String?
    /// The page's summary of itself, as it gives one to link previews.
    public var description: String?
    /// The site's name, such as "Halcyon Careers", or else its host.
    public var site: String?

    public init(url: String, title: String? = nil, description: String? = nil, site: String? = nil)
    {
        self.url = url
        self.title = title
        self.description = description
        self.site = site
    }

    /// Where it goes, when the link reads as one.
    public var address: URL? { URL(string: url) }

    /// The host without `www.`, such as `fernway.example`, or the link itself.
    public var host: String {
        guard let host = address?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// `POST /v0/shares`: any mix of a link, text from another app, photos and files (uploaded first),
/// and your note. The id is made once per share and kept for every retry.
public struct SendShare: Sendable, Equatable, Codable {
    /// A random UUID: the share's retry key, and the id of the message it becomes.
    public let id: MessageID
    /// The link you shared, `http` or `https`.
    public let url: String?
    /// Text you shared from another app.
    public let text: String?
    /// What you wrote in the share sheet. A quick thought can be a note alone.
    public let note: String?
    /// The photos and files you shared, uploaded first, in order.
    public let attachments: [AttachmentID]?

    public init(
        id: MessageID, url: String? = nil, text: String? = nil, note: String? = nil,
        attachments: [AttachmentID] = []
    ) {
        self.id = id
        self.url = url
        self.text = Self.words(text)
        self.note = Self.words(note)
        self.attachments = attachments.isEmpty ? nil : attachments
    }

    /// Whether there's anything to send: the server needs at least one of the four.
    public var isEmpty: Bool { url == nil && text == nil && note == nil && attachments == nil }

    /// Words with something in them, or nothing: the server refuses blank text.
    private static func words(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}

/// A share and where it stands: `sorting` while Kumo decides which thread it belongs in, `placed`
/// once it's your message in that thread.
public struct ShareStatus: Sendable, Equatable, Decodable {
    /// The share's id, which its message takes once it's placed.
    public let id: MessageID
    public let state: ShareState
    /// When the server accepted it.
    public let at: Timestamp
    /// Once it's placed, the thread it's in.
    public let thread: ThreadID?
}

/// Where a share stands. A state Ari doesn't know reads as still sorting.
public struct ShareState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let sorting = ShareState(rawValue: "sorting")
    public static let placed = ShareState(rawValue: "placed")
    public static let known = [sorting, placed]
}

/// The answer to `POST /v0/shares`.
struct ShareResult: Decodable {
    let share: ShareStatus
}
