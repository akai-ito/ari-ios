import AriKit
import Foundation
import Testing

/// What the Library, In mind and the trail show of Ari's memory.
@Suite("Memory")
@MainActor
struct MemoryTests {
    @Test("a change shows the page's present, and only what newly moved to Earlier")
    func change() {
        let change = PageChange(
            change: "c_1", address: "memory:people/alex", title: "Alex",
            at: Timestamp("2026-10-26T20:10:03.500Z")!,
            before: """
                Taking things slow (as of 15 Oct).

                ## Earlier

                - 12 Oct: first date, Dishoom Shoreditch.
                """,
            after: """
                Seeing each other most days, and it's going really well (as of 26 Oct).

                ## Earlier

                - 15 Oct: decided to take things slow.
                - 12 Oct: first date, Dishoom Shoreditch.
                """)
        #expect(
            change.present
                == "Seeing each other most days, and it's going really well (as of 26 Oct).")
        #expect(change.movedToEarlier == ["- 15 Oct: decided to take things slow."])

        let created = PageChange(
            change: "c_2", address: "memory:places/lisbon", title: "Lisbon",
            at: Timestamp("2026-10-26T20:10:03.500Z")!,
            before: nil, after: "Trip on the 14th.")
        #expect(created.present == "Trip on the 14th." && created.movedToEarlier.isEmpty)
    }

    @Test("memory steps carry what they did and which pages, never the words")
    func steps() throws {
        let transcript = try Fixtures.transcript("35-ari-updates-what-it-knows")
        let steps = transcript.events.compactMap { logged -> Step? in
            switch logged.event.payload {
            case .stepStarted(let event), .stepUpdated(let event), .stepEnded(let event):
                event.step.kind == .memory ? event.step : nil
            default: nil
            }
        }
        let updated = try #require(steps.last { $0.memoryAction == .updated })
        #expect(updated.change != nil)
        #expect(updated.pages?.first?.address == "memory:people/alex")
        #expect(steps.contains { $0.memoryAction == .journaled })
    }

    @Test("names a link readably from its address alone")
    func plainNames() {
        #expect(PageAddress("memory:places/lisbon-trip").plainName == "Lisbon trip")
        #expect(PageAddress("memory:now").plainName == "Now")
        #expect(!PageAddress.pastConversations.isPage)
    }

    /// The Library's requests in the contract's transcripts, made through the real client.
    @Test(arguments: ["35-ari-updates-what-it-knows", "36-forget-that"])
    func transcripts(_ name: String) async throws {
        let transcript = try Fixtures.transcript(name)
        let server = TranscriptServer(transcript, only: { $0.isOutsideSession })
        let client = server.client
        let memory = Memory(client: client)
        for case .app(let request) in transcript.steps where request.route.isOutsideSession {
            let query = URLComponents(string: request.path)?.queryItems ?? []
            let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
            switch request.route {
            case .memoryInMind: _ = try await client.inMind()
            case .memoryShelves: _ = try await client.shelves()
            case .memoryRecent: _ = try await client.recentPages()
            case .memoryPages: _ = try await memory.pages(on: value("shelf"))
            case .memoryPage: _ = try? await memory.page(PageAddress(value("address")))
            case .memoryChange(let change): _ = try await memory.change(change)
            default: Issue.record("no action for \(request.method) \(request.path)")
            }
        }
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }
}
