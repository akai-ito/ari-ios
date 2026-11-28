import Foundation

// The browser's stream (`GET /v0/capabilities/browser/stream`): the live page down as JPEG frames,
// with its state, view and focus as JSON; your touches, scrolls and typing up as JSON, which reach
// the page only while you hold it in a takeover.

/// What you do to the page, as the stream carries it up. Coordinates are CSS pixels in the
/// viewport, from its top left.
public enum BrowserInput: Sendable, Equatable {
    /// A tap at one point, as a finger: touch start and end there.
    case tap(x: Double, y: Double)
    /// One finger, phase by phase, for a drag, a long press or a slider.
    case touch(TouchPhase, x: Double, y: Double)
    /// Scrolls whatever is under the point, positive down and right.
    case scroll(x: Double, y: Double, dx: Double, dy: Double)
    /// Typed or pasted text, put in where the focus is. The server keeps none of it.
    case text(String)
    /// The whole value of the field with the focus, replacing what was there, as the native field
    /// laid over it holds it; empty clears it.
    case fill(String)
    /// A key that isn't text.
    case key(BrowserKey)
    case navigate(Navigation)
    /// The room the page has on screen, between the takeover's header and its bar, and how much of
    /// it the keyboard covers from the bottom while it's up. The server makes the page's viewport
    /// the room above the keyboard and answers with the view at that size.
    case viewport(width: Double, height: Double, keyboard: Double)

    public enum TouchPhase: String, Sendable, Equatable {
        case start, move, end, cancel
    }

    public enum Navigation: Sendable, Equatable {
        case url(String)
        case back, forward, reload
    }

    /// The text frame to send.
    public var json: Data {
        var frame: [String: Any]
        switch self {
        case .tap(let x, let y): frame = ["type": "tap", "x": Self.css(x), "y": Self.css(y)]
        case .touch(let phase, let x, let y):
            frame = ["type": "touch", "phase": phase.rawValue, "x": Self.css(x), "y": Self.css(y)]
        case .scroll(let x, let y, let dx, let dy):
            frame = [
                "type": "scroll", "x": Self.css(x), "y": Self.css(y), "dx": Self.round(dx),
                "dy": Self.round(dy),
            ]
        case .text(let text): frame = ["type": "text", "text": text]
        case .fill(let text): frame = ["type": "fill", "text": text]
        case .key(let key): frame = ["type": "key", "key": key.rawValue]
        case .navigate(.url(let url)): frame = ["type": "navigate", "url": url]
        case .navigate(.back): frame = ["type": "navigate", "action": "back"]
        case .navigate(.forward): frame = ["type": "navigate", "action": "forward"]
        case .navigate(.reload): frame = ["type": "navigate", "action": "reload"]
        case .viewport(let width, let height, let keyboard):
            frame = ["type": "viewport", "width": Self.round(width), "height": Self.round(height)]
            if keyboard > 0 { frame["keyboard"] = Self.round(keyboard) }
        }
        return (try? JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys]))
            ?? Data()
    }

    /// Points never go below zero, and a tenth of a pixel is plenty.
    private static func css(_ value: Double) -> Double { round(max(0, value)) }
    private static func round(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// This and the next as one, when one waiting to go up can take the next in: a finger's moves
    /// keep only the latest place, scrolls add up, and the room keeps the latest size. `nil` when
    /// both must go.
    public func joined(with next: BrowserInput) -> BrowserInput? {
        switch (self, next) {
        case (.touch(.move, _, _), .touch(.move, _, _)): next
        case (.scroll(_, _, let dx, let dy), .scroll(let x, let y, let nextDx, let nextDy)):
            .scroll(x: x, y: y, dx: dx + nextDx, dy: dy + nextDy)
        case (.viewport, .viewport): next
        default: nil
        }
    }
}

/// What waits to go up the stream while the connection is busy sending: in order, with moves,
/// scrolls and sizes that come faster than it sends joined to the one before, so a slow connection
/// catches up at once rather than replaying every step, and a tap or a key is never held behind
/// them for long.
public struct InputOutbox: Sendable, Equatable {
    public private(set) var waiting: [BrowserInput] = []

    public init() {}

    public var isEmpty: Bool { waiting.isEmpty }

    public mutating func push(_ input: BrowserInput) {
        if let last = waiting.last, let joined = last.joined(with: input) {
            waiting[waiting.count - 1] = joined
        } else {
            waiting.append(input)
        }
    }

    /// The next to send, taken out.
    public mutating func next() -> BrowserInput? {
        waiting.isEmpty ? nil : waiting.removeFirst()
    }

    public mutating func clear() { waiting = [] }
}

/// The keys the phone's keyboard has that aren't text.
public enum BrowserKey: String, Sendable, Equatable {
    case backspace = "Backspace"
    case delete = "Delete"
    case enter = "Enter"
    case tab = "Tab"
    case escape = "Escape"
    case arrowUp = "ArrowUp"
    case arrowDown = "ArrowDown"
    case arrowLeft = "ArrowLeft"
    case arrowRight = "ArrowRight"
}

/// The page being shown: its address, and the viewport in CSS pixels, the size to map touches by.
public struct PageView: Sendable, Equatable {
    public var url: String
    public var width: Int
    public var height: Int
    /// Which tab, counting from 1, of how many.
    public var tab: Int
    public var tabs: Int
    /// How Chromium runs on the server: `headful`, or `headless` when no display could start.
    public var display: String?

    public init(
        url: String, width: Int, height: Int, tab: Int = 1, tabs: Int = 1, display: String? = nil
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.tab = tab
        self.tabs = tabs
        self.display = display
    }
}

/// The site's own button a payment waits on, for a ring around it: where it is on the page and
/// what it says, such as "Pay £58.40".
public struct PageMark: Sendable, Equatable {
    public var box: PageRect
    public var label: String

    public init(box: PageRect, label: String) {
        self.box = box
        self.label = label
    }
}

/// The kind of field with the focus. One Ari doesn't know types as plain text.
public struct FieldKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let text = FieldKind(rawValue: "text")
    public static let email = FieldKind(rawValue: "email")
    public static let number = FieldKind(rawValue: "number")
    public static let tel = FieldKind(rawValue: "tel")
    public static let url = FieldKind(rawValue: "url")
    public static let search = FieldKind(rawValue: "search")
    public static let password = FieldKind(rawValue: "password")
    /// A one-time code.
    public static let code = FieldKind(rawValue: "code")
    public static let known = [text, email, number, tel, url, search, password, code]

    public var shown: FieldKind { isKnown ? self : .text }
}

/// A rectangle in the viewport's CSS pixels.
public struct PageRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midY: Double { y + height / 2 }
}

/// The field with the focus in a takeover, so the phone shows the keyboard it wants.
public struct FocusedField: Sendable, Equatable {
    public var kind: FieldKind
    /// The field's label, which may be empty.
    public var label: String
    /// Where it is on the page.
    public var box: PageRect
    /// How many characters it already holds.
    public var length: Int

    public init(
        kind: FieldKind, label: String = "",
        box: PageRect = PageRect(x: 0, y: 0, width: 0, height: 0),
        length: Int = 0
    ) {
        self.kind = kind
        self.label = label
        self.box = box
        self.length = length
    }
}

/// What arrives on the browser's stream.
public enum BrowserStreamEvent: Sendable, Equatable {
    /// The page itself: one JPEG of the whole viewport. Draw the latest.
    case picture(Data)
    case state(Browser)
    case view(PageView)
    /// The field with the focus, or `nil` when nothing editable has it: hide the keyboard.
    case focus(FocusedField?)
    /// The pay button to ring, or `nil` for none.
    case mark(PageMark?)
    /// Whether the server can show the page: `false` while it's reconnecting, such as when the page
    /// is frozen or between documents.
    case live(Bool)
    /// Something you sent didn't reach the page, with why.
    case refused(String)
    /// The browser stopped, with why; the server closes the stream next.
    case ended(String)
    case unknown

    /// Reads a text frame.
    public init(json: Data) {
        guard let frame = try? JSONDecoder().decode(Frame.self, from: json) else {
            self = .unknown
            return
        }
        switch frame.type {
        case "state": self = frame.browser.map(Self.state) ?? .unknown
        case "view":
            guard let url = frame.url, let width = frame.width, let height = frame.height,
                width > 0, height > 0
            else {
                self = .unknown
                return
            }
            self = .view(
                PageView(
                    url: url, width: width, height: height, tab: frame.tab ?? 1,
                    tabs: frame.tabs ?? 1, display: frame.display))
        case "focus":
            self = .focus(
                frame.field.map {
                    FocusedField(
                        kind: $0.kind, label: $0.label ?? "",
                        box: PageRect(
                            x: $0.box?.x ?? 0, y: $0.box?.y ?? 0, width: $0.box?.width ?? 0,
                            height: $0.box?.height ?? 0), length: $0.length ?? 0)
                })
        case "mark":
            self = .mark(
                frame.mark.map {
                    PageMark(
                        box: PageRect(
                            x: $0.box.x, y: $0.box.y, width: $0.box.width, height: $0.box.height),
                        label: $0.label)
                })
        // One Ari doesn't know is live.
        case "link": self = .live(frame.state != "reconnecting")
        case "refused": self = .refused(frame.message ?? "That didn't reach the page.")
        case "ended": self = .ended(frame.reason ?? "The browser stopped.")
        default: self = .unknown
        }
    }

    private struct Frame: Decodable {
        let type: String
        let browser: Browser?
        let url: String?
        let width: Int?
        let height: Int?
        let tab: Int?
        let tabs: Int?
        let field: Field?
        let message: String?
        let reason: String?
        let display: String?
        let mark: Mark?
        let state: String?
    }

    private struct Mark: Decodable {
        let box: Box
        let label: String
    }

    private struct Field: Decodable {
        let kind: FieldKind
        let label: String?
        let box: Box?
        let length: Int?
    }

    private struct Box: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
}

/// The live view of Kumo's browser, while something on screen shows it: the latest picture of the
/// page, what page it is, and, in a takeover, the field with the focus. A dropped connection is
/// tried again for as long as the stream is open; the server sends only the latest picture, never
/// a backlog. Pings measure the connection, so a takeover can say when taps may lag.
@MainActor
@Observable
public final class BrowserStream {
    /// The latest picture of the page, as JPEG.
    public private(set) var picture: Data?
    /// Counts pictures, so a view can tell a new one from the same.
    public private(set) var pictures = 0
    public private(set) var view: PageView?
    /// The field with the focus, in a takeover.
    public private(set) var focus: FocusedField?
    /// The pay button to ring, on a payment.
    public private(set) var mark: PageMark?
    /// Whether the server can show the page; `false` while it's reconnecting.
    public private(set) var isPageLive = true
    /// The browser's state as the stream last said.
    public private(set) var browser: Browser?
    /// The last thing that didn't reach the page, and why.
    public private(set) var refusal: String?
    public private(set) var link: Link = .connecting
    /// Why the stream ended, once it has.
    public private(set) var endReason: String?

    public enum Link: Sendable, Equatable {
        case connecting
        case live
        /// Up, but slow: taps may lag.
        case slow
        /// Dropped, trying again.
        case down
    }

    /// Whether to say the connection is struggling.
    public var isDegraded: Bool { link == .slow || link == .down }

    /// Whether the picture isn't live: the connection dropped, or the server can't show the page,
    /// such as while it's frozen. Say so quietly over it, rather than leave it up as if it were
    /// live; both come back by themselves.
    public var isReconnecting: Bool { link == .down || !isPageLive }

    @ObservationIgnored private let connect: @Sendable () -> any WebSocketChannel
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var channel: (any WebSocketChannel)?
    /// Wakes the sender when something waits in the outbox.
    @ObservationIgnored private var outgoing: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var outbox = InputOutbox()
    @ObservationIgnored private var missedPings = 0
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var pinging: Task<Void, Never>?
    @ObservationIgnored private var closed = false
    /// Every event as it arrives, for whoever follows the stream besides the screen.
    @ObservationIgnored private var listeners: [Int: (BrowserStreamEvent) -> Void] = [:]
    @ObservationIgnored private var nextListener = 0

    /// A ping slower than this says taps may lag.
    public static let slowPing = Duration.milliseconds(600)
    /// After this many pings in a row go unanswered, the connection is dropped and made again.
    public static let missedPingsToReconnect = 2

    public init(
        connect: @escaping @Sendable () -> any WebSocketChannel,
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.connect = connect
        self.clock = clock
    }

    public func start() {
        guard running == nil, !closed else { return }
        running = Task { await run() }
        pinging = Task { await ping() }
    }

    /// Sends what you did to the page, never waiting: it goes at once, in order, and while the
    /// connection is still sending what came before, moves, scrolls and sizes join up rather than
    /// queue. Dropped while the connection is down: a tap that lands seconds late, on a page that
    /// moved, is worse than none.
    public func send(_ input: BrowserInput) {
        guard let outgoing else { return }
        outbox.push(input)
        outgoing.yield()
    }

    /// Calls `listener` with each event as it arrives; returns a token for ``stopListening(_:)``.
    @discardableResult
    public func listen(_ listener: @escaping (BrowserStreamEvent) -> Void) -> Int {
        nextListener += 1
        listeners[nextListener] = listener
        return nextListener
    }

    public func stopListening(_ token: Int) { listeners[token] = nil }

    public func close() {
        guard !closed else { return }
        closed = true
        channel?.close(code: WebSocketClosed.normal)
        running?.cancel()
        pinging?.cancel()
        channel = nil
        outgoing = nil
        listeners = [:]
    }

    /// Applies one event, as the connection delivers it; tests call it directly.
    func receive(_ event: BrowserStreamEvent) {
        switch event {
        case .picture(let data):
            picture = data
            pictures += 1
        case .state(let browser):
            self.browser = browser
            // Only while it's yours does the page take typing.
            if browser.state.shown != .yours {
                focus = nil
                mark = nil
            }
        case .view(let view):
            // Another page: what had the focus is gone.
            if view.url != self.view?.url { focus = nil }
            self.view = view
        case .focus(let field): focus = field
        case .mark(let given): mark = given
        case .live(let isLive): isPageLive = isLive
        case .refused(let message): refusal = message
        case .ended(let reason): endReason = reason
        case .unknown: break
        }
        for listener in listeners.values { listener(event) }
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled, !closed {
            let channel = connect()
            self.channel = channel
            outbox.clear()
            missedPings = 0
            let (wakes, outgoing) = AsyncStream<Void>.makeStream(
                bufferingPolicy: .bufferingNewest(1))
            self.outgoing = outgoing
            let sender = Task { [weak self] in
                for await _ in wakes {
                    while let input = self?.outbox.next() {
                        try? await channel.send(.text(input.json))
                    }
                }
            }
            defer {
                outgoing.finish()
                sender.cancel()
            }
            do {
                while true {
                    let message = try await channel.receive()
                    attempt = 0
                    if link != .slow { link = .live }
                    switch message {
                    case .binary(let data): receive(.picture(data))
                    case .text(let json):
                        let event = BrowserStreamEvent(json: json)
                        receive(event)
                        if case .ended = event { return finish() }
                    }
                }
            } catch let refused as WebSocketRefused {
                endReason = Self.reason(refused.status)
                return finish()
            } catch {
                self.channel = nil
                self.outgoing = nil
                if closed || Task.isCancelled { return }
                if (error as? WebSocketClosed)?.code == WebSocketClosed.normal { return finish() }
                link = .down
                attempt += 1
                try? await clock.sleep(for: .milliseconds(min(250 * attempt, 2_000)))
            }
        }
    }

    private func ping() async {
        while !Task.isCancelled, !closed {
            try? await clock.sleep(for: .seconds(2))
            guard let channel, link == .live || link == .slow else { continue }
            let started = ContinuousClock.now
            let answered = await withTaskGroup(of: Bool.self) { group in
                group.addTask { (try? await channel.ping()) != nil }
                group.addTask { [clock] in
                    try? await clock.sleep(for: .seconds(2))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            guard !closed, self.channel != nil else { continue }
            let took = started.duration(to: .now)
            link = answered && took < Self.slowPing ? .live : .slow
            // A connection that stopped answering for whole seconds, without saying it closed, is
            // made again.
            missedPings = answered || took < .seconds(2) ? 0 : missedPings + 1
            if missedPings >= Self.missedPingsToReconnect {
                missedPings = 0
                channel.close(code: Self.unanswered)
            }
        }
    }

    /// The close code for a connection given up on because it stopped answering.
    static let unanswered = 4001

    private func finish() {
        closed = true
        pinging?.cancel()
        channel = nil
        outgoing = nil
        if endReason == nil { endReason = "The browser stopped." }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 401: "Your server didn't accept Ari's token."
        case 503: "Kumo's browser isn't on, on your server."
        default: "Your server couldn't show the page."
        }
    }
}

extension ItoClient {
    /// `GET /v0/capabilities/browser/stream`, upgraded to a WebSocket.
    public func browserStream() -> URLSessionWebSocketChannel {
        var components = URLComponents(url: address.url, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/v0/capabilities/browser/stream"
        var request = URLRequest(url: components.url!)
        if let token {
            request.setValue("Bearer \(token.secret)", forHTTPHeaderField: "Authorization")
        }
        return URLSessionWebSocketChannel(request: request)
    }

    /// `GET /v0/capabilities/browser/state`: what Kumo's browser is doing.
    public func browser() async throws(RequestError) -> Browser {
        let body: BrowserBody = try await call(
            HTTPRequest(.get, "/v0/capabilities/browser/state"))
        return body.browser
    }

    /// `POST /v0/capabilities/browser/takeover`: you hold the page. Taking it again moves the
    /// lease on.
    public func takeOverBrowser() async throws(RequestError) -> Browser {
        let body: BrowserBody = try await call(
            HTTPRequest(.post, "/v0/capabilities/browser/takeover"))
        return body.browser
    }

    /// `DELETE /v0/capabilities/browser/takeover`: the page back to Kumo, who reads it again
    /// before it acts.
    public func handBackBrowser() async throws(RequestError) -> Browser {
        let body: BrowserBody = try await call(
            HTTPRequest(.delete, "/v0/capabilities/browser/takeover"))
        return body.browser
    }

    /// `DELETE /v0/capabilities/browser/task`: stops Kumo's browsing task. A takeover you hold
    /// ends without waking Kumo, and the page stays as it is, unpressed.
    public func stopBrowserTask() async throws(RequestError) -> Browser {
        let body: BrowserBody = try await call(
            HTTPRequest(.delete, "/v0/capabilities/browser/task"))
        return body.browser
    }
}
