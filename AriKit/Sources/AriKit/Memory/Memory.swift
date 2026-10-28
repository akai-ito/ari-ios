import Foundation
import Observation

/// What the Library's Memory and *In mind* show of what Ari knows. Read-only: Ari writes every
/// page, and you see what it wrote and what it uses. A refresh that fails keeps what was shown.
@MainActor
@Observable
public final class Memory {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    /// Portrait, Now and How to help you, in full.
    public private(set) var inMind: [MemoryPage] = []
    /// What Ari changed lately, newest first, with its notes.
    public private(set) var recent: [RecentChange] = []
    public private(set) var shelves: [Shelf] = []
    /// Each shelf's pages, most recently changed first, as of the last refresh.
    public private(set) var shelfPages: [String: [PageSummary]] = [:]
    public private(set) var load = Load.loading

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// Asks for In mind, the recent changes and the shelves together.
    public func refresh() async {
        async let mind = client.inMind()
        async let changed = client.recentChanges()
        async let counts = client.shelves()
        do {
            (inMind, recent, shelves) = try await (mind.pages, changed.changes, counts.shelves)
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(RequestError(error)) }
            return
        }
        // Every shelf's pages, for a peek at what's on each. A shelf that fails keeps what it had.
        let client = client
        await withTaskGroup(of: (String, [PageSummary]?).self) { group in
            for shelf in shelves.map(\.shelf) {
                group.addTask { (shelf, try? await client.pages(on: shelf).pages) }
            }
            for await (shelf, pages) in group {
                if let pages { shelfPages[shelf] = pages }
            }
        }
    }

    public func pages(on shelf: String) async throws(RequestError) -> [PageSummary] {
        try await client.pages(on: shelf).pages
    }

    public func page(_ address: PageAddress) async throws(RequestError) -> MemoryPage {
        try await client.page(address)
    }

    public func change(_ change: String) async throws(RequestError) -> PageChange {
        try await client.change(change)
    }

}
