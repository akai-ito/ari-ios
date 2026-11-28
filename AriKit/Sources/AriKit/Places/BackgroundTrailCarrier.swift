import Foundation
import Synchronization

/// Hands sealed batches of the trail to iOS, which uploads them in the background, even once Ito is
/// suspended or gone, and wakes Ito when they're done. A batch woken by a visit in a locked phone
/// still reaches the box: the upload is iOS's from the moment it's handed over.
@MainActor
public final class BackgroundTrailCarrier: NSObject, TrailCarrier {
    public let identifier: String
    /// Where answers go, set before anything is carried.
    public weak var uploads: TrailUploads?
    private var session: URLSession?
    private let relay: TrailRelay
    private var whenDone: (() -> Void)?
    private var eventsDelivered = false

    public init(identifier: String) {
        self.identifier = identifier
        relay = TrailRelay()
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        // Small and worth having soon: arriving and leaving are events the box acts on.
        configuration.isDiscretionary = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        relay.carrier = self
        session = URLSession(configuration: configuration, delegate: relay, delegateQueue: nil)
    }

    /// iOS woke Ito for this session's events: `done` is called once they're all handled.
    public func whenEventsAreHandled(_ done: @escaping () -> Void) {
        whenDone = done
        if eventsDelivered { finishedEvents() }
    }

    public func carry(_ batches: [SealedBatch], with client: ItoClient, to uploads: TrailUploads) {
        self.uploads = uploads
        guard let session else { return }
        for sealed in batches {
            let request = client.trailRequest().urlRequest(to: client.address.url)
            let task = session.uploadTask(with: request, fromFile: sealed.file)
            task.taskDescription = sealed.batch.id.rawValue
            task.resume()
        }
    }

    public func inFlight() async -> Set<TrailBatchID> {
        guard let session else { return [] }
        let tasks = await session.allTasks
        return Set(
            tasks.filter { $0.state != .completed }.compactMap {
                $0.taskDescription.map(TrailBatchID.init(rawValue:))
            })
    }

    fileprivate func completed(_ id: String?, answer: Result<Void, RequestError>) {
        guard let id else { return }
        uploads?.heard(TrailBatchID(id), answer)
    }

    fileprivate func finishedEvents() {
        guard let done = whenDone else {
            eventsDelivered = true
            return
        }
        eventsDelivered = false
        whenDone = nil
        done()
    }
}

/// The session's delegate, on its own queue: each answer goes to the carrier on the main actor.
private final class TrailRelay: NSObject, URLSessionDataDelegate, Sendable {
    nonisolated(unsafe) weak var carrier: BackgroundTrailCarrier?
    let bodies = Mutex<[Int: Data]>([:])

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bodies.withLock { $0[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        let body = bodies.withLock { $0.removeValue(forKey: task.taskIdentifier) } ?? Data()
        let id = task.taskDescription
        let answer: Result<Void, RequestError>
        if let http = task.response as? HTTPURLResponse {
            var headers: [String: String] = [:]
            for case (let name as String, let value as String) in http.allHeaderFields {
                headers[name] = value
            }
            answer = ItoClient.trailAnswer(status: http.statusCode, headers: headers, body: body)
        } else {
            answer = .failure(RequestError(error ?? URLError(.badServerResponse)))
        }
        Task { @MainActor [weak carrier] in carrier?.completed(id, answer: answer) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak carrier] in carrier?.finishedEvents() }
    }
}
