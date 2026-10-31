import Foundation

/// A calendar time: an instant, such as `2026-11-12T14:00:00Z`, or for an all-day event a day, such
/// as `2026-11-12`. The text is kept as sent.
public struct When: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    /// The instant of a timed event; `nil` for a day.
    public let instant: Date?
    /// The day of an all-day event, as its year, month and day; `nil` for an instant.
    public let day: DateComponents?

    /// Reads a calendar time; `nil` if the text is neither an instant nor a day.
    public init?(_ rawValue: String) {
        if let day = Self.day(rawValue) {
            self.rawValue = rawValue
            self.day = day
            instant = nil
        } else if let instant = Self.instant(rawValue) {
            self.rawValue = rawValue
            self.instant = instant
            day = nil
        } else {
            return nil
        }
    }

    /// An instant on this device, written as the server writes its own times.
    public init(_ date: Date) {
        rawValue = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        instant = Self.instant(rawValue)
        day = nil
    }

    /// The day of an all-day event.
    public init(year: Int, month: Int, day: Int) {
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
        self.day = DateComponents(year: year, month: month, day: day)
        instant = nil
    }

    public var description: String { rawValue }

    private static func day(_ text: String) -> DateComponents? {
        guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
            let year = Int(match.output.1), let month = Int(match.output.2),
            let day = Int(match.output.3), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    /// Seconds and their fraction are optional in a calendar time, unlike in a timestamp; the offset
    /// isn't.
    private static func instant(_ text: String) -> Date? {
        let pattern =
            #/
            (\d{4})-(\d{2})-(\d{2}) T (\d{2}):(\d{2})
            (?: :(\d{2}) (\.\d+)? )?
            (Z | [+-]\d{2}:\d{2})
            /#
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        let output = match.output
        var offset = 0
        if output.8 != "Z" {
            let sign = output.8.first == "-" ? -1 : 1
            let parts = output.8.dropFirst().split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            offset = sign * (parts[0] * 3600 + parts[1] * 60)
        }
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        var components = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: zone, year: Int(output.1),
            month: Int(output.2), day: Int(output.3), hour: Int(output.4), minute: Int(output.5),
            second: output.6.flatMap { Int($0) } ?? 0)
        if let fraction = output.7.flatMap({ Double("0" + $0) }) {
            components.nanosecond = Int((fraction * 1_000_000_000).rounded())
        }
        guard components.isValidDate else { return nil }
        return components.date
    }
}

extension When: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let when = When(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" is neither an instant nor a day.")
        }
        self = when
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
