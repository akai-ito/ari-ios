import AriKit
import Foundation

/// One thing on a day, as the thread and the day view read it: your events, Kumo's planned blocks
/// and its guesses at your time, and the check-ins it has planned.
enum DayEntry: Identifiable, Equatable {
    /// An event on one of your calendars.
    case event(CalendarItem)
    /// One of Kumo's own blocks: its plan for some of your time, a hold, travel or prep.
    case block(CalendarItem)
    /// Kumo's guess at what you're doing then.
    case guess(CalendarItem)
    /// One of Kumo's plans that comes due that day.
    case checkIn(WakeUp)

    init(_ item: CalendarItem) {
        if item.guess != nil {
            self = .guess(item)
        } else if DayReading.isKumos(item) {
            self = .block(item)
        } else {
            self = .event(item)
        }
    }

    var id: String {
        switch self {
        case .event(let item), .block(let item), .guess(let item): "item:\(item.id.rawValue)"
        case .checkIn(let plan): "plan:\(plan.id.rawValue)"
        }
    }

    var start: Date {
        switch self {
        case .event(let item), .block(let item), .guess(let item): item.start.date
        case .checkIn(let plan): plan.at.date
        }
    }

    var isAllDay: Bool {
        switch self {
        case .event(let item), .block(let item), .guess(let item): item.allDay
        case .checkIn: false
        }
    }

    /// Whether it's Kumo's rather than yours.
    var isKumos: Bool {
        if case .event = self { return false }
        return true
    }

    var item: CalendarItem? {
        switch self {
        case .event(let item), .block(let item), .guess(let item): item
        case .checkIn: nil
        }
    }
}

/// One day's entries, all-day ones first, then by time.
struct DayGroup: Equatable {
    let day: Date
    let entries: [DayEntry]
}

/// Reading the Desk's calendar and plans as days.
enum DayReading {
    /// Kumo's own blocks, and times it's holding: shown faintly, as working notes rather than plans.
    static func isKumos(_ item: CalendarItem) -> Bool {
        item.calendar.kumo || item.status == .hold
    }

    /// A day's entries from the Desk: what's on the calendar that day (a trip you're on counts from
    /// today) and Kumo's plans due that day.
    static func group(
        on day: Date, desk: Desk?, now: Date = .now, calendar: Calendar = .current
    ) -> DayGroup {
        let start = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        let items = (desk?.comingUp ?? []).filter { item in
            let first = max(self.day(of: item, calendar: calendar), today)
            if first == start { return true }
            // An all-day item spanning several days shows on each.
            guard item.allDay, first < start else { return false }
            let last = calendar.date(byAdding: .day, value: days(of: item) - 1, to: first) ?? first
            return start <= last
        }
        let plans = (desk?.plans ?? []).filter { calendar.isDate($0.at.date, inSameDayAs: start) }
        let entries = (items.map(DayEntry.init) + plans.map(DayEntry.checkIn)).sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.start < b.start
        }
        return DayGroup(day: start, entries: entries)
    }

    /// Your own timed events that day, for the thread's knots.
    static func knots(_ group: DayGroup) -> [CalendarItem] {
        group.entries.compactMap { entry in
            if case .event(let item) = entry, !item.allDay { return item }
            return nil
        }
    }

    /// The day an item falls on. An all-day item's start is midnight, but whose midnight depends on
    /// how it was written down (UTC or the box's zone), so it's read from midday instead, which
    /// lands on the same date either way.
    static func day(of item: CalendarItem, calendar: Calendar) -> Date {
        let start = item.allDay ? item.start.date.addingTimeInterval(12 * 3600) : item.start.date
        return calendar.startOfDay(for: start)
    }

    /// How many days an all-day item covers; its end is the morning after its last day.
    static func days(of item: CalendarItem) -> Int {
        max(1, Int((item.end.date.timeIntervalSince(item.start.date) / 86_400).rounded()))
    }

    /// The kinds of time Not right? offers.
    static let corrections: [Activity] = [.working, .building, .people, .chilling]

    /// An activity as a choice: "Seeing people" for people.
    static func name(_ activity: Activity) -> String {
        switch activity {
        case .working: "Working"
        case .building: "Building"
        case .training: "Training"
        case .people: "Seeing people"
        case .studying: "Studying"
        case .chilling: "Chilling"
        default: "Something else"
        }
    }
}
