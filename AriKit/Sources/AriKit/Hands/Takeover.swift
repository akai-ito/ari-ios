import Foundation

/// A takeover, from asking for the page to handing it back. Only while you hold it does what you do
/// reach the page; the server's state has the last word on whether you do, since the page goes back
/// to Kumo by itself when its lease runs out.
public struct Takeover: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Asked the server for the page; a step Kumo is in the middle of finishes first.
        case taking
        /// The page is yours: touches, keys and text reach it.
        case holding
        case handingBack
        /// Back with Kumo, who reads the page again before it acts.
        case handedBack
        /// The page went back to Kumo without you handing it back, such as when you left it alone
        /// too long, or the task ended.
        case lost(String)
        /// The server wouldn't give you the page.
        case failed(String)
    }

    public private(set) var phase = Phase.taking
    /// What Kumo asked your hand for, when it did.
    public private(set) var need: Browser.Need?
    /// The thread the task lives in.
    public private(set) var thread: ThreadID?
    /// Hand back didn't go through, with why; you still hold the page.
    public private(set) var problem: String?

    public init(need: Browser.Need? = nil, thread: ThreadID? = nil) {
        self.need = need
        self.thread = thread
    }

    /// Whether what you do reaches the page.
    public var acceptsInput: Bool { phase == .holding }

    /// Whether the takeover is over, one way or another.
    public var isOver: Bool {
        switch phase {
        case .handedBack, .lost, .failed: true
        default: false
        }
    }

    /// Asks again after it failed or was lost; returns whether to ask the server.
    public mutating func retake() -> Bool {
        switch phase {
        case .failed, .lost, .handedBack:
            phase = .taking
            problem = nil
            return true
        default:
            return false
        }
    }

    /// The server's answer to taking over.
    public mutating func took(_ browser: Browser) {
        guard phase == .taking else { return }
        if browser.state.shown == .yours {
            phase = .holding
            keep(browser)
        } else {
            phase = .failed("\(LeadName.current) still has the page. Try again in a moment.")
        }
    }

    public mutating func couldNotTake(_ message: String) {
        guard phase == .taking else { return }
        phase = .failed(message)
    }

    /// The browser's state, from the event stream or the browser's own stream.
    public mutating func observed(_ browser: Browser) {
        switch (phase, browser.state.shown) {
        case (.taking, .yours), (.holding, .yours):
            phase = .holding
            keep(browser)
        case (.holding, .idle):
            phase = .lost("The task is over.")
        case (.holding, _):
            phase = .lost("The page went back to \(LeadName.current).")
        default:
            break
        }
    }

    /// You handed it back; returns whether to tell the server.
    public mutating func handBack() -> Bool {
        guard phase == .holding else { return false }
        phase = .handingBack
        problem = nil
        return true
    }

    public mutating func handedBack() {
        guard phase == .handingBack else { return }
        phase = .handedBack
    }

    /// Hand back didn't reach the server: you still hold the page.
    public mutating func couldNotHandBack(_ message: String) {
        guard phase == .handingBack else { return }
        phase = .holding
        problem = message
    }

    /// Stop the task didn't reach the server: you still hold the page.
    public mutating func couldNotStop(_ message: String) {
        problem = message
    }

    private mutating func keep(_ browser: Browser) {
        if let need = browser.need { self.need = need }
        if let thread = browser.thread { self.thread = thread }
    }
}
