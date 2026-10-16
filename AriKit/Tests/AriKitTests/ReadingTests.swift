import AriKit
import Foundation
import Testing

@Suite("Reading a reply's Markdown")
struct ReplyDocumentTests {
    @Test("every run of every reply in the transcripts starts where its text is in the source")
    func runsMapToTheSource() throws {
        var replies: [String] = []
        for transcript in try Fixtures.transcripts() {
            var texts: [MessageID: String] = [:]
            for logged in transcript.events {
                switch logged.event.payload {
                case .messageStarted(let started): texts[started.message.id] = started.message.text
                case .messageDelta(let delta): texts[delta.message, default: ""] += delta.text
                default: break
                }
            }
            replies += texts.values
        }
        #expect(replies.count > 20)
        for reply in replies {
            let source = Array(reply.utf16)
            for block in ReplyDocument(markdown: reply).blocks {
                for run in block.runs where run.text != " " && run.text != "\n" {
                    let units = Array(run.text.utf16)
                    let end = run.start + units.count
                    #expect(
                        end <= source.count && Array(source[run.start..<end]) == units,
                        "\"\(run.text)\" isn't at \(run.start) in \(reply.debugDescription)")
                }
            }
        }
    }

    @Test("paragraphs, list items with their markers, and bold")
    func lists() {
        let blocks = ReplyDocument(
            markdown:
                "Here's a shape:\n\n- **07:30** Long run.\n- **10:00** Breakfast.\n\nEarly night."
        ).blocks
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph, .paragraph, .paragraph])
        #expect(blocks.map(\.marker) == [nil, "•", "•", nil])
        #expect(blocks.map(\.depth) == [0, 1, 1, 0])
        #expect(blocks[1].runs.first?.text == "07:30")
        #expect(blocks[1].runs.first?.style == .strong)
    }

    @Test("as plain text: no Markdown, paragraphs apart, list items under their markers")
    func plainText() {
        let document = ReplyDocument(
            markdown:
                "Here's a **shape**:\n\n- **07:30** Long run.\n- See [the map](https://example.com)."
                + "\n\nEarly night.")
        #expect(
            document.plainText
                == "Here's a shape:\n\n• 07:30 Long run.\n• See the map.\n\nEarly night.")
    }

    @Test("a code block, its language and inline code")
    func code() {
        let source = """
            Run this in Terminal:

            ```sh
            lsof -nP -iTCP:8080 -sTCP:LISTEN
            ```

            The second column is the process ID; `kill <PID>` stops it.
            """
        let blocks = ReplyDocument(markdown: source).blocks
        #expect(blocks.count == 3)
        #expect(blocks[1].kind == .code(language: "sh"))
        #expect(blocks[1].runs.first?.text == "lsof -nP -iTCP:8080 -sTCP:LISTEN")
        #expect(blocks[1].start == offset(of: "lsof", in: source))
        let inline = blocks[2].runs.first { $0.style.contains(.code) }
        #expect(inline?.text == "kill <PID>")
        #expect(inline?.start == offset(of: "kill", in: source))
    }

    @Test("a bold span or code still arriving shows no markers")
    func arriving() {
        let bold = ReplyDocument(markdown: "Here's a shape:\n\n- **07:3").blocks.last?.runs
        #expect(bold?.map(\.text) == ["07:3"])
        #expect(bold?.first?.style == .strong)
        let code = ReplyDocument(markdown: "Then run `lsof -nP").blocks.last?.runs
        #expect(code?.last?.text == "lsof -nP")
        let fence = ReplyDocument(markdown: "Run:\n\n```sh\nlsof -nP").blocks.last
        #expect(fence?.kind == .code(language: "sh"))
        #expect(fence?.runs.first?.text == "lsof -nP")
    }

    @Test(
        "a table reads as one block per row: its first cell bold, each other cell on its own line")
    func table() {
        let source = """
            Here are two:

            | Café | Where | Why |
            | --- | --- | --- |
            | **Prufrock Coffee** | 23–25 Leather Lane | Coffee first |
            | WatchHouse | Seven Dials | Brunch |
            """
        let blocks = ReplyDocument(markdown: source).blocks
        #expect(blocks.count == 3)
        #expect(
            blocks[1].runs.map(\.text) == [
                "Prufrock Coffee", "\n", "23–25 Leather Lane", "\n", "Coffee first",
            ])
        #expect(blocks[1].runs.first?.style == .strong)
        #expect(blocks[2].runs.first?.text == "WatchHouse")
        #expect(blocks[2].runs.first?.style == .strong)
        #expect(!blocks.contains { $0.runs.contains { $0.text == "Café" } })
    }

    @Test("offsets count UTF-16 units, past emoji; numbered and nested lists; links")
    func offsetsAndStructure() {
        #expect(ReplyDocument(markdown: "🚲 **bike**").blocks.first?.runs.last?.start == 5)
        let blocks = ReplyDocument(
            markdown: "1. First\n2. Second\n   - inner\n\nSee [the docs](https://example.com)."
        ).blocks
        #expect(blocks.map(\.marker) == ["1.", "2.", "•", nil])
        #expect(blocks.map(\.depth) == [1, 1, 2, 0])
        let link = blocks.last?.runs.first { $0.link != nil }
        #expect(link?.text == "the docs")
        #expect(link?.link == URL(string: "https://example.com"))
    }

    private func offset(of text: String, in source: String) -> Int? {
        source.range(of: text).map {
            source.utf16.distance(from: source.startIndex, to: $0.lowerBound)
        }
    }
}

@Suite("The reading pace")
struct RevealTests {
    private let now = Date(timeIntervalSince1970: 1_791_900_000)

    @Test("a reply arrives at a steady reading pace while the screen keeps up")
    func steady() throws {
        let conversation = try Story(now: now).reply("m_1", String(repeating: "a", count: 60))
            .build()
        var reveal = Reveal()
        let entry = try #require(conversation["m_1"])
        #expect(reveal.position(of: entry, at: now) == 0)
        reveal.advance(by: 0.5, in: conversation, at: now)
        #expect(reveal.position(of: entry, at: now) == 30)
        #expect(reveal.isRevealing(conversation, at: now))
    }

    @Test("far behind, it catches up, so the screen is never more than a second or two back")
    func catchesUp() throws {
        let conversation = try Story(now: now).reply("m_1", String(repeating: "a", count: 600))
            .build()
        var reveal = Reveal()
        let entry = try #require(conversation["m_1"])
        reveal.advance(by: 1, in: conversation, at: now)
        #expect(reveal.position(of: entry, at: now) == 400)
        reveal.advance(by: 1, in: conversation, at: now)
        reveal.advance(by: 1, in: conversation, at: now)
        #expect(600 - reveal.position(of: entry, at: now) < Reveal.pace * Reveal.catchUp)
    }

    @Test("a reply starts once the one before it is fully shown")
    func inOrder() throws {
        let conversation = try Story(now: now)
            .reply("m_1", String(repeating: "a", count: 30), ended: true)
            .reply("m_2", String(repeating: "b", count: 30))
            .build()
        var reveal = Reveal()
        reveal.advance(by: 0.5, in: conversation, at: now)
        #expect(reveal.position(of: try #require(conversation["m_1"]), at: now) == 30)
        #expect(reveal.position(of: try #require(conversation["m_2"]), at: now) == 0)
        reveal.advance(by: 0.5, in: conversation, at: now)
        #expect(reveal.position(of: try #require(conversation["m_2"]), at: now) == 30)
    }

    @Test("a reply finished long before Ari saw it shows at once; one just finished still reveals")
    func finishedEarlier() throws {
        let old = try Story(now: now.addingTimeInterval(-3600)).reply("m_1", "Done.", ended: true)
            .build()
        let recent = try Story(now: now.addingTimeInterval(-2)).reply("m_1", "Done.", ended: true)
            .build()
        #expect(Reveal().position(of: try #require(old["m_1"]), at: now) == .infinity)
        #expect(Reveal().position(of: try #require(recent["m_1"]), at: now) == 0)
        #expect(Reveal().position(of: try #require(old["u_1"]), at: now) == .infinity)
    }

    @Test("Stop names the message still being written, at how much of it is on screen")
    func stopCut() throws {
        let conversation = try Story(now: now)
            .reply("m_1", String(repeating: "a", count: 50), ended: true)
            .reply("m_2", String(repeating: "b", count: 40))
            .build()
        var lagging = Reveal()
        lagging.advance(by: 0.2, in: conversation, at: now)
        // The screen is still on the first reply, which the server has finished.
        #expect(lagging.stop(in: conversation) == Cut(message: "m_2", offset: 0))
        #expect(lagging.position(of: try #require(conversation["m_1"]), at: now) == .infinity)

        var caughtUp = Reveal()
        caughtUp.advance(by: 1.1, in: conversation, at: now)
        #expect(caughtUp.stop(in: conversation)?.offset == 16)
    }

    @Test("Stop once the turn has ended sends no cut, and the rest shows at once")
    func stopAfterTheEnd() throws {
        let conversation = try Story(now: now).reply("m_1", "All done here.", ended: true)
            .endTurn().build()
        var reveal = Reveal()
        #expect(reveal.stop(in: conversation) == nil)
        #expect(reveal.position(of: try #require(conversation["m_1"]), at: now) == .infinity)
    }
}

/// Builds a conversation from events: your message, a turn, and the agent's replies.
private struct Story {
    let at: String
    private var events: [String] = []
    private var next = 1

    init(now: Date) {
        at = ISO8601DateFormatter().string(from: now)
        add(
            #""type":"message.accepted","message":{"id":"u_1","role":"user","text":"Hi","at":"\#(at)"}"#
        )
        add(#""type":"turn.started","turn":"t_1","inputs":["u_1"]"#)
    }

    func reply(_ id: String, _ text: String, ended: Bool = false) -> Story {
        var story = self
        story.add(
            #""type":"message.started","message":{"id":"\#(id)","role":"agent","kind":"reply","turn":"t_1","text":"","at":"\#(at)"}"#
        )
        story.add(#""type":"message.delta","message":"\#(id)","offset":0,"text":"\#(text)""#)
        if ended {
            story.add(
                #""type":"message.ended","message":"\#(id)","outcome":"completed","length":\#(text.utf16.count)"#
            )
        }
        return story
    }

    func endTurn() -> Story {
        var story = self
        story.add(#""type":"turn.ended","turn":"t_1","outcome":"completed""#)
        return story
    }

    func build() throws -> Conversation {
        var conversation = Conversation()
        for json in events { conversation.apply(try JSONValue(json: json).decode(Event.self)) }
        return conversation
    }

    private mutating func add(_ body: String) {
        events.append(#"{"id":"e_\#(next)","at":"\#(at)",\#(body)}"#)
        next += 1
    }
}
