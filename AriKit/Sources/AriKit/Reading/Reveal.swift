import Foundation

/// How much of each reply is on screen. Text is revealed at a steady reading pace, catching up when
/// the screen falls behind what has arrived, so it's never more than a second or two back. A reply
/// starts once the one before it is fully shown. A reply that was already finished, long enough
/// ago, when Ari first saw it (history, a snapshot, one finished while Ari was away) shows at once.
///
/// It counts UTF-16 units of the reply's source, the unit of Stop's cut, and is a plain value the
/// screen moves on with each frame.
public struct Reveal: Sendable, Equatable {
    /// The steady reading pace, in units a second.
    public static let pace = 60.0
    /// When behind, the reveal speeds up to finish what has arrived within this many seconds.
    public static let catchUp = 1.5
    /// A reply that ended at most this many seconds before Ari first saw it is still revealed,
    /// quickly, rather than appearing all at once.
    static let recent: TimeInterval = 10

    private var shown: [MessageID: Double] = [:]

    public init() {}

    /// Whether the reveal paces this entry: the agent's replies. Your messages show at once, and
    /// notes belong to the status line.
    public static func paces(_ entry: Conversation.Entry) -> Bool {
        entry.role == .agent && entry.kind == .reply
    }

    /// How much of `entry` is on screen, in source units: fractional, so the leading edge can fade
    /// in, and infinite for an entry shown in full.
    public func position(of entry: Conversation.Entry, at now: Date = .now) -> Double {
        guard Self.paces(entry) else { return .infinity }
        if let shown = shown[entry.id] { return shown }
        return Self.showsAtOnce(entry, at: now) ? .infinity : 0
    }

    /// Whether anything is still being revealed.
    public func isRevealing(_ conversation: Conversation, at now: Date = .now) -> Bool {
        conversation.entries.contains { entry in
            Self.paces(entry)
                && position(of: entry, at: now)
                    < Double(conversation.visibleText(of: entry).utf16.count)
        }
    }

    /// Moves the reveal on by `elapsed` seconds. Returns whether anything is still being revealed.
    @discardableResult
    public mutating func advance(
        by elapsed: TimeInterval, in conversation: Conversation, at now: Date = .now
    ) -> Bool {
        var pending: [(id: MessageID, available: Double, current: Double)] = []
        for entry in conversation.entries where Self.paces(entry) {
            let current = position(of: entry, at: now)
            shown[entry.id] = current
            let available = Double(conversation.visibleText(of: entry).utf16.count)
            if current < available { pending.append((entry.id, available, current)) }
        }
        let backlog = pending.reduce(0) { $0 + $1.available - $1.current }
        let speed = max(Self.pace, backlog / Self.catchUp)
        var budget = speed * elapsed
        for item in pending {
            let step = min(item.available - item.current, budget)
            shown[item.id] = item.current + step
            budget -= step
            if budget <= 0 { break }
        }
        return backlog > speed * elapsed
    }

    /// You tapped Stop. Returns the cut: the message the server is still writing, at how much of
    /// it is on screen (nothing yet, if it's still waiting its turn behind another), or `nil` if
    /// nothing is being written. Everything else in the turn shows in full at once, since an ended
    /// message is final. If the turn has already ended, the rest of it simply shows.
    public mutating func stop(in conversation: Conversation) -> Cut? {
        guard let turn = conversation.turn else {
            showAll(conversation)
            return nil
        }
        let messages = conversation.entries.filter { $0.turn == turn.id && $0.role == .agent }
        let open = messages.last { $0.outcome == nil }
        for entry in messages where entry.id != open?.id { shown[entry.id] = .infinity }
        guard let open else { return nil }
        let text = conversation.visibleText(of: open)
        let seen =
            Self.paces(open)
            ? Int(min(shown[open.id] ?? 0, Double(text.utf16.count)).rounded(.down))
            : text.utf16.count
        return Cut(message: open.id, revealed: text.prefix(utf16: seen))
    }

    /// Shows every reply in full at once.
    public mutating func showAll(_ conversation: Conversation) {
        for entry in conversation.entries where Self.paces(entry) { shown[entry.id] = .infinity }
    }

    private static func showsAtOnce(_ entry: Conversation.Entry, at now: Date) -> Bool {
        guard entry.outcome != nil else { return false }
        guard let ended = (entry.endedAt ?? entry.at)?.date else { return true }
        return now.timeIntervalSince(ended) > recent
    }
}
