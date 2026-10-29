import AriKit
import Foundation
import Testing

/// The `ari:` blocks Ari draws natively; everything else in a reply is Markdown.
@MainActor
@Suite("Shaped replies")
struct ShapeTests {
    @Test("Scenario 59: a plan as a Markdown list, a place to open, and a choice to tap")
    func blocks() throws {
        var replay = Replay(try Fixtures.transcript("59-blocks-in-a-reply"))
        try replay.play()
        let reply = try #require(replay.conversation["m_0001_24454"])
        let document = ReplyDocument(markdown: reply.text)
        #expect(document.plainText.contains("the Uffizi at 8:15"), "the plan is plain Markdown")
        let shapes = document.shapes.sorted { $0.key < $1.key }.compactMap(\.value)
        guard shapes.count == 2, case .place(let place) = shapes[0],
            case .choices(let choices) = shapes[1]
        else {
            Issue.record("the blocks didn't read as a place and choices")
            return
        }
        #expect(place.name == "Uffizi Gallery" && place.lat == 43.7678)
        #expect(choices.options.contains("Swap Siena for Pisa"))
        // The tapped choice went as your message.
        #expect(
            replay.conversation["022d1d4f-19be-4f73-8d0c-4594869ee25d"]?.text
                == "Swap Siena for Pisa")
    }

    @Test("Scenario 60: pictures Ari found, kept as attachments with their credit")
    func images() throws {
        var replay = Replay(try Fixtures.transcript("60-pictures-ari-found"))
        try replay.play()
        let reply = try #require(replay.conversation["m_0001_68134"])
        guard case .images(let images)? = ReplyDocument(markdown: reply.text).shapes.first?.value
        else {
            Issue.record("the block didn't read as pictures")
            return
        }
        #expect(images.images.first?.attachment == "f_0001_06924")
        #expect(images.images.first?.credit == "Photo by M. Rossi, CC BY-SA 4.0")
    }

    @Test("a block Ari doesn't know, or can't read, has no shape")
    func unknown() {
        let markdown = """
            ```ari:weather
            {"sky":"clear"}
            ```

            ```ari:plan
            {"items":[{"id":"a","text":"Go","done":false}]}
            ```

            ```ari:place
            {"name":
            ```

            ```ari:choices
            {"options":["Yes","No"]}
            ```
            """
        let shapes = ReplyDocument(markdown: markdown).shapes.sorted { $0.key < $1.key }.map(
            \.value)
        #expect(shapes.count == 4)
        #expect(shapes[0] == nil && shapes[1] == nil && shapes[2] == nil)
        if case .choices(let choices)? = shapes[3] {
            #expect(choices.options == ["Yes", "No"])
        } else {
            Issue.record("the choices didn't read")
        }
    }

    @Test("what's said aloud leaves the blocks out")
    func spoken() {
        let markdown = "Here's one.\n\n```ari:choices\n{\"options\":[\"Yes\"]}\n```\n\nEnjoy it."
        let said = ReplyDocument(markdown: markdown).withoutShapes.plainText
        #expect(!said.contains("ari:") && !said.contains("options"))
        #expect(said.contains("Here's one.") && said.contains("Enjoy it."))
    }
}
