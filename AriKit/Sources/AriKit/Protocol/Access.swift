// How Kumo runs on the server: in Codex's sandbox, as it does unless you change it, or with full
// access, from its next turn. Settings turns it on, after Face ID, and the main chat shows a marker
// while it lasts.

/// How Kumo runs on the server, and since when it has had full access.
public struct Access: Sendable, Equatable, Codable {
    public var mode: AccessMode
    /// `full` only: when you turned it on.
    public var since: Timestamp?

    public init(mode: AccessMode, since: Timestamp? = nil) {
        self.mode = mode
        self.since = since
    }

    /// Kumo in its sandbox: the default, and what a snapshot without `access` means.
    public static let sandboxed = Access(mode: .sandboxed)

    /// Whether Kumo has full access. A mode this version of Ari doesn't know isn't full access, so
    /// the marker shows only for what Ari knows to mean it.
    public var isFull: Bool { mode == .full }
}

/// `sandboxed`, the default: Kumo writes only in its workspace. `full`: no sandbox at all.
public struct AccessMode: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let sandboxed = AccessMode(rawValue: "sandboxed")
    public static let full = AccessMode(rawValue: "full")
    public static let known = [sandboxed, full]
}

/// You turned full access on or off, from any device: the whole state.
public struct AccessChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let access: Access
}

/// The body that turns full access on: it says it's meant, once the phone has checked it's you.
struct FullAccessConsent: Encodable {
    let confirm = true
}
