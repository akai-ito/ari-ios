import CryptoKit
import Foundation

/// What Ari last read from one server, kept on the device so it stays readable without a
/// connection: the chat and its threads, the Desk, what's in motion, the Library and the pages
/// Kumo made, with their photos. Each piece is a file of its own, by name (a request's path, or the
/// session's own pieces), written atomically as the outbox's are, so a crash never leaves half of
/// one. It's personal: readable only once the phone has been unlocked since it started, left out of
/// backups, and forgotten when you leave the server.
public struct LocalCopy: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The copy for `address`, in Application Support beside the outbox.
    public static func applicationSupport(for address: ServerAddress) throws -> LocalCopy {
        LocalCopy(directory: try root().appending(path: Self.name(of: address)))
    }

    /// Forgets every server's copy, as when you leave the server or connect to another.
    public static func forgetAll() {
        guard let root = try? root() else { return }
        try? FileManager.default.removeItem(at: root)
    }

    /// The piece kept as `name`, if there is one.
    public func data(_ name: String) -> Data? {
        try? Data(contentsOf: file(name))
    }

    /// Keeps `data` as `name`, replacing what was kept.
    public func keep(_ data: Data, as name: String) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: file(name), options: Self.writing)
        } catch {
            // A copy that can't be written leaves the last one, which is only older.
        }
    }

    /// The value kept as `name`, if there is one this Ari can still read.
    public func value<Value: Decodable>(_ type: Value.Type = Value.self, _ name: String) -> Value? {
        data(name).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// Keeps `value` as `name`, as JSON.
    public func keep(_ value: some Encodable, as name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        keep(data, as: name)
    }

    /// Forgets everything kept for this server.
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Application Support/Offline, made once and left out of backups: everything in it comes from
    /// the server again.
    private static func root() throws -> URL {
        var root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        )
        .appending(path: "Offline", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        return root
    }

    /// As the outbox names a server's folder.
    private static func name(of address: ServerAddress) -> String {
        Data(address.description.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
    }

    /// A name's file: its hash, so a path with a query, or a long one, is always a safe file name.
    private func file(_ name: String) -> URL {
        let hash = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: hash)
    }

    private static var writing: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }
}
