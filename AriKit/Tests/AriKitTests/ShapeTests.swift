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

/// Replies that show: picks, tables with verdicts, the number that matters, and action cards.
@MainActor
@Suite("Replies that show")
struct ShowingShapeTests {
    @Test(
        "Scenario 90: a menu as a table with verdicts, picks with pictures, the total and choices")
    func aReplyThatShows() throws {
        var replay = Replay(try Fixtures.transcript("90-a-reply-that-shows"))
        try replay.play()
        let reply = try #require(replay.conversation["m_0001_30856"])
        let shapes = ReplyDocument(markdown: reply.text).shapes.sorted { $0.key < $1.key }
            .compactMap(\.value)
        guard shapes.count == 4, case .table(let table) = shapes[0],
            case .picks(let picks) = shapes[1],
            case .number(let number) = shapes[2], case .choices(let choices) = shapes[3]
        else {
            Issue.record("the blocks didn't read as a table, picks, a number and choices")
            return
        }
        #expect(table.columns == ["Dish", "My take"])
        #expect(table.rows.first?.verdict == ReplyShape.Verdict(label: "Must try", tone: .strong))
        let tones: [ReplyShape.Verdict.Tone?] = table.rows.map { $0.verdict?.tone }
        #expect(tones == [.strong, .strong, .good, .quiet, .quiet, .neutral])
        #expect(picks.title == "What I'd order")
        #expect(picks.picks.count == 5 && picks.picks.allSatisfy { $0.image != nil })
        #expect(picks.picks.first?.detail == "£9.50")
        #expect(number.value == "£47" && number.label == "Estimated for two")
        #expect(choices.options == ["Add drinks", "Lighter swap", "That's the lot"])
        // The thanks names a friend, linked to her page in memory.
        let thanks = try #require(replay.conversation["m_0002_95048"])
        let link = try #require(
            ReplyDocument(markdown: thanks.text).blocks.first?.runs.compactMap(\.link).first)
        #expect(NameLink(link) == .memory("memory:people/maya-lind"))
    }

    @Test("Scenario 91: the reply carries the page as a card")
    func madeCard() throws {
        var replay = Replay(try Fixtures.transcript("91-a-page-kumo-made"))
        try replay.play()
        let reply = try #require(replay.conversation["m_0001_42040"])
        guard case .made(let card)? = ReplyDocument(markdown: reply.text).shapes.first?.value else {
            Issue.record("the block didn't read as a page")
            return
        }
        #expect(card.made == "va-guide")
    }

    @Test("action cards: an event, a Desk item, a person and a place with Directions")
    func actionCards() throws {
        let markdown = """
            ```ari:event
            {"title":"Dinner with Theo","start":"2026-11-27T19:30:00+00:00","end":"2026-11-27T21:30:00+00:00","place":"Saffron Lane"}
            ```

            ```ari:desk
            {"card":"k_0001_00042"}
            ```

            ```ari:person
            {"page":"memory:people/maya-lind"}
            ```

            ```ari:place
            {"name":"The V&A","address":"Cromwell Road","note":"open till 17:45","image":{"attachment":"f_1","alt":"The dome","source_url":"https://example.org/dome","credit":"A. Example"}}
            ```

            ```ari:table
            {"columns":["Role"],"rows":[{"name":"Northwind","verdict":{"label":"Maybe","tone":"sparkly"}}]}
            ```
            """
        let shapes = ReplyDocument(markdown: markdown).shapes.sorted { $0.key < $1.key }.compactMap(
            \.value)
        guard shapes.count == 5, case .event(let event) = shapes[0],
            case .desk(let desk) = shapes[1],
            case .person(let person) = shapes[2], case .place(let place) = shapes[3],
            case .table(let table) = shapes[4]
        else {
            Issue.record("the blocks didn't read as action cards")
            return
        }
        #expect(event.title == "Dinner with Theo" && !event.onCalendar && !event.allDay)
        #expect(
            event.end == event.start.addingTimeInterval(2 * 3600),
            "\(event.start) \(String(describing: event.end))")
        #expect(desk.card == "k_0001_00042")
        #expect(person.page == "memory:people/maya-lind")
        #expect(place.note == "open till 17:45" && place.image?.credit == "A. Example")
        // A tone this Ari doesn't know draws as neutral.
        #expect(table.rows.first?.verdict?.tone.isKnown == false)
    }
}
