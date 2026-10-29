import Foundation
import Observation

/// What's in motion: the things Ari keeps going for you, for the In motion tab, the pinned line and
/// the compact lines under replies. The session hands it every motion event; it fetches a thing's
/// content again when it changes. A refresh that fails keeps what was shown.
@MainActor
@Observable
public final class Motions {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    /// Everything going on, then what's done, each most recently changed first, as the server
    /// lists them.
    public private(set) var all: [Motion] = []
    /// Each thing's content, ticks and what changed, once fetched.
    public private(set) var details: [MotionID: MotionDetail] = [:]
    public private(set) var load = Load.loading
    /// Things whose pinned line you swiped away, at the version you did. One comes back when Ari
    /// changes it again.
    public private(set) var dismissed: [MotionID: Int]

    /// The changes heard on the stream since the thing's detail was fetched, for compact lines.
    @ObservationIgnored private var heard: [MotionID: [MotionChange]] = [:]
    @ObservationIgnored private let client: ItoClient
    @ObservationIgnored private let defaults: UserDefaults

    private static let dismissedKey = "motion.dismissed"

    public init(client: ItoClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.dismissedKey) as? [String: Int] ?? [:]
        dismissed = Dictionary(uniqueKeysWithValues: saved.map { (MotionID($0.key), $0.value) })
    }

    public var going: [Motion] { all.filter { $0.status != .done } }
    public var done: [Motion] { all.filter { $0.status == .done } }

    public subscript(id: MotionID) -> Motion? {
        all.first { $0.id == id } ?? details[id]?.motion
    }

    /// The pinned line: the most recently changed thing that's pinned, going on and not swiped
    /// away, and how many more are pinned besides.
    public var pinned: (motion: Motion, more: Int)? {
        let shown = going.filter { motion in
            motion.pinned && (dismissed[motion.id].map { $0 < motion.version } ?? true)
        }
        guard let first = shown.max(by: { $0.changedAt.date < $1.changedAt.date }) else {
            return nil
        }
        return (first, shown.count - 1)
    }

    /// Asks for everything in motion, then the content of each thing going on, for its line.
    public func refresh() async {
        do {
            all = Self.ordered(try await client.motions().motions)
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(RequestError(error)) }
            return
        }
        for motion in going where details[motion.id]?.motion.version != motion.version {
            _ = try? await detail(motion.id)
        }
    }

    /// Fetches a thing's content, ticks and what changed, and keeps them.
    @discardableResult
    public func detail(_ id: MotionID) async throws(RequestError) -> MotionDetail {
        let fetched = try await client.motion(id)
        // Two changes close together fetch twice: an older answer arriving last never wins.
        if let kept = details[id], kept.motion.version > fetched.motion.version { return kept }
        details[id] = fetched
        heard[id]?.removeAll { change in fetched.changes.contains { $0.version == change.version } }
        return fetched
    }

    /// Follows the stream: Ari starting, changing or finishing a thing, your ticks on any device,
    /// and a thing forgotten. A snapshot means events may have been missed, so it asks again.
    public func apply(_ event: Event) {
        switch event.payload {
        case .snapshot:
            Task { await refresh() }
        case .motionStarted(let event), .motionChanged(let event), .motionFinished(let event):
            all.removeAll { $0.id == event.motion.id }
            all = Self.ordered(all + [event.motion])
            heard[event.motion.id, default: []].append(event.change)
            if load != .loaded { load = .loaded }
            let id = event.motion.id
            Task { _ = try? await detail(id) }
        case .motionState(let event):
            details[event.motion]?.state = event.state
        case .motionRemoved(let event):
            all.removeAll { $0.id == event.motion }
            details[event.motion] = nil
            heard[event.motion] = nil
            dismissed[event.motion] = nil
            saveDismissed()
        default:
            break
        }
    }

    /// Ticks an item, or unticks it, at once on screen: `false` if the server didn't take it, and
    /// the tick goes back.
    public func tick(_ motion: MotionID, list: String, item: String, done: Bool) async -> Bool {
        let before = details[motion]?.state
        details[motion]?.state[list, default: [:]][item] = MotionTick(done: done)
        do {
            let state = try await client.tick(motion, list: list, item: item, done: done)
            details[motion]?.state = state
            return true
        } catch {
            if let before { details[motion]?.state = before }
            return false
        }
    }

    /// Swipes a thing's pinned line away until Ari next changes it. It stays in In motion.
    public func dismiss(_ motion: Motion) {
        dismissed[motion.id] = motion.version
        saveDismissed()
    }

    /// What changed in a version, from the thing's detail or the stream; `nil` if it's older than
    /// both hold.
    public func change(_ motion: MotionID, version: Int) -> MotionChange? {
        details[motion]?.changes.first { $0.version == version }
            ?? heard[motion]?.last { $0.version == version }
    }

    private func saveDismissed() {
        defaults.set(
            Dictionary(uniqueKeysWithValues: dismissed.map { ($0.key.rawValue, $0.value) }),
            forKey: Self.dismissedKey)
    }

    /// Going on first, then done, each most recently changed first.
    private static func ordered(_ motions: [Motion]) -> [Motion] {
        motions.sorted { a, b in
            if (a.status == .done) != (b.status == .done) { return b.status == .done }
            return a.changedAt.date > b.changedAt.date
        }
    }
}
