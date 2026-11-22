import AriKit
import Foundation
import Testing

/// Pages Kumo makes: the shelf, a page with its ticks, how the store follows the stream, and how a
/// page reads and shares.
@Suite("Pages Kumo makes")
@MainActor
struct MadeTests {
    private let guide: MadeID = "va-guide"

    @Test(
        "Scenario 91: the app opens the page, ticks two things off, sees Kumo's change, and lists the shelf"
    )
    func aPageKumoMade() async throws {
        let transcript = try Fixtures.transcript("91-a-page-kumo-made")
        let server = TranscriptServer(transcript, only: Self.madeRoutes)

        let first = try await server.client.madePage(guide)
        #expect(first.made.title == "Your guide to the V&A")
        #expect(first.made.cover?.credit == "Photo by A. Example, CC BY-SA 4.0")
        #expect(first.made.forDay == "2026-11-22")
        #expect(first.content.check == "Spotted")
        #expect(
            first.content.sections.map(\.id) == ["cast-courts", "south-asia", "fashion", "halfway"])
        #expect(first.content.sections.last?.numbered == false)
        #expect(MadeReading.progressLine(first.content, state: first.state) == "0 of 4 spotted")
        #expect(
            MadeReading.latestChange(first) == nil,
            "a page Kumo hasn't changed says Made, not Updated")
        #expect(MadeReading.openAtFirst(first.content) == ["cast-courts"])

        let spotted = try #require(Timestamp("2026-11-22T14:32:00.000Z"))
        let once = try await server.client.tick(guide, item: "trajans-column", at: spotted)
        #expect(once.ticks == ["trajans-column": spotted])
        let figLeaf = try #require(Timestamp("2026-11-22T14:38:00.000Z"))
        let twice = try await server.client.tick(guide, item: "fig-leaf", at: figLeaf)
        #expect(twice.ticks.count == 2)

        let changed = try await server.client.madePage(guide)
        #expect(changed.made.version == 2)
        let cartoons = try #require(changed.content.sections.first { $0.id == "raphael-cartoons" })
        #expect(cartoons.badge == "Back in")
        #expect(
            MadeReading.latestChange(changed)?.note
                == "The Raphael Cartoons reopened this morning, so they're back in.")
        #expect(MadeReading.progressLine(changed.content, state: changed.state) == "2 of 5 spotted")
        let castCourts = try #require(changed.content.sections.first)
        #expect(
            MadeReading.progress(of: castCourts, in: changed.content, state: changed.state)! == (
                2, 2
            ))

        let shelf = try await server.client.madePages()
        #expect(shelf.made.map(\.id) == [guide])
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("the store follows the stream: a page made, changed and ticked on another device")
    func followsTheStream() async throws {
        let transcript = try Fixtures.transcript("91-a-page-kumo-made")
        let server = TranscriptServer(transcript, only: Self.madeRoutes)
        let pages = MadePages(client: server.client)
        let events = transcript.events.map(\.event)
        let made = try #require(
            events.firstIndex {
                if case .madeCreated = $0.payload { true } else { false }
            })
        for event in events[...made] { pages.apply(event) }
        #expect(pages.all.map(\.id) == [guide])
        #expect(pages[guide]?.version == 1)

        // Opening it fetches it; Kumo's change then fetches it again by itself.
        _ = try await pages.detail(guide)
        for event in events[(made + 1)...] { pages.apply(event) }
        #expect(pages[guide]?.version == 2)
        #expect(pages.details[guide]?.state.ticks.count == 2, "ticks from another device show")
    }

    @Test("a forgotten page leaves the shelf, and its cards can say so")
    func forgotten() throws {
        let pages = MadePages(client: try Self.offline())
        let at = try #require(Timestamp("2026-11-21T18:10:15.000Z"))
        let page = Made(id: guide, title: "Your guide to the V&A", summary: "", madeAt: at)
        pages.apply(Event(json: Self.event("made.created", made: page)))
        #expect(pages.all.count == 1)
        pages.apply(
            Event(
                json:
                    #"{"id":"e_9","type":"made.removed","at":"2026-11-22T09:00:00.000Z","made":"va-guide"}"#
            ))
        #expect(pages.all.isEmpty)
        #expect(pages.forgotten.contains(guide))
    }

    @Test("a page shares as clean text: its parts, what's ticked, and its pictures' credits")
    func shares() throws {
        let photo = Photo(
            attachment: "f_1", alt: "The dome", sourceURL: URL(string: "https://example.org/dome")!,
            credit: "A. Example")
        let detail = MadeDetail(
            made: Made(
                id: guide, title: "Your guide to the V&A", summary: "2 rooms", cover: photo,
                madeAt: try #require(Timestamp("2026-11-21T18:10:15.000Z"))),
            content: MadeContent(
                intro: "Two rooms.\n\n```ari:place\n{\"name\":\"The V&A\"}\n```",
                check: "Spotted",
                sections: [
                    MadeSection(
                        id: "casts", title: "Cast Courts", detail: "25 min",
                        items: [
                            MadeItem(
                                id: "column", title: "Trajan's Column", detail: "Find the join."),
                            MadeItem(id: "leaf", title: "The fig leaf"),
                        ]),
                    MadeSection(id: "halfway", title: "Halfway", numbered: false, text: "Coffee."),
                ]),
            state: MadeState(ticks: ["column": try #require(Timestamp("2026-11-22T14:32:00.000Z"))])
        )

        #expect(
            MadeReading.shareText(detail) == """
                Your guide to the V&A
                2 rooms

                Two rooms.

                1. Cast Courts (25 min)
                [x] Trajan's Column: Find the join.
                [ ] The fig leaf

                HALFWAY
                Coffee.

                Pictures: A. Example, https://example.org/dome
                """)
        #expect(MadeReading.ask(detail.content) == "Spotted it?")
    }

    @Test("names in a reply: memory, things in motion and made pages, not the web")
    func names() throws {
        #expect(
            NameLink(URL(string: "memory:people/maya-lind")!) == .memory("memory:people/maya-lind"))
        #expect(NameLink(URL(string: "motion:lisbon-weekend")!) == .motion("lisbon-weekend"))
        #expect(NameLink(URL(string: "made:va-guide")!) == .made("va-guide"))
        #expect(NameLink(URL(string: "https://example.org")!) == nil)
        #expect(NameLink.isName(URL(string: "made:va-guide")!))
        let document = ReplyDocument(markdown: "Say hi to [Maya](memory:people/maya-lind).")
        let link = try #require(document.blocks.first?.runs.compactMap(\.link).first)
        #expect(NameLink(link) == .memory("memory:people/maya-lind"))
    }

    @Test("a draft reads as Mail shows it, without Markdown's marks")
    func draftWords() {
        let body = """
            # Thursday
            Works for me! Two things:
            - **7:30** at Saffron Lane
            - I'll book
            ![the menu](uploads/menu.jpg)
            > see you there
            """
        #expect(
            DraftReading.readable(body) == """
                **Thursday**
                Works for me! Two things:
                • **7:30** at Saffron Lane
                • I'll book
                see you there
                """)
    }

    private nonisolated static func madeRoutes(_ route: Route) -> Bool {
        switch route {
        case .madePages, .madePage, .madeState: true
        default: false
        }
    }

    private static func offline() throws -> ItoClient {
        ItoClient(
            address: try ServerAddress("http://127.0.0.1:8787"), token: Token("t"),
            transport: TranscriptServer(try Fixtures.transcript("91-a-page-kumo-made")) { _ in false
            })
    }

    private static func event(_ type: String, made: Made) -> String {
        """
        {"id":"e_1","type":"\(type)","at":"\(made.madeAt)","made":{"id":"\(made.id)","title":"\(made.title)",\
        "summary":"","version":\(made.version),"made_at":"\(made.madeAt)","changed_at":"\(made.changedAt)",\
        "position":1},"change":{"version":1,"at":"\(made.madeAt)","note":"Made it","position":1}}
        """
    }
}

extension Event {
    fileprivate init(json: String) {
        self = try! JSONDecoder().decode(Event.self, from: Data(json.utf8))
    }
}
