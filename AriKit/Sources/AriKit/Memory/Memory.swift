import Foundation
import Observation

/// What the Library's Memory and *In mind* show of what Ari knows. Read-only: Ari writes every
/// page, and you see what it wrote and what it uses. A refresh that fails keeps what was shown, and
/// what was shown last time shows at once, from the copy kept on the device.
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
    /// The chapters of your life Kumo noticed, those still going first.
    public private(set) var chapters: [Chapter] = []
    /// What Kumo learnt about you lately, newest first.
    public private(set) var learnt: [LearntLine] = []
    public private(set) var shelves: [Shelf] = []
    /// Each shelf's pages, most recently changed first, as of the last refresh.
    public private(set) var shelfPages: [String: [PageSummary]] = [:]
    public private(set) var load = Load.loading

    @ObservationIgnored private let client: ItoClient
    /// Photos fetched while Ari runs, by name, up to a few dozen megabytes.
    private let photos: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    public init(client: ItoClient) {
        self.client = client
        guard let mind: MemoryPages = client.kept(ItoClient.Kept.inMind),
            let counts: ShelfList = client.kept(ItoClient.Kept.shelves)
        else { return }
        inMind = mind.pages
        shelves = counts.shelves
        load = .loaded
        chapters = (client.kept(ItoClient.Kept.chapters) as ChapterList?)?.chapters ?? []
        learnt = (client.kept(ItoClient.Kept.learnt) as LearntLines?)?.lines ?? []
        for shelf in shelves.map(\.shelf) {
            shelfPages[shelf] = (client.kept(ItoClient.Kept.pages(on: shelf)) as PageList?)?.pages
        }
    }

    /// Asks for In mind, the shelves, the chapters and what Kumo learnt together. Chapters or what
    /// Kumo learnt that fail keep what they had, and leave the rest of the Library showing.
    public func refresh() async {
        async let mind = client.inMind()
        async let counts = client.shelves()
        async let noticed = try? client.chapters()
        async let learning = try? client.learnt()
        do {
            (inMind, shelves) = try await (mind.pages, counts.shelves)
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(RequestError(error)) }
            return
        }
        if let noticed = await noticed { chapters = noticed.chapters }
        if let learning = await learning { learnt = learning.lines }
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

    /// The page as it was kept the last time it opened, to show at once while it's asked for.
    public func keptPage(_ address: PageAddress) -> MemoryPage? {
        client.kept(ItoClient.Kept.page(address))
    }

    public func change(_ change: String) async throws(RequestError) -> PageChange {
        try await client.change(change)
    }

    /// A photo's bytes, kept once fetched: a photo in memory never changes under its name.
    public func photo(_ photo: MemoryPhoto) async -> Data? {
        let key = photo.name as NSString
        if let kept = photos.object(forKey: key) { return kept as Data }
        // Kept on the device once fetched, as photos never change: no need to ask again.
        var data = client.copies?.data(ItoClient.Kept.photo(photo.name))
        if data == nil { data = try? await client.memoryPhoto(photo.name) }
        guard let data else { return nil }
        photos.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

}
