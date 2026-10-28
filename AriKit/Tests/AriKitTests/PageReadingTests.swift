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
        let bora = try #require(URL(string: "ari-page:memory:people/bora"))
        let ali = try #require(URL(string: "ari-page:memory:people/ali"))
        let wilson = try #require(URL(string: "ari-page:memory:people/ali-wilson"))
        let document = ReplyDocument(
            markdown:
                "## Bora\n\nYou paced bora to a sub-two; Bora was thrilled. Ali Wilson sent [Ali](https://x.y) a CV."
        ).linking([("Bora", bora), ("Ali", ali), ("Ali Wilson", wilson)])
        #expect(document.blocks[0].runs.allSatisfy { $0.link == nil }, "not in a heading")
        let linked = document.blocks[1].runs.filter { $0.link != nil }
        #expect(linked.map(\.text) == ["bora", "Ali Wilson", "Ali"])
        #expect(linked.map(\.link) == [bora, wilson, URL(string: "https://x.y")])
        #expect(
            text(document.blocks[1])
                == "You paced bora to a sub-two; Bora was thrilled. Ali Wilson sent Ali a CV.")
    }
}
