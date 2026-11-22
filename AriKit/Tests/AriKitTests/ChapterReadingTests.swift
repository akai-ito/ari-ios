import AriKit
import Foundation
import Testing

@Suite("Saying a chapter's when, and what Kumo learnt")
struct ChapterReadingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    /// Saturday 21 November 2026, at noon in London.
    private let now = Timestamp("2026-11-21T12:00:00.000Z")!.date

    private func day(_ text: String) -> LocalTime { LocalTime(text)! }

    @Test("a card says since when for a chapter still going, else the month and how long")
    func cards() {
        let when = { (began: String, ended: String?) in
            ChapterReading.when(
                began: day(began), ended: ended.map(day), now: now, calendar: calendar)
        }
        #expect(when("2026-11-03", nil) == "Since 3 Nov · still going")
        #expect(when("2026-10-04", "2026-10-09") == "October · six days")
        #expect(when("2026-06-01", "2026-07-31") == "June – July · two months")
        #expect(when("2025-10-04", "2025-10-04") == "October 2025 · one day")
        #expect(when("2026-09-01", "2026-09-21") == "September · three weeks")
    }

    @Test("a page gives the days themselves")
    func spans() {
        let span = { (began: String, ended: String?) in
            ChapterReading.span(
                began: day(began), ended: ended.map(day), now: now, calendar: calendar)
        }
        #expect(span("2026-10-04", "2026-10-09") == "4–9 October · six days")
        #expect(span("2026-09-28", "2026-10-03") == "28 September – 3 October · six days")
        #expect(span("2026-11-03", nil) == "Since 3 November · still going")
        #expect(span("2025-12-30", "2026-01-02") == "30 December 2025 – 2 January · four days")
    }

    @Test("where it came from is only what the server counted, and always what you told it")
    func provenance() {
        let noticed = ChapterFacts(
            began: day("2026-10-04"), ended: day("2026-10-09"), noticed: day("2026-10-10"),
            drawnFrom: .init(journalDays: 6, photos: 86))
        #expect(
            ChapterReading.provenance(noticed, lead: "Kumo", now: now, calendar: calendar)
                == "Kumo noticed this chapter on 10 October, from your journal, 86 photos and what you told it."
        )
        let bare = ChapterFacts(
            began: day("2026-10-04"), drawnFrom: .init(journalDays: 0, photos: 1))
        #expect(
            ChapterReading.provenance(bare, lead: "Kumo", now: now, calendar: calendar)
                == "Kumo noticed this chapter, from one photo and what you told it.")
        let told = ChapterFacts(
            began: day("2026-10-04"), noticed: day("2026-10-05"),
            drawnFrom: .init(journalDays: 0, photos: 0))
        #expect(
            ChapterReading.provenance(told, lead: "Kumo", now: now, calendar: calendar)
                == "Kumo noticed this chapter on 5 October, from what you told it.")
    }

    @Test("the journal days a chapter draws on are one chip, where the first of them was")
    func chips() {
        let links = [
            MemoryLink(address: "memory:people/mira", title: "Mira"),
            MemoryLink(address: "memory:journal/2026-10-05", title: "5 October 2026"),
            MemoryLink(address: "memory:topics/trips", title: "Trips"),
            MemoryLink(address: "memory:journal/2026-10-04", title: "4 October 2026"),
            MemoryLink(address: "memory:journal/2026-10-09", title: "9 October 2026"),
        ]
        #expect(
            ChapterReading.chips(links, calendar: calendar, now: now) == [
                .init(title: "Mira", address: "memory:people/mira"),
                .init(title: "Journal, 4–9 Oct", address: "memory:journal/2026-10-04"),
                .init(title: "Trips", address: "memory:topics/trips"),
            ])
        let one = [MemoryLink(address: "memory:journal/2026-10-04", title: "4 October 2026")]
        #expect(
            ChapterReading.chips(one, calendar: calendar, now: now).map(\.title) == [
                "Journal, 4 Oct"
            ])
    }

    @Test("what Kumo learnt is dated today, yesterday, by weekday, then by date")
    func learnt() {
        let said = { (at: String) in
            ChapterReading.learnt(Timestamp(at)!, now: now, calendar: calendar)
        }
        #expect(said("2026-11-21T08:00:00.000Z") == "Today")
        #expect(said("2026-11-20T21:00:00.000Z") == "Yesterday")
        #expect(said("2026-11-18T09:00:00.000Z") == "Wednesday")
        #expect(said("2026-11-12T09:00:00.000Z") == "12 Nov")
        #expect(said("2025-11-12T09:00:00.000Z") == "12 Nov 2025")
    }

    @Test("Now's card says how fresh it is, by the part of the day")
    func freshness() {
        let fresh = { (at: String) in
            ChapterReading.freshness(Timestamp(at)!, now: now, calendar: calendar)
        }
        #expect(fresh("2026-11-21T07:30:00.000Z") == "this morning")
        #expect(fresh("2026-11-21T11:59:00.000Z") == "this morning")
        #expect(fresh("2026-11-20T19:00:00.000Z") == "yesterday")
        #expect(fresh("2026-11-17T19:00:00.000Z") == "Tuesday")
    }
}
