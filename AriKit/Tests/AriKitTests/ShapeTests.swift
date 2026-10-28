import AriKit
import Foundation
import Testing

/// Replies shaped by what they are: the `ari:` blocks Ari draws natively, and a plan's ticks.
@MainActor
@Suite("Shaped replies")
struct ShapeTests {
    @Test(
        "Scenario 59: a plan, a time and a place, each its own part, and a tick every device sees")
    func plan() throws {
        var replay = Replay(try Fixtures.transcript("59-a-plan-you-can-tick"))
        try replay.play()
        let reply = try #require(replay.conversation["m_0001_87815"])
        let shapes = ReplyDocument(markdown: reply.text).shapes.sorted { $0.key < $1.key }.map(
            \.value)
        #expect(shapes.map(\.part) == [0, 1, 2])
        guard case .plan(let plan) = shapes[0].shape, case .time(let time) = shapes[1].shape,
            case .place(let place) = shapes[2].shape
        else {
            Issue.record("the blocks didn't read as a plan, a time and a place")
            return
        }
        #expect(plan.title == "Florence")
        #expect(plan.items.map(\.id) == ["book-uffizi", "duomo-climb", "siena"])
        #expect(time.timezone == "Europe/Rome" && !time.isAllDay)
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rome
        let start = try #require(time.dates?.start)
        #expect(calendar.component(.hour, from: start) == 8)
        #expect(calendar.component(.minute, from: start) == 15)
        #expect(place.name == "Uffizi Gallery" && place.lat == 43.7678)
        #expect(reply.ticks == [Tick(part: 0, item: "book-uffizi", done: true)])
    }

    @Test("Scenario 60: pictures Ari found, kept as attachments with their credit")
    func images() throws {
        var replay = Replay(try Fixtures.transcript("60-pictures-ari-found"))
        try replay.play()
        let reply = try #require(replay.conversation["m_0001_68134"])
        guard
            case .images(let images) = ReplyDocument(markdown: reply.text).shapes.first?.value.shape
        else {
            Issue.record("the block didn't read as pictures")
            return
        }
        #expect(images.images.first?.attachment == "f_0001_06924")
        #expect(images.images.first?.credit == "Photo by M. Rossi, CC BY-SA 4.0")
    }

    @Test("a comparison keeps its facts in the order Ari wrote them")
    func compare() {
        let json = #"""
            {"options":[{"name":"Rimini","facts":{"When":"April","Flat":"Yes","Odds":"Lottery"}},
            {"name":"Valencia","facts":{"When":"December","Flat":"Very","Odds":"Open"}}],
            "pick":"Valencia"}
            """#
        guard case .compare(let compare) = ReplyShape(language: "ari:compare", json: json) else {
            Issue.record("didn't read as a comparison")
            return
        }
        #expect(
            compare.options.map { $0.facts.map(\.key) } == [
                ["When", "Flat", "Odds"], ["When", "Flat", "Odds"],
            ])
        #expect(compare.pick == "Valencia")
    }

    @Test("a block Ari doesn't know, or can't read, has no shape but still counts as a part")
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
            """
        let shapes = ReplyDocument(markdown: markdown).shapes.sorted { $0.key < $1.key }.map(
            \.value)
        #expect(shapes.map(\.part) == [0, 1, 2])
        #expect(shapes[0].shape == nil && shapes[2].shape == nil)
        if case .plan = shapes[1].shape {} else { Issue.record("the plan didn't read") }
    }

    @Test("what's said aloud leaves the blocks out")
    func spoken() {
        let markdown = "Here's the plan.\n\n```ari:plan\n{\"items\":[]}\n```\n\nEnjoy it."
        let said = ReplyDocument(markdown: markdown).withoutShapes.plainText
        #expect(!said.contains("ari:") && !said.contains("items"))
        #expect(said.contains("Here's the plan.") && said.contains("Enjoy it."))
    }
}
