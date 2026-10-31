import Foundation

/// How an occasion reads: when it is, who's there and what's left to prepare. Your ticks on its
/// prep, in the thing's state, win over how Kumo wrote an item, as a trip's to-dos do.
public enum OccasionReading {
    /// The prep list's name in the state.
    public static let prepList = "prep"

    /// Whether a prep item is done: your tick if you've made one, otherwise how Kumo wrote it.
    public static func isDone(_ item: Occasion.Prep, in state: MotionState) -> Bool {
        state[prepList]?[item.id]?.done ?? item.done
    }

    /// What's left to prepare, in its order.
    public static func left(_ occasion: Occasion, state: MotionState) -> [Occasion.Prep] {
        occasion.prep.filter { !isDone($0, in: state) }
    }

    /// How much of the prep is done, from 0 to 1; `nil` without any.
    public static func progress(_ occasion: Occasion, state: MotionState) -> Double? {
        guard !occasion.prep.isEmpty else { return nil }
        let done = occasion.prep.count - left(occasion, state: state).count
        return Double(done) / Double(occasion.prep.count)
    }

    /// What the pinned line and In motion say: when it is, "Tomorrow 09:30" or "Fri 13 Nov", and how
    /// much prep is left, counting your ticks; `nil` without any prep.
    public static func line(
        _ occasion: Occasion, state: MotionState, now: Date = .now,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> (when: String, left: Int?) {
        let when = MatterReading.when(
            occasion.start, allDay: occasion.allDay, now: now, calendar: calendar, locale: locale)
        return (when, occasion.prep.isEmpty ? nil : left(occasion, state: state).count)
    }

    /// When it is, in full: "Friday 13 November · 09:30–10:15", "Saturday 14 November" for a whole
    /// day, "Sat 14 – Sun 15 November" for whole days, "Fri 13 Nov, 18:00 – Sun 15 Nov, 12:00"
    /// across days. The year shows when it isn't this one.
    public static func when(
        _ occasion: Occasion, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let start = occasion.start.date(in: calendar)
        let sameYear = calendar.isDate(start, equalTo: now, toGranularity: .year)
        let year = sameYear ? "" : " y"
        func text(_ template: String, _ date: Date) -> String {
            MatterReading.format(template, calendar: calendar, locale: locale).string(from: date)
        }
        if occasion.allDay {
            // A whole-day end is the midnight after its last day, as in a calendar.
            let last = occasion.end.map { $0.date(in: calendar).addingTimeInterval(-1) } ?? start
            guard last > start, !calendar.isDate(last, inSameDayAs: start) else {
                return text("EEEE d MMMM" + year, start)
            }
            if calendar.isDate(start, equalTo: last, toGranularity: .month) {
                return "\(text("EEE d", start)) – \(text("EEE d MMMM" + year, last))"
            }
            return "\(text("EEE d MMM", start)) – \(text("EEE d MMM" + year, last))"
        }
        let clock = { (time: LocalTime) in
            MatterReading.clock(time, calendar: calendar, locale: locale)
        }
        guard let end = occasion.end, end.date(in: calendar) > start else {
            return "\(text("EEEE d MMMM" + year, start)) · \(clock(occasion.start))"
        }
        if calendar.isDate(start, inSameDayAs: end.date(in: calendar)) {
            return "\(text("EEEE d MMMM" + year, start)) · \(clock(occasion.start))–\(clock(end))"
        }
        return "\(text("EEE d MMM", start)), \(clock(occasion.start)) – "
            + "\(text("EEE d MMM" + year, end.date(in: calendar))), \(clock(end))"
    }

    /// Who's there besides you: "With Dr Shah", "With Janki and Poppy"; `nil` for no one.
    public static func people(_ occasion: Occasion) -> String? {
        guard !occasion.people.isEmpty else { return nil }
        return "With " + ListFormatter.localizedString(byJoining: occasion.people.map(\.name))
    }
}
