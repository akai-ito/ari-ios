import Foundation

/// What Ari shares with its extensions through its app group: the server's address, the token (in
/// the group's Keychain), and the outbox that shares wait in until they're sent.
public struct AppGroup: Sendable {
    /// Such as `group.io.github.akai-ito.ari`.
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// The group for this app, or for one of its extensions: named after the app's bundle
    /// identifier.
    public static func forThisApp(_ bundle: Bundle = .main) -> AppGroup {
        var identifier = bundle.bundleIdentifier ?? "io.github.akai-ito.ari"
        if bundle.bundleURL.pathExtension == "appex", let dot = identifier.lastIndex(of: ".") {
            identifier = String(identifier[..<dot])
        }
        return AppGroup(identifier: "group." + identifier)
    }

    /// The server Ari is connected to, for the extensions to reach it too.
    public var address: ServerAddress? {
        get {
            UserDefaults(suiteName: identifier)?.string(forKey: "address")
                .flatMap { try? ServerAddress($0) }
        }
        nonmutating set {
            UserDefaults(suiteName: identifier)?.set(newValue?.description, forKey: "address")
        }
    }

    /// Tokens kept where the extensions can read them.
    public var tokens: KeychainTokenStore {
        KeychainTokenStore(accessGroup: identifier)
    }

    /// Where a share waits until it's sent: by the share extension at once, or by Ari when it
    /// next opens. `nil` without the app group, as in a build without its entitlement.
    public func shares() -> OutboxStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            .map {
                OutboxStore(directory: $0.appending(path: "Shares", directoryHint: .isDirectory))
            }
    }
}

/// Sends what waits in the share outbox: its photos and files first, then its messages. Repeating
/// any of it is safe, so whatever doesn't go simply waits for the next try, by the extension or by
/// Ari.
public enum ShareDelivery {
    /// Returns whether everything went.
    public static func deliver(_ shares: OutboxStore, with client: ItoClient) async -> Bool {
        for attachment in shares.attachments() {
            do {
                _ = try await client.upload(
                    attachment.id, name: attachment.name, mediaType: attachment.mediaType,
                    bytes: attachment.bytes)
                shares.removeAttachment(attachment.id)
            } catch {
                // Ari uploads it again, and says why if the server refuses it.
                return false
            }
        }
        for message in (try? shares.load()) ?? [] {
            do {
                _ = try await client.send(message)
                try? shares.remove(message.id)
            } catch {
                return false
            }
        }
        return true
    }
}
