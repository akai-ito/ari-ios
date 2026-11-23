import Foundation

// Kumo's hands: the browser on the server that Kumo uses for you, at iPhone size. Its state comes
// with the snapshot and `browser.changed`; its live view, and your hand on it, on the browser's
// stream (see `BrowserStream`).

/// What Kumo's browser is doing. A state Ari doesn't know counts as `idle`.
public struct BrowserState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let idle = BrowserState(rawValue: "idle")
    /// Kumo at work on a site.
    public static let browsing = BrowserState(rawValue: "browsing")
    /// Kumo asked you to take over: a login, a code, a CAPTCHA or the pay button.
    public static let needsYou = BrowserState(rawValue: "needs_you")
    /// You hold the page in a takeover; Kumo can't touch it.
    public static let yours = BrowserState(rawValue: "yours")
    /// A commit card waits for your tap.
    public static let waiting = BrowserState(rawValue: "waiting")
    public static let known = [idle, browsing, needsYou, yours, waiting]

    /// The state as Ari draws it: one it doesn't know is idle.
    public var shown: BrowserState { isKnown ? self : .idle }
}

/// What Kumo needs your hand for. A kind Ari doesn't know counts as `other`.
public struct BrowserNeedKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// To sign in.
    public static let login = BrowserNeedKind(rawValue: "login")
    /// A two-factor code.
    public static let code = BrowserNeedKind(rawValue: "code")
    public static let captcha = BrowserNeedKind(rawValue: "captcha")
    /// To press the site's own pay button yourself.
    public static let payment = BrowserNeedKind(rawValue: "payment")
    public static let other = BrowserNeedKind(rawValue: "other")
    public static let known = [login, code, captcha, payment, other]

    public var shown: BrowserNeedKind { isKnown ? self : .other }
}

/// Kumo's browser on the server, while it's doing something. A browsing task lives in the thread it
/// started in, where its line shows.
public struct Browser: Sendable, Equatable, Decodable {
    public var state: BrowserState
    /// The task's line, in the server's words, such as "On OpenTable: choosing Sat 19:30 · step 6".
    public var line: String?
    /// The side thread the task lives in; absent for the main chat.
    public var thread: ThreadID?
    /// The site, such as "OpenTable".
    public var site: String?
    /// The page's address, without its query.
    public var url: String?
    public var title: String?
    /// `browsing` only: what Kumo is doing, such as "choosing Sat 19:30".
    public var doing: String?
    /// `browsing` only: how many steps Kumo has taken on this task.
    public var step: Int?
    /// What Kumo needs your hand for, while it waits on you or you hold the page because it asked.
    public var need: Need?
    /// `yours` only: until when you hold the page, unless you touch it again.
    public var lease: Lease?
    /// `waiting` only: the commit card on the Desk.
    public var card: CardID?

    public struct Need: Sendable, Equatable, Decodable {
        public var kind: BrowserNeedKind
        /// What to do, in Kumo's words, such as "Sign in to OpenTable so I can book Saturday".
        public var why: String
        public var turn: TurnID?

        public init(kind: BrowserNeedKind, why: String, turn: TurnID? = nil) {
            self.kind = kind
            self.why = why
            self.turn = turn
        }
    }

    public struct Lease: Sendable, Equatable, Decodable {
        public var until: Timestamp

        public init(until: Timestamp) { self.until = until }
    }

    public init(
        state: BrowserState, line: String? = nil, thread: ThreadID? = nil, site: String? = nil,
        url: String? = nil, title: String? = nil, doing: String? = nil, step: Int? = nil,
        need: Need? = nil, lease: Lease? = nil, card: CardID? = nil
    ) {
        self.state = state
        self.line = line
        self.thread = thread
        self.site = site
        self.url = url
        self.title = title
        self.doing = doing
        self.step = step
        self.need = need
        self.lease = lease
        self.card = card
    }

    public static let idle = Browser(state: .idle)

    /// Whether there's a task to show: anything but idle.
    public var isActive: Bool { state.shown != .idle }

    /// The site's host, for the takeover's header: "railway-tickets.co.uk".
    public var host: String? {
        guard let url, let host = URL(string: url)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// `browser.changed`: the whole state, after a step, a takeover, a hand back, a commit card, or the
/// task's end.
public struct BrowserChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let browser: Browser
}

/// The answer to `GET /v0/capabilities/browser/state`, a takeover and a hand back.
public struct BrowserBody: Sendable, Equatable, Decodable {
    public let browser: Browser
}

/// A free booking or form Kumo has ready on a site, for your one tap. The option that `acts` has the
/// box press the site's own button, but only if the page is still as it was. Money never goes this
/// way.
public struct CommitCard: Sendable, Equatable, Decodable {
    /// The site, such as "Tablewise".
    public let site: String
    /// The page's address, without its query.
    public let url: String
    /// The site's button a go-ahead presses, as it reads, such as "Book now".
    public let button: String
    /// What pressing it does, in Kumo's words.
    public let summary: String
    /// What matters, such as when, for how many, the name it's under.
    public let details: [Detail]?
    /// The page as Kumo left it, at iPhone size, with the button outlined.
    public let screenshot: AttachmentID
    /// The side thread the task lives in; absent for the main chat.
    public let thread: ThreadID?

    public struct Detail: Sendable, Equatable, Decodable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public init(
        site: String, url: String, button: String, summary: String, details: [Detail]? = nil,
        screenshot: AttachmentID, thread: ThreadID? = nil
    ) {
        self.site = site
        self.url = url
        self.button = button
        self.summary = summary
        self.details = details
        self.screenshot = screenshot
        self.thread = thread
    }
}
