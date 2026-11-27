import Foundation
import Observation

/// Kumo's dream, for the moon and sun on the Desk and the page they open: the dream time, one under
/// way, and the latest record, with each line's change to take back. The session hands it every
/// event; `dream.finished` brings a new record, and a snapshot asks again. A refresh that fails
/// keeps what was shown.
@MainActor
@Observable
public final class Dreams {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    /// The dream as the server last said; `nil` until the first answer.
    public private(set) var state: DreamState?
    public private(set) var load = Load.loading
    /// The entries in Kumo's work behind the dreams' lines, once read, for a line's why.
    public private(set) var entries: [DoneID: DoneEntry] = [:]
    /// Dream now, on its way to the server.
    public private(set) var asking = false

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// The latest dream, once there's been one.
    public var latest: Dream? { state?.latest }
    /// A dream under way, while there is one.
    public var dreaming: DreamState.Dreaming? { state?.dreaming }

    /// Asks for the dream again, such as when the Desk opens.
    public func refresh() async {
        do {
            state = try await client.dream()
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(error) }
        }
    }

    /// Kumo dreams now. It shows as under way at once; the record follows in `dream.finished`.
    public func dreamNow() async throws(RequestError) {
        asking = true
        defer { asking = false }
        state = try await client.dreamNow()
        load = .loaded
    }

    /// When Kumo dreams each night, such as `04:00`.
    public func setTime(_ time: String) async throws(RequestError) {
        state = try await client.setDreamTime(time)
        load = .loaded
    }

    /// You've seen a dream's record: the moon becomes the sun at once, and the server keeps the
    /// first time. If the server didn't take it, it's new again next time the dream is read.
    public func see(_ dream: DreamID, at now: Date = .now) async {
        guard let latest, latest.id == dream, latest.isNew else { return }
        state = state?.with(latest: .some(latest.seen(at: Timestamp(now))))
        guard let seen = try? await client.see(dream) else { return }
        if self.latest?.id == seen.id { state = state?.with(latest: .some(seen)) }
    }

    /// Takes back a line's change. The line says so at once, and the record is read again.
    @discardableResult
    public func undo(_ line: DreamLine) async throws(RequestError) -> DoneEntry? {
        guard let done = line.done else { return nil }
        let entry = try await client.undo(done)
        entries[done] = entry
        if let latest { state = state?.with(latest: .some(latest.undoing(done))) }
        await refresh()
        return entry
    }

    /// "That was wrong" on a line's change, with your words or none.
    @discardableResult
    public func correct(_ line: DreamLine, text: String?) async throws(RequestError) -> DoneEntry? {
        guard let done = line.done else { return nil }
        let entry = try await client.correct(done, text: text)
        entries[done] = entry
        await refresh()
        return entry
    }

    /// The entry in Kumo's work behind a line, read once from Done, for its why and whether it's
    /// been called wrong. `nil` for a line that changed nothing, or one Done no longer has.
    public func entry(for line: DreamLine) async -> DoneEntry? {
        guard let done = line.done else { return nil }
        if let known = entries[done] { return known }
        guard let page = try? await client.done(before: nil, limit: 50) else { return nil }
        for entry in page.entries where entry.dream != nil { entries[entry.id] = entry }
        return entries[done]
    }

    /// Follows the stream: a dream finishing brings its record; a snapshot means asking again.
    public func apply(_ event: Event) {
        switch event.payload {
        case .snapshot:
            Task { await refresh() }
        case .dreamFinished(let finished):
            if let state {
                self.state = state.with(dreaming: .some(nil), latest: .some(finished.dream))
            } else {
                Task { await refresh() }
            }
        default:
            break
        }
    }
}
