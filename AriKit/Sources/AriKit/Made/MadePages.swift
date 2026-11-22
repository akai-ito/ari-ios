import Foundation
import Observation

/// The pages Kumo made, for the Made shelf, their cards in the chat and the page itself. The
/// session hands it every made event; it fetches a page's content again when Kumo changes it. A
/// refresh that fails keeps what was shown.
@MainActor
@Observable
public final class MadePages {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    /// Every page, most recently changed first, as the server lists them.
    public private(set) var all: [Made] = []
    /// Each page's content, ticks and what changed, once fetched.
    public private(set) var details: [MadeID: MadeDetail] = [:]
    /// Pages Kumo forgot while this ran: their cards say so rather than wait to load.
    public private(set) var forgotten: Set<MadeID> = []
    public private(set) var load = Load.loading
    /// The files Kumo showed you for review, such as a CV, newest change first: documents on the
    /// shelf beside the pages.
    public private(set) var documents: [ShownFile] = []
    /// The names of the threads pages were made in, once asked for.
    public private(set) var threadNames: [ThreadID: String] = [:]

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// How many things the shelf holds: the pages and the documents.
    public var shelfCount: Int { all.count + documents.count }

    public subscript(id: MadeID) -> Made? {
        all.first { $0.id == id } ?? details[id]?.made
    }

    /// Asks for the shelf: the pages, and the documents beside them.
    public func refresh() async {
        async let files = try? client.files()
        do {
            all = Self.ordered(try await client.madePages().made)
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(RequestError(error)) }
        }
        if let files = await files { documents = files }
    }

    /// The name of the thread a page was made in, as "From your thread" says it: asked for once,
    /// then kept. `nil` while it has none yet, or the server can't say.
    public func threadName(_ thread: ThreadID) async -> String? {
        if let known = threadNames[thread] { return known }
        guard let title = try? await client.thread(thread).thread.title else { return nil }
        threadNames[thread] = title
        return title
    }

    /// Fetches a page's content, ticks and what changed, and keeps them.
    @discardableResult
    public func detail(_ id: MadeID) async throws(RequestError) -> MadeDetail {
        do {
            let fetched = try await client.madePage(id)
            // Two changes close together fetch twice: an older answer arriving last never wins.
            if let kept = details[id], kept.made.version > fetched.made.version { return kept }
            details[id] = fetched
            forgotten.remove(id)
            return fetched
        } catch {
            if error.status == 404 { forgotten.insert(id) }
            throw error
        }
    }

    /// Follows the stream: Kumo making or changing a page, your ticks on any device, and a page
    /// forgotten. A snapshot means events may have been missed, so it asks again.
    public func apply(_ event: Event) {
        switch event.payload {
        case .snapshot:
            Task { await refresh() }
        case .madeCreated(let event), .madeChanged(let event):
            all.removeAll { $0.id == event.made.id }
            all = Self.ordered(all + [event.made])
            forgotten.remove(event.made.id)
            if load != .loaded { load = .loaded }
            // A page already open follows Kumo's change at once.
            if details[event.made.id] != nil {
                let id = event.made.id
                Task { _ = try? await detail(id) }
            }
        case .madeState(let event):
            details[event.made]?.state = event.state
        case .madeRemoved(let event):
            all.removeAll { $0.id == event.made }
            details[event.made] = nil
            forgotten.insert(event.made)
        default:
            break
        }
    }

    /// Ticks an item off now, or takes the tick back, at once on screen: `false` if the server
    /// didn't take it, and the tick goes back.
    public func tick(_ made: MadeID, item: String, done: Bool, at now: Date = .now) async -> Bool {
        let before = details[made]?.state
        let time = done ? Timestamp(now) : nil
        details[made]?.state.ticks[item] = time
        do {
            let state = try await client.tick(made, item: item, at: time)
            details[made]?.state = state
            return true
        } catch {
            if let before { details[made]?.state = before }
            return false
        }
    }

    private static func ordered(_ pages: [Made]) -> [Made] {
        pages.sorted { $0.changedAt.date > $1.changedAt.date }
    }
}
