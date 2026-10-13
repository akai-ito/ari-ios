import Foundation

/// Where Ari reaches an Ito server: HTTPS, or plain HTTP to this device only, for development on
/// the Mac and in the Simulator.
public struct ServerAddress: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The server's root, without a trailing slash.
    public let url: URL

    /// What's wrong with an address someone typed.
    public enum Problem: Error, Equatable, Sendable {
        case empty
        /// It isn't a web address.
        case notAnAddress
        /// Plain HTTP to another device: the token would cross the network unencrypted.
        case insecure
    }

    /// Reads an address as someone types it. Without a scheme it means HTTPS, so `studio:8787` is
    /// `https://studio:8787`.
    public init(_ text: String) throws(Problem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        let written = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: written),
            let scheme = components.scheme?.lowercased(),
            let host = components.host, !host.isEmpty,
            components.query == nil, components.fragment == nil, components.user == nil
        else { throw .notAnAddress }
        switch scheme {
        case "https": break
        case "http" where Self.isThisDevice(host): break
        case "http": throw .insecure
        default: throw .notAnAddress
        }
        components.scheme = scheme
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url else { throw .notAnAddress }
        self.url = url
    }

    public var description: String { url.absoluteString }

    private static func isThisDevice(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return ["localhost", "127.0.0.1", "::1"].contains(bare)
    }
}

/// The token `ito serve` printed. It never shows in full: printing, logging or dumping it gives
/// only its last four characters.
public struct Token: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// The whole token, for the `Authorization` header and the Keychain only.
    public let secret: String

    public init(_ secret: String) {
        self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last four characters, as Ari shows the token: "…f3a9".
    public var lastFour: String { "…" + secret.suffix(4) }

    public var description: String { lastFour }
    public var debugDescription: String { "Token(\(lastFour))" }
    public var customMirror: Mirror { Mirror(self, children: ["lastFour": lastFour]) }
}
