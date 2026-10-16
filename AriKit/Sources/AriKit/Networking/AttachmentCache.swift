import Foundation

/// Photos' and files' bytes kept on this device, by attachment id. An attachment's bytes never
/// change on the server, so whatever is kept here stays right; the system may clear the folder
/// when space runs low, and they're fetched again.
public struct AttachmentCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Caches/Attachments in the app's container.
    public static func forThisApp() -> AttachmentCache {
        AttachmentCache(
            directory: URL.cachesDirectory.appending(
                path: "Attachments", directoryHint: .isDirectory))
    }

    public func bytes(of attachment: AttachmentID) -> Data? {
        try? Data(contentsOf: file(for: attachment))
    }

    public func keep(_ bytes: Data, for attachment: AttachmentID) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? bytes.write(to: file(for: attachment), options: .atomic)
    }

    private func file(for attachment: AttachmentID) -> URL {
        // Ids are the app's or the server's UUIDs; anything else is kept out of the path.
        let name = attachment.rawValue.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appending(path: name)
    }
}
