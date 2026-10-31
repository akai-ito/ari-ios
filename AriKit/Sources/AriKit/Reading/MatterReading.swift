import Foundation

/// How the times in a matter read: when it's waited since, when the next step is. Times are the
/// server's, read in the device's calendar and time zone.
public enum MatterReading {
    /// A day, short: "15 Oct", with its year when that isn't this one: "15 Oct 2025".
    public static func day(
        _ time: Timestamp, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let sameYear = calendar.isDate(time.date, equalTo: now, toGranularity: .year)
        return format(sameYear ? "d MMM" : "d MMM y", calendar: calendar, locale: locale)
            .string(from: time.date)
    }

    /// When something is, as said: "Today 14:00", "Tomorrow 09:30", "Yesterday 18:00", a weekday
    /// within the week ahead, "Thu 14:00", and further off the day alone, "Tue 17 Nov". A time of
    /// midnight is a day without a time, so none shows, nor for a whole day (`allDay`). Inside a
    /// line, not `first`, it's "today", "tomorrow" and "yesterday".
    public static func when(
        _ time: Timestamp, allDay: Bool = false, first: Bool = true, now: Date = .now,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let days = daysFrom(now, to: time.date, in: calendar)
        let dayText: String
        switch days {
        case 0: dayText = first ? "Today" : "today"
        case 1: dayText = first ? "Tomorrow" : "tomorrow"
        case -1: dayText = first ? "Yesterday" : "yesterday"
        case 2...6:
            dayText = format("EEE", calendar: calendar, locale: locale).string(from: time.date)
        default:
            let sameYear = calendar.isDate(time.date, equalTo: now, toGranularity: .year)
            return format(sameYear ? "EEE d MMM" : "d MMM y", calendar: calendar, locale: locale)
                .string(from: time.date)
        }
        guard !allDay, !isMidnight(time, in: calendar) else { return dayText }
        return "\(dayText) \(clock(time, calendar: calendar, locale: locale))"
    }

    /// A time of day: "14:00", or "2:00 PM" where that's how the clock reads.
    public static func clock(
        _ time: Timestamp, calendar: Calendar = .current, locale: Locale = .current
    )
        -> String
    {
        format("jjmm", calendar: calendar, locale: locale).string(from: time.date)
    }

    /// Who it's waiting on and since when: "Waiting on Poppy since 15 Oct".
    public static func waiting(
        _ waiting: WaitingOn, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let since =
            daysFrom(now, to: waiting.since.date, in: calendar) == 0
            ? "today" : day(waiting.since, now: now, calendar: calendar, locale: locale)
        return "Waiting on \(waiting.who) since \(since)"
    }

    /// The next step, with when if it's set: "Second round · Tue 17 Nov".
    public static func next(
        _ next: NextStep, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let at = next.at else { return next.text }
        return
            "\(next.text) · \(when(at, first: false, now: now, calendar: calendar, locale: locale))"
    }

    // MARK: - Days

    /// Whole days from `now`'s day to `date`'s, in the calendar: 0 for today, 1 for tomorrow.
    static func daysFrom(_ now: Date, to date: Date, in calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    static func isMidnight(_ time: Timestamp, in calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: time.date)
        return parts.hour == 0 && parts.minute == 0
    }

    static func format(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
