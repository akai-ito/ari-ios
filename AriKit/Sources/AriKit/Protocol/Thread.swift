import Foundation

public struct ThreadID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Who started a thread.
public struct ThreadStarter: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let kumo = ThreadStarter(rawValue: "kumo")
    public static let you = ThreadStarter(rawValue: "you")
    public static let known = [kumo, you]
}

/// Whether a thread's question or task is still live. Ari treats a state it doesn't know as open.
public struct ThreadState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let open = ThreadState(rawValue: "open")
    public static let done = ThreadState(rawValue: "done")
    public static let known = [open, done]
}

/// A side thread: a subject of its own beside the main chat, with its own conversation, so talking
/// in it never steers the main chat or another thread aside. It shows in the main chat as one
/// quiet line.
public struct SideThread: Hashable, Sendable, Identifiable, Codable {
    public var id: ThreadID
    /// One to five plain words, such as "Kiln menu". Absent until Kumo names a thread you started.
    public var title: String?
    public var by: ThreadStarter
    public var state: ThreadState
    public var startedAt: Timestamp
    /// Where its line sits in the main chat: just after the main chat's message with the greatest
    /// position below it, or under ``anchor`` while it hasn't moved.
    public var position: Int
    /// The main chat's message it hangs from, when you started it by replying there.
    public var anchor: MessageID?
    /// How many messages it holds, yours and Kumo's.
    public var replies: Int
    public var lastAt: Timestamp
    /// Kumo's one line on where it stands, such as "Noodles, laab, skewers · £47 for two".
    public var result: String?
    /// What Kumo said there that you haven't seen yet.
    public var news: News?
    /// Who marked it done, and when, while it's done.
    public var done: Done?
    /// Its first picture, for a thumbnail.
    public var picture: AttachmentID?
    /// Whether it holds a page Kumo made.
    public var page: Bool?

    public struct News: Hashable, Sendable, Codable {
        public var message: MessageID
        public var text: String
        public var at: Timestamp
    }

    public struct Done: Hashable, Sendable, Codable {
        public var at: Timestamp
        public var by: ThreadStarter
    }

    public init(
        id: ThreadID, title: String? = nil, by: ThreadStarter = .kumo, state: ThreadState = .open,
        startedAt: Timestamp, position: Int, anchor: MessageID? = nil, replies: Int = 0,
        lastAt: Timestamp? = nil, result: String? = nil, news: News? = nil, done: Done? = nil,
        picture: AttachmentID? = nil, page: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.by = by
        self.state = state
        self.startedAt = startedAt
        self.position = position
        self.anchor = anchor
        self.replies = replies
        self.lastAt = lastAt ?? startedAt
        self.result = result
        self.news = news
        self.done = done
        self.picture = picture
        self.page = page
    }

    /// Open unless it's done: a state this Ari doesn't know still keeps its open marker.
    public var isOpen: Bool { state != .done }

    enum CodingKeys: String, CodingKey {
        case id, title, by, state, position, anchor, replies, result, news, done, picture, page
        case startedAt = "started_at"
        case lastAt = "last_at"
    }
}

/// Inside a thread, the message you replied to, and a line of it to show above yours.
public struct Quote: Hashable, Sendable, Codable {
    public var message: MessageID
    public var text: String

    public init(message: MessageID, text: String) {
        self.message = message
        self.text = text
    }
}

/// `thread.started` and `thread.changed`: the thread as it is now.
public struct ThreadEvent: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let thread: SideThread
}

/// `message.moved`: a message moved between the main chat and a thread, keeping its id and
/// position; the whole message as it is now.
public struct MessageMoved: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: Message
    /// The thread it left; absent when it left the main chat.
    public let from: ThreadID?
}

/// `GET /v0/threads/{thread}`: a thread with its latest messages, as a snapshot is for the main chat.
public struct ThreadPage: Sendable, Equatable, Decodable {
    public let thread: SideThread
    /// The main chat's message it hangs from, to show at its top.
    public let anchor: Message?
    public let messages: [Message]
    public let steps: [Step]
    public let asks: [Ask]
    public let turn: LiveTurn?
    public let next: [MessageID]
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case thread, anchor, messages, steps, asks, turn, next
        case hasMore = "has_more"
    }
}

/// `GET /v0/threads`: every open thread, then done ones newest first, a page at a time.
public struct ThreadList: Sendable, Equatable, Decodable {
    public let open: [SideThread]
    public let threads: [SideThread]
    public let hasMore: Bool

    public init(open: [SideThread], threads: [SideThread], hasMore: Bool) {
        self.open = open
        self.threads = threads
        self.hasMore = hasMore
    }

    enum CodingKeys: String, CodingKey {
        case open, threads
        case hasMore = "has_more"
    }
}

/// The answer to renaming a thread, marking it done or open, or seeing it.
public struct ThreadResult: Sendable, Equatable, Decodable {
    public let thread: SideThread
}

/// `PATCH /v0/threads/{thread}`: a new name, or done or open.
public struct ThreadChange: Sendable, Equatable, Codable {
    public let title: String?
    public let state: ThreadState?

    public init(title: String? = nil, state: ThreadState? = nil) {
        self.title = title
        self.state = state
    }
}

/// `POST /v0/messages/{message}/move`: the thread to move it into, or none for the main chat.
public struct MoveMessage: Sendable, Equatable, Codable {
    public let thread: ThreadID?

    public init(thread: ThreadID?) { self.thread = thread }
}
