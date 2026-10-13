import Foundation

/// Your messages saved on the device before they're sent, so none is lost if Ari closes or the
/// signal drops. Each is a small JSON file, written atomically (to a temporary file, then renamed),
/// so a crash never leaves half of one; its name starts with a sequence number, so the order
/// survives a restart.
public struct OutboxStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The outbox for `address` in Application Support.
    public static func applicationSupport(for address: ServerAddress) throws -> OutboxStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        let name = Data(address.description.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return OutboxStore(
            directory: support.appending(path: "Outbox/\(name)", directoryHint: .isDirectory))
    }

    /// The waiting messages, oldest first.
    public func load() throws -> [SendMessage] {
        try files().map {
            try JSONDecoder().decode(SendMessage.self, from: Data(contentsOf: $0.url))
        }
    }

    public func add(_ message: SendMessage) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try files()
        guard !existing.contains(where: { $0.id == message.id.rawValue }) else { return }
        let next = (existing.last?.sequence ?? 0) + 1
        let name = String(format: "%012d", next) + "-" + message.id.rawValue + ".json"
        try JSONEncoder().encode(message).write(
            to: directory.appending(path: name), options: Self.writing)
    }

    public func remove(_ id: MessageID) throws {
        for file in try files() where file.id == id.rawValue {
            try FileManager.default.removeItem(at: file.url)
        }
    }

    private static var writing: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }

    private func files() throws -> [(sequence: Int, id: String, url: URL)] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", let dash = name.firstIndex(of: "-"),
                let sequence = Int(name[..<dash])
            else { return nil }
            return (sequence, String(name[name.index(after: dash)...]), url)
        }
        .sorted { $0.sequence < $1.sequence }
    }
}
