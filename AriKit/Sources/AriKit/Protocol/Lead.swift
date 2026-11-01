import Foundation

// The settings you make for Kumo itself: what it's called, and when your morning starts.

/// The lead you talk to: Kumo until you choose another name. `GET /v0/server`'s `lead`, and the
/// body and answer of `PUT /v0/lead`.
public struct Lead: Sendable, Equatable, Codable {
    public let name: String

    public init(name: String) { self.name = name }
}

/// When your morning starts: the earliest Kumo's first line of the day may come, as `HH:mm` on a
/// 24-hour clock in the box's time. `GET /v0/server`'s `morning`, and the body and answer of
/// `PUT /v0/morning`.
public struct MorningTime: Sendable, Equatable, Codable {
    /// Such as "07:30".
    public let notBefore: String

    /// Half past seven, until you choose another time.
    public static let standard = MorningTime(hour: 7, minute: 30)

    public init(notBefore: String) { self.notBefore = notBefore }

    public init(hour: Int, minute: Int) {
        notBefore = String(format: "%02d:%02d", hour, minute)
    }

    /// The hour and minute, or `nil` if the server sent something that isn't `HH:mm`.
    public var time: (hour: Int, minute: Int)? {
        let parts = notBefore.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    enum CodingKeys: String, CodingKey {
        case notBefore = "not_before"
    }
}
