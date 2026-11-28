import Foundation

/// A time of day on your local clock, written `HH:mm` in 24 hours, such as `04:00`: when Kumo
/// dreams, as Settings picks it.
public struct DreamTimeOfDay: Sendable, Hashable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    /// `nil` unless it's a real time of day.
    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Reads `HH:mm`; `nil` for anything else.
    public init?(_ text: String) {
        guard let match = text.wholeMatch(of: /(\d{2}):(\d{2})/),
            let hour = Int(match.1), let minute = Int(match.2)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// The time of day `date` shows on `calendar`.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
    }

    /// 04:00, until you choose another.
    public static let standard = DreamTimeOfDay(hour: 4, minute: 0)!

    public var description: String { String(format: "%02d:%02d", hour, minute) }

    /// Today at this time on `calendar`, for a time picker.
    public func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

extension Dream {
    /// Settings' Last dream: "Today 04:00 · 31 min", "Yesterday 04:00 · 2 hr 5 min", or the day's
    /// date further back. Under a minute reads as one.
    public func summary(now: Date = .now, calendar: Calendar = .current) -> String {
        let start = startedAt.date
        let day: String
        if calendar.isDate(start, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(start, inSameDayAs: yesterday)
        {
            day = "Yesterday"
        } else {
            day = start.formatted(
                Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day()
                    .month(.abbreviated).locale(calendar.locale ?? .current))
        }
        let time = DreamTimeOfDay(start, calendar: calendar).description
        let minutes = max(1, Int((endedAt.date.timeIntervalSince(start) / 60).rounded()))
        let length =
            minutes < 60
            ? "\(minutes) min"
            : "\(minutes / 60) hr" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
        return "\(day) \(time) · \(length)"
    }
}
