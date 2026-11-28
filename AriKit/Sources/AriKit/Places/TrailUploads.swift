import Foundation
import Observation
import os

/// Sends the trail waiting on the phone to the box, a sealed batch at a time, whenever it's
/// reachable. A batch leaves the phone only once the box has said it has it; anything else, it
/// waits for the next try. Sending a batch twice is harmless: the box keeps each id once.
@MainActor
@Observable
public final class TrailUploads {
    /// Points and visits on the phone that the box doesn't have yet.
    public private(set) var waiting = 0
    /// When the box last took a batch.
    public private(set) var lastSent: Date?
    /// Why the last batch didn't go, until one does; being offline or out of reach, the usual
    /// reason, isn't one.
    public private(set) var problem: RequestError?

    @ObservationIgnored public let queue: TrailQueue
    /// The box to send to; with none, the trail waits.
    @ObservationIgnored public var client: ItoClient?
    @ObservationIgnored private let carrier: any TrailCarrier
    @ObservationIgnored private let defaults: UserDefaults

    private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "places")

    public init(queue: TrailQueue, carrier: any TrailCarrier, defaults: UserDefaults = .standard) {
        self.queue = queue
        self.carrier = carrier
        self.defaults = defaults
        lastSent = defaults.object(forKey: "trailLastSent") as? Date
        waiting = queue.waiting()
    }

    /// Seals what's open and sends every batch that isn't already on its way.
    public func send() async {
        do {
            try queue.seal()
        } catch {
            Self.log.error("couldn't seal the trail: \(error)")
        }
        waiting = queue.waiting()
        guard let client else { return }
        let flying = await carrier.inFlight()
        let batches = queue.sealed().filter { !flying.contains($0.batch.id) }
        guard !batches.isEmpty else { return }
        carrier.carry(batches, with: client, to: self)
    }

    /// Something was added to the queue: just the count changes.
    public func added() {
        waiting = queue.waiting()
    }

    /// A batch's answer, from whichever carrier took it.
    public func heard(_ id: TrailBatchID, _ answer: Result<Void, RequestError>) {
        switch answer {
        case .success:
            queue.remove(id)
            lastSent = .now
            defaults.set(lastSent, forKey: "trailLastSent")
            problem = nil
        case .failure(let error):
            Self.log.notice("trail batch \(id.rawValue) waits: \(String(describing: error))")
            if case .network = error { problem = nil } else { problem = error }
        }
        waiting = queue.waiting()
    }

    /// Whether a refusal means the box already has the batch.
    nonisolated static func kept(_ status: Int) -> Bool {
        (200..<300).contains(status) || status == 409
    }

}

/// Carries batches to the box: iOS in the background in the app, this process in tests.
@MainActor
public protocol TrailCarrier: AnyObject {
    /// Starts sending these batches. Each answer goes to ``TrailUploads/heard(_:_:)``.
    func carry(_ batches: [SealedBatch], with client: ItoClient, to uploads: TrailUploads)
    /// The batches on their way now.
    func inFlight() async -> Set<TrailBatchID>
}

/// Sends batches from this process, one after another, while it runs: for tests, and wherever a
/// background session isn't available.
@MainActor
public final class DirectTrailCarrier: TrailCarrier {
    private var flying: Set<TrailBatchID> = []

    public init() {}

    public func carry(_ batches: [SealedBatch], with client: ItoClient, to uploads: TrailUploads) {
        let fresh = batches.filter { !flying.contains($0.batch.id) }
        flying.formUnion(fresh.map(\.batch.id))
        Task {
            for sealed in fresh {
                let answer: Result<Void, RequestError>
                if let body = try? Data(contentsOf: sealed.file) {
                    do throws(RequestError) {
                        try await client.sendTrail(body)
                        answer = .success(())
                    } catch {
                        answer = .failure(error)
                    }
                } else {
                    answer = .failure(.unreadable("the batch's file is gone"))
                }
                flying.remove(sealed.batch.id)
                uploads.heard(sealed.batch.id, answer)
                // Offline: the rest would fail the same way, and wait for the next try.
                if case .failure(.network) = answer { break }
            }
            flying.subtract(fresh.map(\.batch.id))
        }
    }

    public func inFlight() async -> Set<TrailBatchID> { flying }
}
