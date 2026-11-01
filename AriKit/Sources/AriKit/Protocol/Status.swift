import Foundation

// What your phone tells the box about what you're doing now: the Focus it's in, when you've added
// Ito to that Focus.

/// What a Focus is for, as you chose when adding Ito to it. One Ari doesn't know still goes as it is.
public struct FocusKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let sleep = FocusKind(rawValue: "sleep")
    public static let work = FocusKind(rawValue: "work")
    public static let fitness = FocusKind(rawValue: "fitness")
    public static let personal = FocusKind(rawValue: "personal")
    /// Something else.
    public static let other = FocusKind(rawValue: "other")
    public static let known = [sleep, work, fitness, personal, other]
}

/// The body of `PUT /v0/devices/{device}/status`: the Focus that's on, or none once it's off.
public struct DeviceStatus: Sendable, Equatable, Codable {
    public let focus: FocusKind?

    public init(focus: FocusKind? = nil) {
        self.focus = focus
    }
}
