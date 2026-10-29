import AriKit
import Foundation
import Testing

@Suite("Laying out a shelf")
struct ShelfReadingTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func page(_ name: String, minutesAgo: Double) -> PageSummary {
        PageSummary(
            address: PageAddress("memory:people/\(name.lowercased())"), title: name,
            changedAt: Timestamp(now.addingTimeInterval(-minutesAgo * 60).formatted(.iso8601)))
    }

    @Test("an import isn't lately: only what changed since, newest first")
    func lately() {
        // Eight pages imported together three days ago, then Ari touched two of them.
        var pages = (0..<8).map { page("Person\($0)", minutesAgo: 3 * 1_440 + Double($0)) }
        #expect(ShelfReading.lately(pages, now: now).isEmpty, "the import alone says nothing")
        pages[2] = page("Janki", minutesAgo: 30)
        pages[5] = page("Bora", minutesAgo: 600)
        #expect(ShelfReading.lately(pages, now: now).map(\.title) == ["Janki", "Bora"])
    }

    @Test("lately is the last two weeks, at most five, and only when it stands out")
    func window() {
        let pages = (0..<16).map { page("P\($0)", minutesAgo: Double($0) * 2 * 1_440) }
        #expect(
            ShelfReading.lately(pages, now: now).map(\.title) == ["P0", "P1", "P2", "P3", "P4"])
        let old = (0..<3).map { page("Old\($0)", minutesAgo: 20 * 1_440 + Double($0) * 1_440) }
        #expect(ShelfReading.lately(old, now: now).isEmpty)
        // Most of a small shelf changed lately: nothing stands out.
        let few = (0..<4).map { page("F\($0)", minutesAgo: Double($0) * 1_440) }
        #expect(ShelfReading.lately(few, now: now).isEmpty)
    }

    @Test("everyone reads A to Z, numbers in order")
    func everyone() {
        let pages = ["bora", "Ali Wilson", "Andrei", "page 10", "page 9"].map {
            page($0, minutesAgo: 1)
        }
        #expect(
            ShelfReading.everyone(pages).map(\.title) == [
                "Ali Wilson", "Andrei", "bora", "page 9", "page 10",
            ])
    }

    @Test("people group by circle, closest first, those without one last")
    func circles() {
        let people = [
            ("Bora", "friends"), ("Mum", "family"), ("Poppy Walton", "work"), ("Janki", "partner"),
            ("Ayush", "friends"), ("Coach", "running"), ("Niwi", nil),
        ].map {
            PageSummary(address: PageAddress("memory:people/\($0.0)"), title: $0.0, circle: $0.1)
        }
        let circles = ShelfReading.circles(people)
        #expect(circles.map(\.circle) == ["partner", "family", "friends", "work", "running", nil])
        #expect(circles[2].pages.map(\.title) == ["Ayush", "Bora"])
    }

    @Test("journal days group by month, newest first")
    func months() {
        let days = ["2026-10-26", "2026-09-11", "2026-10-24", "2026-09-12"].map {
            PageSummary(address: PageAddress("memory:journal/\($0)"), title: $0)
        }
        let months = ShelfReading.months(days)
        #expect(months.map(\.month) == [10, 9])
        #expect(months[0].days.map(\.day) == [26, 24])
        #expect(months[1].days.map(\.day) == [12, 11])
    }
}
