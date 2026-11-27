import Foundation

// When Kumo dreams, for Settings: the time it dreams each night, and when the latest dream ran. The
// dream's record itself (what it planned, tidied, noticed and saved for you) belongs to the Desk's
// moon and sun page; Settings reads only what its rows show, and ignores the rest.

/// `GET /v0/dream`, read as far as Settings needs: the time, the next dream, one under way, and when
/// the latest ran.
public struct DreamSchedule: Sendable, Equatable, Decodable {
    /// When Kumo dreams each night, on your local clock, such as `04:00`.
    public let time: Time
    /// When the next dream is due.
    public let nextAt: Timestamp
    /// A dream under way, while there is one.
    public let dreaming: Dreaming?
    /// The latest dream, once there's been one.
    public let latest: LastDream?

    public init(
        time: Time, nextAt: Timestamp, dreaming: Dreaming? = nil, latest: LastDream? = nil
    ) {
        self.time = time
        self.nextAt = nextAt
        self.dreaming = dreaming
        self.latest = latest
    }

    public struct Dreaming: Sendable, Equatable, Decodable {
        public let since: Timestamp
        public let trigger: Trigger
    }

    /// When a dream ran, and why.
    public struct LastDream: Sendable, Equatable, Decodable {
        public let trigger: Trigger
        public let startedAt: Timestamp
        public let endedAt: Timestamp

        public init(trigger: Trigger, startedAt: Timestamp, endedAt: Timestamp) {
            self.trigger = trigger
            self.startedAt = startedAt
            self.endedAt = endedAt
        }

        enum CodingKeys: String, CodingKey {
            case trigger
            case startedAt = "started_at"
            case endedAt = "ended_at"
        }

        /// The row in Settings: "Today 04:00 · 31 min", "Yesterday 04:00 · 2 hr 5 min", or the
        /// day's date further back. Under a minute reads as one.
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
            let time = Self.clock(start, calendar: calendar)
            let minutes = max(1, Int((endedAt.date.timeIntervalSince(start) / 60).rounded()))
            let length =
                minutes < 60
                ? "\(minutes) min"
                : "\(minutes / 60) hr" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
            return "\(day) \(time) · \(length)"
        }

        /// 24-hour, as the dream time is written.
        private static func clock(_ date: Date, calendar: Calendar) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
    }

    enum CodingKeys: String, CodingKey {
        case time, dreaming, latest
        case nextAt = "next_at"
    }
}

// Nested, so the names stay Settings' own beside the Desk's dream record.
extension DreamSchedule {
    /// `scheduled`, at the dream time; `manual`, from Dream now.
    public struct Trigger: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let scheduled = Trigger(rawValue: "scheduled")
        public static let manual = Trigger(rawValue: "manual")
        public static let known = [scheduled, manual]
    }

    /// A time of day on your local clock, written `HH:mm` in 24 hours, such as `04:00`.
    public struct Time: Sendable, Hashable, Codable, CustomStringConvertible {
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

        /// 04:00, until you choose another.
        public static let standard = Time(hour: 4, minute: 0)!

        public var description: String { String(format: "%02d:%02d", hour, minute) }

        /// Today at this time on `calendar`, for a time picker.
        public func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        /// The time of day `date` shows on `calendar`.
        public init(_ date: Date, calendar: Calendar = .current) {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            hour = parts.hour ?? 0
            minute = parts.minute ?? 0
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let time = Time(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\(text) is not a time of day")
            }
            self = time
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }
    }
}

/// The body of `PUT /v0/dream/time`.
struct DreamScheduleChange: Encodable {
    let time: DreamSchedule.Time
}
