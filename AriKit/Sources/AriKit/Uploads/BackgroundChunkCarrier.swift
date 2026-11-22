import Foundation
import Synchronization

/// Hands chunks to iOS, which carries them in the background, even once Ari or its share extension
/// is gone, and wakes Ari when they're done. One connection at a time, so they arrive in order; one
/// that arrives early anyway is refused, and the next round sends it again from what the server has.
///
/// Each chunk is a file of its own in the app group, written a window at a time so a long recording
/// never doubles on the phone's disk all at once.
@MainActor
public final class BackgroundChunkCarrier: NSObject, ChunkCarrier {
    public let identifier: String
    /// Where answers go: Ari's uploads, set before anything is carried.
    public weak var uploads: BigUploads?
    private var session: URLSession?
    private let relay: Relay
    /// Settling that a background wake must wait for before telling iOS it's done.
    private var settling: [Task<Void, Never>] = []
    /// What to tell iOS once a wake's events are handled.
    private var whenDone: (() -> Void)?
    /// The session said its events were all delivered before iOS's handler arrived.
    private var eventsDelivered = false

    /// Chunks per round: a long recording goes in rounds of this many.
    static let window = 64

    /// - Parameters:
    ///   - identifier: The background session's, such as the app group's with `.uploads.app`.
    ///   - sharedContainer: The app group, so the share extension's chunks reach Ari.
    public init(identifier: String, sharedContainer: String?) {
        self.identifier = identifier
        relay = Relay()
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = sharedContainer
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        relay.carrier = self
        session = URLSession(configuration: configuration, delegate: relay, delegateQueue: nil)
    }

    /// iOS woke Ari for this session's events: `done` is called once they're all handled.
    public func whenEventsAreHandled(_ done: @escaping () -> Void) {
        whenDone = done
        if eventsDelivered { finishedEvents() }
    }

    public func carry(_ chunks: [BigUpload.Chunk], of upload: BigUpload, to uploads: BigUploads) {
        self.uploads = uploads
        guard let session else { return }
        let id = upload.id
        var carried = 0
        for chunk in chunks.prefix(Self.window) {
            let file: URL
            do {
                file = try uploads.store.chunkFile(chunk, of: id)
            } catch {
                uploads.heard(id, offset: chunk.offset, .failure(.unreadable("\(error)")))
                break
            }
            let request = uploads.client.chunkRequest(id, offset: chunk.offset)
                .urlRequest(to: uploads.client.address.url)
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = Self.describe(id, chunk.offset)
            task.resume()
            carried += 1
        }
        if carried == 0 { Task { await uploads.settled(id) } }
    }

    public func cancel(_ id: AttachmentID) {
        session?.getAllTasks { tasks in
            for task in tasks where Self.read(task.taskDescription)?.id == id { task.cancel() }
        }
    }

    public func inFlight() async -> Set<AttachmentID> {
        guard let session else { return [] }
        let tasks = await session.allTasks
        return Set(
            tasks.filter { $0.state != .completed }.compactMap { Self.read($0.taskDescription)?.id }
        )
    }

    // MARK: - From the relay

    fileprivate func progressed(_ description: String?, sent: Int64) {
        guard let (id, offset) = Self.read(description) else { return }
        uploads?.progressed(id, offset: offset, sent: Int(sent))
    }

    fileprivate func completed(_ description: String?, answer: Result<UploadStatus, RequestError>) {
        guard let (id, offset) = Self.read(description), let uploads else { return }
        uploads.heard(id, offset: offset, answer)
        let task = Task {
            guard let session else { return }
            let left = await session.allTasks.contains {
                $0.state != .completed && Self.read($0.taskDescription)?.id == id
            }
            if !left { await uploads.settled(id) }
        }
        settling.append(task)
    }

    fileprivate func finishedEvents() {
        guard whenDone != nil else {
            eventsDelivered = true
            return
        }
        eventsDelivered = false
        let waiting = settling
        settling = []
        Task {
            for task in waiting { await task.value }
            let done = whenDone
            whenDone = nil
            done?()
        }
    }

    // MARK: - Naming tasks

    private static func describe(_ id: AttachmentID, _ offset: Int) -> String {
        "\(id.rawValue)@\(offset)"
    }

    private nonisolated static func read(_ description: String?) -> (id: AttachmentID, offset: Int)?
    {
        guard let description, let at = description.lastIndex(of: "@"),
            let offset = Int(description[description.index(after: at)...])
        else { return nil }
        return (AttachmentID(String(description[..<at])), offset)
    }
}

/// The session's delegate, on its own queue: it gathers each answer and hands it to the carrier on
/// the main actor, whole.
private final class Relay: NSObject, URLSessionDataDelegate, Sendable {
    nonisolated(unsafe) weak var carrier: BackgroundChunkCarrier?
    let bodies = Mutex<[Int: Data]>([:])

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bodies.withLock { $0[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        let description = task.taskDescription
        Task { @MainActor [weak carrier] in carrier?.progressed(description, sent: totalBytesSent) }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        let body = bodies.withLock { $0.removeValue(forKey: task.taskIdentifier) } ?? Data()
        let description = task.taskDescription
        let answer: Result<UploadStatus, RequestError>
        if let http = task.response as? HTTPURLResponse {
            var headers: [String: String] = [:]
            for case (let name as String, let value as String) in http.allHeaderFields {
                headers[name] = value
            }
            answer = ItoClient.chunkAnswer(status: http.statusCode, headers: headers, body: body)
        } else {
            answer = .failure(RequestError(error ?? URLError(.badServerResponse)))
        }
        Task { @MainActor [weak carrier] in carrier?.completed(description, answer: answer) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak carrier] in carrier?.finishedEvents() }
    }
}
