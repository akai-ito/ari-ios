import AriKit
import Foundation
import Testing

/// Kumo's blocks over something else on purpose: what they overlap, and why.
@Suite("Overlapping blocks")
struct DayOverlapTests {
    @Test("Kumo's blocks know what else shares their time, soonest first")
    func overlapping() throws {
        let kumo = CalendarName(name: "Kumo", kumo: true)
        let home = CalendarName(name: "Home", kumo: false)
        func item(_ id: String, _ start: String, _ end: String, calendar: CalendarName = home)
            -> CalendarItem
        {
            CalendarItem(
                id: CalendarItemID(rawValue: id), uid: id, title: id,
                start: When("2026-11-15T\(start):00.000Z")!,
                end: When("2026-11-15T\(end):00.000Z")!,
                calendar: calendar)
        }
        let walk = item("walk", "09:00", "10:30", calendar: kumo)
        let hold = item("hold", "09:30", "10:00", calendar: kumo)
        let early = item("early", "08:00", "09:15")
        let after = item("after", "10:30", "11:00")
        let allDay = CalendarItem(
            id: "trip", uid: "trip", title: "trip", start: When(year: 2026, month: 11, day: 15),
            end: When(year: 2026, month: 11, day: 16), allDay: true, calendar: home)
        let desk = Desk(comingUp: [walk, hold, after, allDay, early])

        #expect(desk.overlapping(walk).map(\.id) == ["early", "hold"])
        #expect(desk.overlapping(hold).map(\.id) == ["walk"])
        #expect(desk.overlapping(after).isEmpty, "one ending as it starts doesn't overlap")
        #expect(desk.overlapping(allDay).isEmpty)
    }

    @Test("a block put over something on purpose says why")
    func overlapReason() throws {
        let json = #"""
            {"id":"v_walk","uid":"block-1","title":"Morning walk","start":"2026-11-15T09:00:00.000Z",
             "end":"2026-11-15T10:30:00.000Z","all_day":false,"calendar":{"name":"Kumo","kumo":true},
             "status":"confirmed","overlap":{"reason":"Both stand until Dana confirms the call."}}
            """#
        let item = try JSONDecoder().decode(CalendarItem.self, from: Data(json.utf8))
        #expect(item.overlap == Overlap(reason: "Both stand until Dana confirms the call."))
        let plain = json.replacingOccurrences(
            of: #","overlap":{"reason":"Both stand until Dana confirms the call."}"#, with: "")
        #expect(try JSONDecoder().decode(CalendarItem.self, from: Data(plain.utf8)).overlap == nil)
    }
}
