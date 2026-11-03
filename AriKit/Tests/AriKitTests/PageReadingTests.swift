import AriKit
import Foundation
import Testing

@Suite("Reading a page")
struct PageReadingTests {
    private func text(_ block: ReplyDocument.Block) -> String { block.runs.map(\.text).joined() }

    @Test("a freshness stamp leaves its sentence and ends the paragraph, quietly")
    func stamps() throws {
        let document = ReplyDocument(
            markdown: "A marathon is a possibility, not a plan (as of 21 Oct). Rimini is unknown."
        ).quietingStamps()
        let block = try #require(document.blocks.first)
        #expect(
            text(block)
                == "A marathon is a possibility, not a plan. Rimini is unknown.  as\u{00A0}of\u{00A0}21\u{00A0}Oct"
        )
        #expect(block.runs.last?.style == .stamp)
    }

    @Test("names link to their pages once, longest first, and never inside headings or links")
    func names() throws {
        let leo = try #require(URL(string: "ari-page:memory:people/leo"))
        let ali = try #require(URL(string: "ari-page:memory:people/ali"))
        let wilson = try #require(URL(string: "ari-page:memory:people/ali-wilson"))
        let document = ReplyDocument(
            markdown:
                "## Leo\n\nYou paced leo to a sub-two; Leo was thrilled. Ali Wilson sent [Ali](https://x.y) a CV."
        ).linking([(["Leo"], leo), (["Ali"], ali), (["Ali Wilson"], wilson)])
        #expect(document.blocks[0].runs.allSatisfy { $0.link == nil }, "not in a heading")
        let linked = document.blocks[1].runs.filter { $0.link != nil }
        #expect(linked.map(\.text) == ["leo", "Ali Wilson", "Ali"])
        #expect(linked.map(\.link) == [leo, wilson, URL(string: "https://x.y")])
        #expect(
            text(document.blocks[1])
                == "You paced leo to a sub-two; Leo was thrilled. Ali Wilson sent Ali a CV.")
    }

    @Test("a page links once, by whichever of its names comes first")
    func aliases() throws {
        let mira = try #require(URL(string: "ari-page:memory:people/mira"))
        let document = ReplyDocument(markdown: "Mimi booked Florence. Mira is thrilled.")
            .linking([(["Mira", "Mimi"], mira)])
        let linked = document.blocks[0].runs.filter { $0.link != nil }
        #expect(linked.map(\.text) == ["Mimi"], "once, at the first mention")
    }

    private func page(_ markdown: String, photos: [MemoryPhoto]) throws -> MemoryPage {
        MemoryPage(
            address: PageAddress("memory:journal/2026-11-03"), title: "3 November 2026",
            shelf: "journal", changedAt: try #require(Timestamp("2026-11-03T18:30:00.000Z")),
            markdown: markdown, photos: photos)
    }

    private func words(_ piece: PagePiece) -> [String] {
        guard case .words(let document) = piece else { return [] }
        return document.blocks.map(text)
    }

    @Test("a photo memory keeps stands where the story shows it, in its words' place")
    func photos() throws {
        let river = MemoryPhoto(
            source: "../media/3f9a1c2b4d5e6f70.jpg", name: "3f9a1c2b4d5e6f70.jpg", width: 1333,
            height: 2000)
        let page = try page(
            "### 18:30\n\nA long walk by the river.\n\n![Mira by the river](../media/3f9a1c2b4d5e6f70.jpg)"
                + "\n\n> ![Mira again](../media/3f9a1c2b4d5e6f70.jpg)\n\nHome by eight.",
            photos: [river])
        let pieces = ReplyDocument.pieces(of: page, reading: ReplyDocument(markdown: page.markdown))
        #expect(pieces.count == 3)
        #expect(words(pieces[0]) == ["18:30", "A long walk by the river."])
        guard case .photos(let shown) = pieces[1] else {
            Issue.record("the photos come second")
            return
        }
        #expect(shown.map(\.alt) == ["Mira by the river", "Mira again"])
        #expect(shown.map(\.photo) == [river, river])
        #expect(shown.map(\.id) == [0, 1])
        #expect(words(pieces[2]) == ["Home by eight."])
    }

    @Test("a photo amid words follows its paragraph, and an image on the web stays as words")
    func photosAmidWords() throws {
        let river = MemoryPhoto(
            source: "../media/3f9a1c2b4d5e6f70.jpg", name: "3f9a1c2b4d5e6f70.jpg")
        let page = try page(
            "We walked ![Mira](../media/3f9a1c2b4d5e6f70.jpg) to Piran.\n\n"
                + "![The harbour](https://example.com/piran.jpg)",
            photos: [river])
        let pieces = ReplyDocument.pieces(of: page, reading: ReplyDocument(markdown: page.markdown))
        #expect(pieces.count == 3)
        #expect(words(pieces[0]) == ["We walked Mira to Piran."])
        #expect(pieces[1] == .photos([PagePhoto(photo: river, alt: "Mira", id: 0)]))
        #expect(words(pieces[2]) == ["The harbour"])
    }

    @Test("a page without photos is its words, as they were")
    func noPhotos() throws {
        let page = try page("Your oldest friend (as of 3 Nov).", photos: [])
        let reading = ReplyDocument(markdown: page.markdown).quietingStamps()
        #expect(ReplyDocument.pieces(of: page, reading: reading) == [.words(reading)])
    }
}
