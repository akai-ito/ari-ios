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

    @Test("plays transcript 57: Ari's notes on what changed, the journal by headline, named links")
    func learntLately() async throws {
        let transcript = try Fixtures.transcript("57-what-ari-learnt-lately")
        let server = TranscriptServer(
            transcript, only: { [.memoryRecent, .memoryPages, .memoryPage].contains($0) })
        let recent = try await server.client.recentChanges()
        #expect(recent.changes.first?.note == "Florence with Mira")
        #expect(recent.changes.first?.title == "27 October 2026")
        let journal = try await server.client.pages(on: "journal")
        #expect(journal.pages.first?.gist == "Florence planned with Mira")
        let people = try await server.client.pages(on: "people")
        #expect(people.pages.first?.circle == "friends")
        let trip = try await server.client.page("memory:projects/florence-trip")
        #expect(trip.gist == "With Mira, 6–9 November; nothing booked yet")
        #expect(
            trip.links == [
                MemoryLink(address: "memory:people/mira", title: "Mira", aliases: ["Mimi"])
            ])
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("names a link readably from its address alone")
    func plainNames() {
        #expect(PageAddress("memory:places/lisbon-trip").plainName == "Lisbon trip")
        #expect(PageAddress("memory:now").plainName == "Now")
        #expect(!PageAddress.pastConversations.isPage)
    }

    @Test("a page's photos come by name, once, and a page without them has none")
    func photos() async throws {
        let json = #"""
            {"address": "memory:journal/2026-11-03", "title": "3 November 2026", "shelf": "journal",
             "aliases": [], "links": [], "changed_at": "2026-11-03T18:30:00.000Z",
             "markdown": "![Mira by the river](../media/3f9a1c2b4d5e6f70.jpg)\n",
             "photos": [{"source": "../media/3f9a1c2b4d5e6f70.jpg", "name": "3f9a1c2b4d5e6f70.jpg",
                         "width": 1333, "height": 2000}]}
            """#
        let page = try JSONDecoder().decode(MemoryPage.self, from: Data(json.utf8))
        let plain = try JSONDecoder().decode(
            MemoryPage.self,
            from: Data(json.replacing(#/,\s*"photos"[\s\S]*\]/#, with: "").utf8))
        let photo = MemoryPhoto(
            source: "../media/3f9a1c2b4d5e6f70.jpg", name: "3f9a1c2b4d5e6f70.jpg", width: 1333,
            height: 2000)
        #expect(page.photos == [photo])
        #expect(plain.photos.isEmpty)

        let server = PhotoServer(bytes: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let memory = Memory(
            client: ItoClient(
                address: try ServerAddress("https://studio.example"),
                token: Token("ito_example_not_a_real_token_00000000000000000000"),
                transport: server))
        #expect(await memory.photo(photo) == Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(await memory.photo(photo) == Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(await server.paths == ["/v0/memory/media/3f9a1c2b4d5e6f70.jpg"])
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
            case .memoryRecent: _ = try await client.recentChanges()
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

/// Answers every request with the same photo, and remembers what it was asked for.
private actor PhotoServer: Transport {
    private(set) var paths: [String] = []
    private let bytes: Data

    init(bytes: Data) {
        self.bytes = bytes
    }

    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        paths.append(request.path)
        return HTTPResponse(status: 200, headers: ["content-type": "image/jpeg"], body: bytes)
    }

    func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
        throw URLError(.badServerResponse)
    }
}
