import Foundation

/// The trail waiting on the phone until the box has it, so nothing is lost offline, in the
/// background or across a restart. Points and visits go into an open batch, rewritten atomically
/// with each one (to a temporary file, then renamed, like the outbox), so a crash or iOS ending Ito
/// never leaves half of one. A full batch is sealed: from then on it never changes, and its id makes
/// sending it again harmless. A sealed batch's file is exactly the body that's uploaded.
public struct TrailQueue: Sendable {
    public let directory: URL
    /// Entries per batch before it's sealed.
    public let batchSize: Int

    public init(directory: URL, batchSize: Int = 200) {
        self.directory = directory
        self.batchSize = batchSize
    }

    /// The queue in Application Support, for whichever box the phone is paired with: the trail is
    /// yours, not a server's, so it waits through a change of box too.
    public static func applicationSupport() throws -> TrailQueue {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        return TrailQueue(directory: support.appending(path: "Trail", directoryHint: .isDirectory))
    }

    // MARK: - Adding

    public func add(_ point: TrailPoint) throws {
        try change { $0.points.append(point) }
    }

    /// A visit; a later delivery of the same one, with its departure, replaces it while it's still
    /// in the open batch.
    public func add(_ visit: TrailVisit) throws {
        try change { batch in
            var visit = visit
            if let earlier = batch.visits.first(where: { $0.key == visit.key }) {
                visit.placemark = visit.placemark ?? earlier.placemark
            }
            batch.visits.removeAll { $0.key == visit.key }
            batch.visits.append(visit)
        }
    }

    /// Seals the open batch, if it has anything, so it can go now.
    public func seal() throws {
        guard let open = try readOpen(), !open.isEmpty else { return }
        try write(open, sealedAs: nextSequence())
        try? FileManager.default.removeItem(at: openFile)
    }

    // MARK: - Reading

    /// The sealed batches, oldest first.
    public func sealed() -> [SealedBatch] {
        files().compactMap { file in
            // Not readable now, as before the first unlock after a restart: it waits.
            guard let data = try? Data(contentsOf: file.url) else { return nil }
            guard let batch = try? Self.decoder.decode(TrailBatch.self, from: data) else {
                // Read but not a batch, as from an older Ito: it can never be sent.
                try? FileManager.default.removeItem(at: file.url)
                return nil
            }
            return SealedBatch(batch: batch, file: file.url)
        }
    }

    /// How many points and visits are waiting, sealed or not.
    public func waiting() -> Int {
        let open = (try? readOpen())?.count ?? 0
        return open + sealed().reduce(0) { $0 + $1.batch.count }
    }

    /// The box has this batch.
    public func remove(_ id: TrailBatchID) {
        for file in files() where file.id == id.rawValue {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - Deleting what you asked to

    /// Drops what's waiting between `start` and `end`, as when you delete a day: it never leaves.
    public func remove(from start: Date, to end: Date) throws {
        let inside = { (date: Date?) in date.map { $0 >= start && $0 < end } ?? false }
        try change { batch in
            batch.points.removeAll { inside($0.at) }
            batch.visits.removeAll { inside($0.at) }
        }
        for sealed in sealed() {
            var batch = sealed.batch
            batch.points.removeAll { inside($0.at) }
            batch.visits.removeAll { inside($0.at) }
            guard batch != sealed.batch else { continue }
            if batch.isEmpty {
                try FileManager.default.removeItem(at: sealed.file)
            } else {
                try Self.encoder.encode(batch).write(to: sealed.file, options: Self.writing)
            }
        }
    }

    /// Drops everything waiting.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    private var openFile: URL { directory.appending(path: "open.json") }

    private func change(_ edit: (inout TrailBatch) -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var open = try readOpen() ?? TrailBatch(id: TrailBatchID(UUID().uuidString.lowercased()))
        edit(&open)
        if open.count >= batchSize {
            try write(open, sealedAs: nextSequence())
            try? FileManager.default.removeItem(at: openFile)
        } else if open.isEmpty {
            try? FileManager.default.removeItem(at: openFile)
        } else {
            try Self.encoder.encode(open).write(to: openFile, options: Self.writing)
        }
    }

    private func readOpen() throws -> TrailBatch? {
        guard let data = try? Data(contentsOf: openFile) else { return nil }
        return try? Self.decoder.decode(TrailBatch.self, from: data)
    }

    private func write(_ batch: TrailBatch, sealedAs sequence: Int) throws {
        let name = String(format: "%012d", sequence) + "-" + batch.id.rawValue + ".json"
        try Self.encoder.encode(batch).write(
            to: directory.appending(path: name), options: Self.writing)
    }

    private func nextSequence() -> Int {
        (files().last?.sequence ?? 0) + 1
    }

    private func files() -> [(sequence: Int, id: String, url: URL)] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
            ?? []
        return urls.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", let dash = name.firstIndex(of: "-"),
                let sequence = Int(name[..<dash])
            else { return nil }
            return (sequence, String(name[name.index(after: dash)...]), url)
        }
        .sorted { $0.sequence < $1.sequence }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    /// Readable once the phone has been unlocked since it started, so a visit that relaunches Ito
    /// in the background, phone locked in a pocket, can still be written.
    private static var writing: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }
}

/// A sealed batch and where it's kept: the file is the body to upload.
public struct SealedBatch: Sendable, Equatable {
    public let batch: TrailBatch
    public let file: URL
}
