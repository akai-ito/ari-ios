import Foundation

/// A time by the server's clock: RFC 3339 in UTC with milliseconds. The text is kept as sent, so it
/// survives a round trip exactly (Foundation's ISO 8601 encoding would drop the milliseconds).
public struct Timestamp: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public let date: Date

    /// Reads a timestamp; `nil` if the text isn't RFC 3339.
    public init?(_ rawValue: String) {
        guard let date = Self.parse(rawValue) else { return nil }
        self.rawValue = rawValue
        self.date = date
    }

    public var description: String { rawValue }

    private static let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutMilliseconds = Date.ISO8601FormatStyle(
        includingFractionalSeconds: false)

    private static func parse(_ text: String) -> Date? {
        (try? withMilliseconds.parse(text)) ?? (try? withoutMilliseconds.parse(text))
    }
}

extension Timestamp: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let timestamp = Timestamp(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" is not an RFC 3339 timestamp.")
        }
        self = timestamp
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
