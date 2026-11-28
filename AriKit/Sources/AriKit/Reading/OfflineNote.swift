import Foundation

/// The quiet note that what's on screen is the copy Ari kept, and how fresh it is:
/// "Offline · updated 14:02".
public enum OfflineNote {
    /// The note, for a copy last brought up to date at `updatedAt`; just "Offline" before Ari ever
    /// heard from the server.
    public static func words(
        updatedAt: Date?, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let updatedAt else { return "Offline" }
        return "Offline · updated \(when(updatedAt, now: now, calendar: calendar, locale: locale))"
    }

    /// The time today, "yesterday" with it, or the day for anything older.
    static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let time = date.formatted(
            Date.FormatStyle(
                date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "yesterday \(time)"
        }
        return date.formatted(
            Date.FormatStyle(
                date: nil, time: nil, locale: locale, calendar: calendar,
                timeZone: calendar.timeZone
            )
            .day().month(.abbreviated))
    }
}
