import Foundation

/// Photos' and files' bytes kept on this device, by attachment id. An attachment's bytes never
/// change on the server, so whatever is kept here stays right, and what you've seen shows without a
/// connection; the system may clear the folder when space runs low, and they're fetched again.
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
        try? bytes.write(to: file(for: attachment), options: Self.writing)
    }

    /// Forgets every attachment kept, as when you leave the server.
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Your photos and files are personal: readable only once the phone has been unlocked since
    /// it started.
    private static var writing: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }

    private func file(for attachment: AttachmentID) -> URL {
        // Ids are the app's or the server's UUIDs; anything else is kept out of the path.
        let name = attachment.rawValue.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appending(path: name)
    }
}
