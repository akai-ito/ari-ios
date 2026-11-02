import Foundation

/// Kumo's work before today, a day at a time, for Kumo's work as it scrolls back. Done finds the
/// next earlier day with anything on it, and `GET /v0/work?day=` reads that day whole, so a quiet
/// weekend costs nothing and every day shows complete. A page from Done with nothing on it ends the
/// history, whatever it says about more, so the bottom never waits on nothing.
public struct WorkHistory: Sendable, Equatable {
    /// The earlier days read so far, newest first, each with something on it.
    public private(set) var days: [KumoWork] = []
    /// Whether there's nothing earlier to read.
    public private(set) var isFinished = false
    /// The oldest entry seen, which Done is asked to go back from.
    private var oldest: DoneEntry?

    public init(days: [KumoWork] = [], isFinished: Bool = false) {
        self.days = days
        self.isFinished = isFinished
    }

    /// Reads the next earlier day with any work on it, after `today` and the days already read, or
    /// finds there's none.
    public mutating func readNext(
        after today: KumoWork, calendar: Calendar = .current,
        done: (_ before: DoneID?) async throws(RequestError) -> DonePage,
        work: (_ day: String) async throws(RequestError) -> KumoWork
    ) async throws(RequestError) {
        guard !isFinished else { return }
        let start = oldest ?? Self.oldest(in: today)
        let page = try await done(start?.id)
        guard let entry = page.entries.first, entry.id != start?.id else {
            isFinished = true
            return
        }
        // Never a day already read, even where this phone's days and the box's disagree.
        let latest = Self.day(before: days.last?.day ?? today.day, calendar: calendar)
        let day = min(Self.day(of: entry.at.date, calendar: calendar), latest)
        let read = try await work(day)
        if !read.handled.isEmpty || !read.cleared.isEmpty { days.append(read) }
        oldest = Self.oldest(in: read).map { $0.at.date < entry.at.date ? $0 : entry } ?? entry
        isFinished = !page.hasMore
    }

    /// The history with one entry as it is now, such as after an Undo or a "That was wrong".
    public func replacing(_ entry: DoneEntry) -> WorkHistory {
        var history = self
        history.days = days.map { $0.replacing(entry) }
        return history
    }

    /// The local day a moment falls on, such as `2026-11-05`.
    public static func day(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    /// The local day before another.
    static func day(before day: String, calendar: Calendar) -> String {
        let date = LocalTime(day)?.date(in: calendar) ?? calendar.startOfDay(for: .now)
        return Self.day(
            of: calendar.date(byAdding: .day, value: -1, to: date) ?? date, calendar: calendar)
    }

    private static func oldest(in work: KumoWork) -> DoneEntry? {
        (work.handled + work.cleared).min { $0.at.date < $1.at.date }
    }
}

extension KumoWork {
    /// The day's work with one entry as it is now, wherever it sits.
    public func replacing(_ entry: DoneEntry) -> KumoWork {
        let swap = { (entries: [DoneEntry]) in entries.map { $0.id == entry.id ? entry : $0 } }
        return KumoWork(day: day, handled: swap(handled), cleared: swap(cleared), trust: trust)
    }
}
