import Foundation

/// A time as a matter writes it: a day, such as `2026-11-06`, or a local date and time, such as
/// `2026-11-08T09:12`, with no zone. It reads as that day or time on whatever calendar shows it,
/// which is what you'd say out loud ("Friday at 9:30") wherever the event happens. The text is kept
/// as sent.
public struct LocalTime: Hashable, Sendable, Decodable, CustomStringConvertible {
    public let rawValue: String
    /// Its year, month and day, and its hour and minute unless it's a day.
    public let components: DateComponents
    /// Whether it names a day only, with no time.
    public var isDay: Bool { components.hour == nil }

    /// Reads a day or a local date and time; `nil` for anything else.
    public init?(_ rawValue: String) {
        let parts: [Int]
        if let match = rawValue.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            parts = [match.1, match.2, match.3].compactMap { Int($0) }
        } else if let match = rawValue.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/) {
            parts = [match.1, match.2, match.3, match.4, match.5].compactMap { Int($0) }
        } else {
            return nil
        }
        guard (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        if parts.count == 5 {
            guard (0..<24).contains(parts[3]), (0..<60).contains(parts[4]) else { return nil }
            components = DateComponents(
                year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])
        } else {
            components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let time = LocalTime(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\(text) is neither a day nor a local time")
        }
        self = time
    }

    /// The day or time on `calendar`, a day at its start.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: components) ?? .distantFuture
    }

    /// The day or time on this phone's calendar.
    public var date: Date { date(in: .current) }

    public var description: String { rawValue }
}
