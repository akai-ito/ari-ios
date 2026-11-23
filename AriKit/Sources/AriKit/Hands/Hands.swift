import Foundation

/// Where Kumo's hands reach the server: taking the page, handing it back, and the live view. The
/// app uses ``ItoClient``; tests and samples stand in for it.
public protocol HandsBackend: Sendable {
    func takeOver() async throws(RequestError) -> Browser
    func handBack() async throws(RequestError) -> Browser
    func openStream() -> any WebSocketChannel
}

extension ItoClient: HandsBackend {
    public func takeOver() async throws(RequestError) -> Browser { try await takeOverBrowser() }
    public func handBack() async throws(RequestError) -> Browser { try await handBackBrowser() }
    public func openStream() -> any WebSocketChannel { browserStream() }
}

/// What a browsing task's line says, where the task lives: in its thread's trail, as one live step
/// whose words change in place, and in the main chat, in its thread line's detail.
public struct LiveLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Kumo at work: tap to watch.
        case browsing
        /// Kumo needs your hand: tap to take over.
        case needsYou
        /// You hold the page: tap to go back to it.
        case yours
        /// A card waits for your tap.
        case waiting
    }

    public let kind: Kind
    /// The trail's words: "On Tablewise · choosing Sat 19:30 · step 6".
    public let text: String
    /// The thread line's detail in the main chat: "On Tablewise · step 6".
    public let detail: String
    /// What a tap does, under the words: "Tap to watch".
    public let hint: String?

    /// Whether it shows a small live picture of the page.
    public var showsPicture: Bool { kind != .waiting }

    /// The line for `browser`; `nil` while it's idle. `resumed` once Kumo has the page back after
    /// you had it, so it reads "Back on it".
    public init?(_ browser: Browser, resumed: Bool = false) {
        let site = browser.site
        let step = browser.step.map { "step \($0)" }
        switch browser.state.shown {
        case .browsing:
            kind = .browsing
            let lead = resumed ? "Back on it" : site.map { "On \($0)" }
            if lead == nil, browser.doing == nil, let line = browser.line {
                text = line
            } else {
                text = [lead ?? "Browsing", browser.doing, step].compactMap(\.self)
                    .joined(separator: " · ")
            }
            detail = [lead ?? "Browsing", step].compactMap(\.self).joined(separator: " · ")
            hint = "Tap to watch"
        case .needsYou:
            kind = .needsYou
            text = browser.line ?? "Needs your hand" + (site.map { " on \($0)" } ?? "")
            detail = "Needs your hand" + (site.map { " on \($0)" } ?? "")
            hint = "Tap to take over"
        case .yours:
            kind = .yours
            text = "You have the page" + (site.map { " on \($0)" } ?? "")
            detail = "You have the page"
            hint = "Tap to go back to it"
        case .waiting:
            kind = .waiting
            text = browser.line ?? "Waiting for your OK" + (site.map { " on \($0)" } ?? "")
            detail = "Waiting for your OK"
            hint = nil
        default:
            return nil
        }
    }
}

/// A time Kumo needed your hand and got the page back, for the trail: "Needed you to log in", then
/// "You logged in and handed back · 17:21".
public struct Handoff: Sendable, Equatable, Identifiable {
    public let id: Int
    /// The thread the task lives in; `nil` for the main chat.
    public let thread: ThreadID?
    /// What Kumo asked your hand for, if it asked.
    public let need: BrowserNeedKind?
    /// Whether you handed it back, rather than it going back by itself.
    public let handedBack: Bool
    public let at: Date

    public init(id: Int, thread: ThreadID?, need: BrowserNeedKind?, handedBack: Bool, at: Date) {
        self.id = id
        self.thread = thread
        self.need = need
        self.handedBack = handedBack
        self.at = at
    }

    /// The step's words: what Kumo needed.
    public var asked: String {
        switch need?.shown {
        case .login: "Needed you to log in"
        case .code: "Needed a code from you"
        case .captcha: "Needed you past a check"
        case .payment: "Needed you to press Pay"
        case .other: "Needed your hand"
        default: "You took over"
        }
    }

    /// Under it: how the page came back.
    public var answered: String {
        guard handedBack else { return "The page went back to \(LeadName.current)" }
        return switch need?.shown {
        case .login: "You logged in and handed back"
        case .code: "You put the code in and handed back"
        case .captcha: "You got past it and handed back"
        default: "You had the page and handed back"
        }
    }
}

/// Where a one-tap card stands for you.
public enum CommitState: Sendable, Equatable {
    /// Waiting for your tap.
    case ready
    /// Your tap is on its way, or the box is pressing the site's button.
    case booking
    /// You tapped it and it's off the Desk. The server doesn't say yet how pressing went, so Ari
    /// says only what you did.
    case pressed(at: Date)
    /// Booked, with the site's reference when it gave one. Needs the server to say.
    case done(reference: String?, at: Date)
    /// The page had changed, so nothing was pressed and Kumo looks again. Needs the server to say.
    case changed
}

/// Kumo's hands, as Ari follows them: what the browser is doing, its line where its task lives, the
/// times it needed you, the live view while something shows it, and a takeover while you hold the
/// page. The session feeds it the browser's state.
@MainActor
@Observable
public final class Hands {
    /// What Kumo's browser is doing, as the server last said.
    public private(set) var browser = Browser.idle
    /// Whether Kumo has the page back after you had it, for "Back on it".
    public private(set) var resumed = false
    /// The times Kumo needed your hand and got the page back, oldest first. Kept while Ari runs:
    /// the server's trail doesn't hold them yet.
    public private(set) var handoffs: [Handoff] = []
    /// The takeover, while you hold the page or are asking for it.
    public private(set) var takeover: Takeover?
    /// Whether the takeover's screen is up. Leaving it with you hides it and keeps the page.
    public private(set) var showsTakeover = false
    /// The live view, while anything on screen watches it.
    public private(set) var stream: BrowserStream?
    /// Commit cards as last seen on the Desk, so one that settled still draws.
    public private(set) var commits: [CardID: DeskCard] = [:]
    /// The commit cards you tapped Book on, and when.
    public private(set) var pressed: [CardID: Date] = [:]

    @ObservationIgnored private let backend: any HandsBackend
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var closing: Task<Void, Never>?
    @ObservationIgnored private var lastNeed: Browser.Need?
    @ObservationIgnored private var listening: Int?
    @ObservationIgnored private var nextHandoff = 0
    @ObservationIgnored private let makeStream: (any HandsBackend) -> BrowserStream

    public init(
        backend: any HandsBackend, now: @escaping @Sendable () -> Date = { Date() },
        makeStream: ((any HandsBackend) -> BrowserStream)? = nil
    ) {
        self.backend = backend
        self.now = now
        self.makeStream =
            makeStream ?? { backend in BrowserStream(connect: { backend.openStream() }) }
    }

    // MARK: - Following

    /// The browser's state, from the snapshot or `browser.changed`.
    public func follow(_ next: Browser) {
        let before = browser.state.shown
        let after = next.state.shown
        if let need = next.need { lastNeed = need }
        if before == .yours, after != .yours {
            // Handed back, here or from another device, or gone back by itself.
            let byYou = takeover?.phase == .handingBack || takeover?.phase == .handedBack
            record(
                Handoff(
                    id: nextHandoff, thread: browser.thread ?? next.thread,
                    need: lastNeed?.kind, handedBack: byYou, at: now()))
            resumed = after == .browsing
            lastNeed = nil
        } else if after == .idle || after == .needsYou {
            resumed = false
        }
        if after == .idle { lastNeed = nil }
        browser = next
        takeover?.observed(next)
    }

    /// Commit cards on the Desk, as it changes, so one still draws once it's settled.
    public func follow(desk: Desk?) {
        for card in desk?.waiting ?? [] where card.kind == .commit { commits[card.id] = card }
    }

    /// The task's line where `place` is: a thread, or the main chat with `nil`.
    public func line(in place: ThreadID?) -> LiveLine? {
        guard browser.isActive, browser.thread == place else { return nil }
        return LiveLine(browser, resumed: resumed)
    }

    /// The times Kumo needed your hand in `place`.
    public func handoffs(in place: ThreadID?) -> [Handoff] {
        handoffs.filter { $0.thread == place }
    }

    private func record(_ handoff: Handoff) {
        handoffs.append(handoff)
        nextHandoff += 1
    }

    // MARK: - The live view

    /// Something on screen shows the page: the live view opens, shared by all that show it.
    @discardableResult
    public func watch() -> BrowserStream {
        watchers += 1
        closing?.cancel()
        closing = nil
        if let stream { return stream }
        let stream = makeStream(backend)
        listening = stream.listen { [weak self] event in
            guard let self, case .state(let browser) = event else { return }
            self.takeover?.observed(browser)
        }
        stream.start()
        self.stream = stream
        return stream
    }

    /// It's gone from the screen; the live view closes a moment after the last one goes, so
    /// moving from the peek to the takeover keeps the picture.
    public func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        closing?.cancel()
        closing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.watchers == 0 else { return }
            self.stream?.close()
            self.stream = nil
        }
    }

    // MARK: - Taking over

    /// You take the page: the takeover's screen comes up, and the server is asked. Coming back to
    /// a page you already hold shows it again.
    public func takeOver() async {
        showsTakeover = true
        if let takeover, !takeover.isOver {
            // Taking it again moves the lease on.
            if takeover.phase == .holding { _ = try? await backend.takeOver() }
            return
        }
        var takeover = takeover ?? Takeover(need: browser.need, thread: browser.thread)
        if takeover.isOver { _ = takeover.retake() }
        self.takeover = takeover
        do {
            let browser = try await backend.takeOver()
            self.takeover?.took(browser)
            follow(browser)
        } catch {
            self.takeover?.couldNotTake(Self.words(error))
        }
    }

    /// Hand back to Kumo: it reads the page again, then carries on.
    public func handBack() async {
        guard takeover?.handBack() == true else {
            if takeover?.isOver == true { close() }
            return
        }
        do {
            let browser = try await backend.handBack()
            takeover?.handedBack()
            follow(browser)
            close()
        } catch {
            takeover?.couldNotHandBack(Self.words(error))
        }
    }

    /// Leave it with you for now: the screen goes, the page stays yours until you come back or it
    /// goes back to Kumo by itself.
    public func leave() {
        showsTakeover = false
        if takeover?.isOver == true { takeover = nil }
    }

    /// Closes the screen once the takeover is over.
    public func close() {
        showsTakeover = false
        takeover = nil
    }

    /// What you did to the page; it goes only while you hold it.
    public func send(_ input: BrowserInput) {
        guard takeover?.acceptsInput == true else { return }
        stream?.send(input)
    }

    private static func words(_ error: RequestError) -> String {
        switch error {
        case .network: "No connection to your server."
        case .refused(_, let error?, _): error.message
        case .refused(503, nil, _): "\(LeadName.current)'s browser isn't on."
        case .refused(let status, nil, _): "Your server answered \(status)."
        case .protocolMismatch: "Your server speaks a different version of Ito."
        case .unreadable: "Your server's answer couldn't be read."
        }
    }

    // MARK: - One-tap cards

    /// You tapped the option that acts on a commit card.
    public func pressing(_ card: DeskCard) {
        commits[card.id] = card
        pressed[card.id] = now()
    }

    /// Where a commit card stands: from the Desk while it waits, then from what you did.
    public func state(of id: CardID, on desk: Desk?) -> CommitState? {
        if let card = desk?.waiting.first(where: { $0.id == id }) {
            return card.state == .working || card.answer != nil ? .booking : .ready
        }
        if let at = pressed[id] { return .pressed(at: at) }
        return nil
    }
}
