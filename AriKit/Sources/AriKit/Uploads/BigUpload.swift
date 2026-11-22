import Foundation

/// A file too big to go in one request, such as a recorded conversation, on its way to the server in
/// chunks. Its record lives beside the file in the app group, so Ari, its share extension and iOS
/// carrying the chunks in the background all see the same one, and it resumes from what the server
/// has after any drop, restart or eviction.
public struct BigUpload: Codable, Sendable, Equatable, Identifiable {
    /// The id Ari made, which becomes the attachment's.
    public let id: AttachmentID
    public let name: String
    public let mediaType: String
    /// In bytes.
    public let size: Int
    /// The size of each chunk; the last may be smaller.
    public let chunkBytes: Int
    /// How many bytes from the start the server has, as last heard.
    public var received: Int
    public var state: State
    /// The message that waits for it, sent once it's an attachment, by whoever is awake then.
    /// Sending the same message again is always safe, so Ari's own outbox may send it too.
    public var message: SendMessage?
    /// Whether that message has reached the server.
    public var messageSent = false
    /// How long a recording is, when the phone could tell.
    public var durationSeconds: Double?
    public let startedAt: Date
    /// Who hands its chunks to iOS: Ari (`app`) or its share extension (`share`).
    public var carriedBy: String?

    public enum State: Codable, Sendable, Equatable {
        /// Its chunks are going, or wait to.
        case sending
        /// It's an attachment, to name in a message.
        case finished(Attachment)
        /// The server won't take it, in its words; it waits for you to take it off.
        case refused(ServerError)
    }

    /// About 8 MB a chunk, as the server suggests, never more than it takes.
    public static let preferredChunk = 8 * 1024 * 1024

    public init(
        id: AttachmentID, name: String, mediaType: String, size: Int, chunkLimit: Int,
        durationSeconds: Double? = nil, startedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.size = size
        chunkBytes = max(1, min(Self.preferredChunk, chunkLimit))
        received = 0
        state = .sending
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
    }

    /// The attachment as the conversation shows it, before the server has it.
    public var attachment: Attachment {
        if case .finished(let attachment) = state { return attachment }
        return Attachment(
            id: id, kind: UploadLimits.kind(of: mediaType), name: name, mediaType: mediaType,
            size: size)
    }

    /// From 0 to 1.
    public var fraction: Double {
        size == 0 ? 1 : min(1, Double(received) / Double(size))
    }

    public var isSending: Bool { state == .sending }

    /// The chunks still to send, in order, from what the server has.
    public var remainingChunks: [Chunk] {
        stride(from: received, to: size, by: chunkBytes).map {
            Chunk(offset: $0, length: min(chunkBytes, size - $0))
        }
    }

    /// The server said where the upload stands. What it has only grows, unless it started the
    /// upload over.
    public mutating func heard(_ status: UploadStatus) {
        received = min(size, status.received)
        if status.state == "finished", let attachment = status.attachment {
            state = .finished(attachment)
        }
    }

    /// A piece of the file: `length` bytes from `offset`.
    public struct Chunk: Sendable, Equatable, Hashable {
        public let offset: Int
        public let length: Int

        public init(offset: Int, length: Int) {
            self.offset = offset
            self.length = length
        }
    }
}

/// Where big uploads wait: a folder each, with the record, the file, and the chunks iOS is carrying.
/// A finished upload keeps its file for a week, so a recording sent from this phone plays at once.
public struct BigUploadStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store in Ari's app group, which its share extension uses too.
    public static func shared(_ group: AppGroup = .forThisApp()) -> BigUploadStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group.identifier)
            .map {
                BigUploadStore(
                    directory: $0.appending(path: "Uploads", directoryHint: .isDirectory))
            }
    }

    /// How long a finished upload's file is kept on the phone.
    static let keeping: TimeInterval = 7 * 24 * 3600

    private func folder(_ id: AttachmentID) -> URL {
        directory.appending(path: id.rawValue, directoryHint: .isDirectory)
    }

    /// The file itself, while it uploads and for a week after.
    public func file(_ id: AttachmentID) -> URL {
        folder(id).appending(path: "file")
    }

    /// The file, if the phone still has it.
    public func keptFile(_ id: AttachmentID) -> URL? {
        let url = file(id)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Takes in the file to upload: a copy, as what was picked or shared goes away.
    public func take(_ upload: BigUpload, from source: URL) throws {
        try FileManager.default.createDirectory(
            at: folder(upload.id), withIntermediateDirectories: true)
        let destination = file(upload.id)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        try save(upload)
    }

    public func save(_ upload: BigUpload) throws {
        try FileManager.default.createDirectory(
            at: folder(upload.id), withIntermediateDirectories: true)
        try JSONEncoder().encode(upload).write(
            to: folder(upload.id).appending(path: "upload.json"), options: .atomic)
    }

    public func load(_ id: AttachmentID) -> BigUpload? {
        (try? Data(contentsOf: folder(id).appending(path: "upload.json")))
            .flatMap { try? JSONDecoder().decode(BigUpload.self, from: $0) }
    }

    /// Every upload the store holds, oldest first.
    public func all() -> [BigUpload] {
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))) ?? []
        return names.compactMap { load(AttachmentID($0)) }.sorted { $0.startedAt < $1.startedAt }
    }

    /// The bytes of one chunk.
    public func read(_ chunk: BigUpload.Chunk, of id: AttachmentID) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file(id))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(chunk.offset))
        return try handle.read(upToCount: chunk.length) ?? Data()
    }

    /// One chunk as a file of its own, for iOS to carry in the background.
    public func chunkFile(_ chunk: BigUpload.Chunk, of id: AttachmentID) throws -> URL {
        let chunks = folder(id).appending(path: "chunks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true)
        let url = chunks.appending(path: String(chunk.offset))
        try read(chunk, of: id).write(to: url, options: .atomic)
        return url
    }

    public func removeChunk(at offset: Int, of id: AttachmentID) {
        try? FileManager.default.removeItem(
            at: folder(id).appending(path: "chunks/\(offset)"))
    }

    /// The chunks go once the server has the whole file; the file stays a while to play.
    public func tidy(_ id: AttachmentID) {
        try? FileManager.default.removeItem(at: folder(id).appending(path: "chunks"))
    }

    public func remove(_ id: AttachmentID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Lets go of finished uploads' files after a week.
    public func sweep(now: Date = .now) {
        for upload in all() {
            if case .finished = upload.state, upload.messageSent || upload.message == nil,
                now.timeIntervalSince(upload.startedAt) > Self.keeping
            {
                remove(upload.id)
            }
        }
    }
}
