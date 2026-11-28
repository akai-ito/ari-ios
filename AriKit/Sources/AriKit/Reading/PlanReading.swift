import Foundation

/// Kumo's plans, as the Plans page groups them: one-offs by when they're due (today, tomorrow, later
/// this week, then later still), and each repeat once under Repeating, with tonight's time also
/// under Today.
public struct PlanGroups: Equatable, Sendable {
    public var today: [WakeUp] = []
    public var tomorrow: [WakeUp] = []
    public var laterThisWeek: [WakeUp] = []
    public var later: [WakeUp] = []
    public var repeating: [WakeUp] = []

    public init() {}

    /// How many plans the Plans page has beyond today's: the rest of the one-offs and the repeats
    /// that aren't due today.
    public var beyondToday: Int {
        tomorrow.count + laterThisWeek.count + later.count
            + repeating.filter { plan in !today.contains { $0.id == plan.id } }.count
    }

    /// Whether everything beyond today falls in this week.
    public var allThisWeek: Bool { later.isEmpty }
}

public enum PlanReading {
    /// Groups plans by when they're next due on this phone's calendar, soonest first in each.
    public static func group(_ plans: [WakeUp], now: Date, calendar: Calendar = .current)
        -> PlanGroups
    {
        var groups = PlanGroups()
        let sorted = plans.sorted { $0.at.date < $1.at.date }
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let afterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now
        let endOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? afterTomorrow
        for plan in sorted {
            let at = plan.at.date
            if plan.repeat != nil {
                groups.repeating.append(plan)
                if at < tomorrow { groups.today.append(plan) }
                continue
            }
            if at < tomorrow {
                groups.today.append(plan)
            } else if at < afterTomorrow {
                groups.tomorrow.append(plan)
            } else if at < endOfWeek {
                groups.laterThisWeek.append(plan)
            } else {
                groups.later.append(plan)
            }
        }
        return groups
    }

    /// The next `count` times a plan comes due: its own next time, then, for a repeat, each day it
    /// comes back at its time, on this phone's calendar, as far as its end. A one-off has only its
    /// own.
    public static func nextTimes(of plan: WakeUp, count: Int = 4, calendar: Calendar = .current)
        -> [Date]
    {
        var times = [plan.at.date]
        guard let repeating = plan.repeat, !repeating.days.isEmpty else { return times }
        let count = min(count, max(1, repeating.left ?? count))
        let last = repeating.lastDay(in: calendar).flatMap {
            calendar.date(byAdding: .day, value: 1, to: $0)
        }
        var day = calendar.startOfDay(for: plan.at.date)
        // A fortnight is always enough to find the next of any day.
        var looked = 0
        while times.count < count, looked < 14 * count {
            looked += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            if let last, day >= last { break }
            guard repeating.days.contains(weekday(of: day, calendar: calendar)),
                let time = self.time(repeating.time, on: day, calendar: calendar),
                time > times[times.count - 1]
            else { continue }
            times.append(time)
        }
        return times
    }

    /// How a repeat ends, in short: "4 left", "1 left" or "until 22 Dec"; `nil` while it repeats
    /// until stopped.
    public static func end(of repeating: Repeat, calendar: Calendar = .current) -> String? {
        if let left = repeating.left { return "\(left) left" }
        guard let last = repeating.lastDay(in: calendar) else { return nil }
        let day = last.formatted(
            Date.FormatStyle(timeZone: calendar.timeZone).day().month(.abbreviated)
                .locale(calendar.locale ?? .current))
        return "until \(day)"
    }

    /// The protocol's day for a date: Monday first.
    static func weekday(of date: Date, calendar: Calendar) -> Weekday {
        // The calendar counts Sunday as 1; the protocol's days start on Monday.
        let index = (calendar.component(.weekday, from: date) + 5) % 7
        return Weekday.known[index]
    }

    /// `09:00` on a day, on this phone's calendar.
    static func time(_ time: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}
