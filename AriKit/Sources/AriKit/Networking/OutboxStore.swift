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

    /// The waiting messages, oldest first. A file that reads but isn't a waiting message, such as
    /// one an older Ari left, is deleted.
    public func load() throws -> [SendMessage] {
        try files().compactMap { file in
            let data = try Data(contentsOf: file.url)
            guard let message = try? JSONDecoder().decode(SendMessage.self, from: data) else {
                try? FileManager.default.removeItem(at: file.url)
                return nil
            }
            return message
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

    // MARK: - Attachments waiting to upload

    /// Saves an attachment's bytes until the server has them, beside the waiting messages.
    public func add(_ attachment: PendingAttachment) throws {
        let folder = directory.appending(path: "attachments")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = attachment.id.rawValue
        try attachment.bytes.write(to: folder.appending(path: id + ".bytes"), options: Self.writing)
        let about = PendingAttachment.About(name: attachment.name, mediaType: attachment.mediaType)
        try JSONEncoder().encode(about).write(
            to: folder.appending(path: id + ".about"), options: Self.writing)
    }

    /// The attachments still to upload.
    public func attachments() -> [PendingAttachment] {
        let folder = directory.appending(path: "attachments")
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: folder.path(percentEncoded: false)))
            ?? []
        return names.filter { $0.hasSuffix(".about") }.compactMap { name in
            let id = String(name.dropLast(".about".count))
            guard let about = try? Data(contentsOf: folder.appending(path: name)),
                let decoded = try? JSONDecoder().decode(PendingAttachment.About.self, from: about),
                let bytes = try? Data(contentsOf: folder.appending(path: id + ".bytes"))
            else { return nil }
            return PendingAttachment(
                id: AttachmentID(id), name: decoded.name, mediaType: decoded.mediaType, bytes: bytes
            )
        }
    }

    public func removeAttachment(_ attachment: AttachmentID) {
        let folder = directory.appending(path: "attachments")
        for suffix in [".bytes", ".about"] {
            try? FileManager.default.removeItem(
                at: folder.appending(path: attachment.rawValue + suffix))
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
