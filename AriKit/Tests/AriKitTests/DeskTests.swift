import AriKit
import Foundation
import Testing

/// The Desk as the box sends it: Kumo's line for the moment, what's coming up, what's waiting on
/// you, and Done, read from JSON written as the 0.17 contract has it.
@Suite("Desk")
struct DeskTests {
    @Test("the Desk decodes whole: Kumo's line, coming up, waiting, handled and the last mail")
    func desk() throws {
        let desk = try JSONValue(json: Self.desk).decode(Desk.self)
        let moment = try #require(desk.moment)
        #expect(moment.id == "o_0001" && moment.kind == .news && moment.message == "m_0042")
        #expect(moment.at == Timestamp("2026-11-05T15:20:00.000Z"))
        #expect(moment.text.hasPrefix("How did the call with Northwind go?"))
        #expect(moment.options.map(\.label) == ["Ask me tonight"] && moment.allowsText)
        #expect(moment.readAt == nil && !moment.isWorking && moment.answer == nil)
        #expect(desk.handled == 9)
        #expect(desk.lastMailAt == Timestamp("2026-11-05T15:18:00.000Z"))
        #expect(desk.comingUp.map(\.id) == ["prep", "halcyon", "florence"])
        #expect(desk.waiting.map(\.kind) == [.draft, .invite, .times, .question, .offer])
        #expect(desk.waiting[0].changedAt == Timestamp("2026-11-05T09:30:00.000Z"))
        #expect(desk.waiting[1].changedAt == nil)
    }

    @Test("Kumo's line at work on your answer, and the same Desk with it")
    func workingMoment() throws {
        var json = try JSONValue(json: Self.desk)
        json["moment"]?["state"] = .string("working")
        json["moment"]?["answer"] = .object(["option": .string("Ask me tonight")])
        json["moment"]?["read_at"] = .string("2026-11-05T15:20:02.000Z")
        let working = try #require(try json.decode(Desk.self).moment)
        #expect(working.isWorking && working.answer == CardAnswer(option: "Ask me tonight"))
        #expect(working.readAt == Timestamp("2026-11-05T15:20:02.000Z"))
        let desk = try JSONValue(json: Self.desk).decode(Desk.self)
        #expect(desk.replacing(moment: working).moment == working)
        #expect(desk.replacing(moment: working).handled == 9)
    }

    @Test("a guess in Coming up, the plan under the day's line, and answers that change them")
    func picture() throws {
        var json = try JSONValue(json: Self.desk)
        json["moment"]?["kind"] = .string("question")
        json["moment"]?["detail"] = .string("Easy run · groceries · 2h prep")
        json["moment"]?["reply_label"] = .string("Note it")
        var items = try #require(json["coming_up"]?.array)
        items[0]["guess"] = .object([
            "activity": .string("chilling"), "why": .string("Sunday evenings you switch off."),
        ])
        json["coming_up"] = .array(items)
        let desk = try json.decode(Desk.self)
        let moment = try #require(desk.moment)
        #expect(moment.kind == .question && moment.detail == "Easy run · groceries · 2h prep")
        #expect(moment.replyLabel == "Note it")
        let guessed = desk.comingUp[0]
        #expect(guessed.guess == Guess(activity: .chilling, why: "Sunday evenings you switch off."))
        let yours = CalendarItem(
            id: guessed.id, uid: guessed.uid, title: "Building", start: guessed.start,
            end: guessed.end, calendar: guessed.calendar)
        #expect(desk.replacing(item: yours).comingUp[0] == yours)
        #expect(desk.replacing(item: yours).comingUp[1] == desk.comingUp[1])
        #expect(desk.withoutMoment(moment.id).moment == nil)
        #expect(desk.withoutMoment("o_other").moment == moment)
        #expect(try JSONValue(encoding: GuessAnswer.right) == JSONValue(json: #"{"right":true}"#))
        #expect(
            try JSONValue(encoding: GuessAnswer(activity: .people))
                == JSONValue(json: #"{"activity":"people"}"#))
        #expect(try JSONValue(encoding: MomentSkip()) == JSONValue(json: #"{"skip":true}"#))
    }

    @Test("Kumo's work today: what it handled and what it cleared")
    func work() throws {
        let work = try JSONValue(
            json: """
                {"day":"2026-11-05",
                 "handled":[{"id":"d1","at":"2026-11-05T15:02:00.000Z","text":"Electricity bill → Admin",
                             "reason":"A bill with a date on it","undo":true,"quiet":false}],
                 "cleared":[{"id":"q1","at":"2026-11-05T08:10:00.000Z","text":"Bank statement",
                             "reason":"routine, nothing due","undo":false,"quiet":true}]}
                """
        ).decode(KumoWork.self)
        #expect(work.day == "2026-11-05")
        #expect(work.handled.map(\.id) == ["d1"] && work.handled[0].undo)
        #expect(work.cleared.map(\.id) == ["q1"] && work.cleared[0].quiet)
        #expect(work.trust.isEmpty)
    }

    @Test("Kumo's work carries the trust ladder, and each call its kind of work")
    func trust() throws {
        let work = try JSONValue(
            json: """
                {"day":"2026-11-05",
                 "handled":[{"id":"d1","at":"2026-11-05T15:02:00.000Z","text":"Undone: Binned a mail",
                             "undo":false,"quiet":false,"work":"sorting",
                             "corrected_at":"2026-11-05T16:00:00.000Z"}],
                 "cleared":[],
                 "trust":[{"work":"sorting","title":"Sorting mail","step":"spot_checks",
                           "line":"You said it was wrong.","since":"2026-11-05T16:00:00.000Z"},
                          {"work":"filing","title":"Filing","step":"climbing",
                           "line":"Something new.","since":"2026-11-01T09:00:00.000Z"}]}
                """
        ).decode(KumoWork.self)
        #expect(work.handled[0].work == .sorting && work.handled[0].isCorrected)
        #expect(work.trust.map(\.step.rung) == [1, 0])
        #expect(work.trust.map(\.work.isKnown) == [true, false])
        #expect(work.trust[0].title == "Sorting mail")
    }

    @Test("a card to glance at a day's calls opens Kumo's work with its first option")
    func review() throws {
        let card = try JSONValue(
            json: """
                {"id":"k1","kind":"question","at":"2026-11-06T07:30:00.000Z",
                 "title":"Yesterday I sorted 44 mails. Glance?",
                 "options":[{"label":"Glance","acts":true},{"label":"Looks fine"}],
                 "allows_text":false,"quiet":true,"question":{"text":"I'm still learning."},
                 "review":{"day":"2026-11-05","work":["sorting"]}}
                """
        ).decode(DeskCard.self)
        #expect(card.review == ReviewCard(day: "2026-11-05", work: [.sorting]))
        #expect(card.glances(CardAnswer(option: "Glance")))
        #expect(!card.glances(CardAnswer(option: "Looks fine")))
        #expect(CorrectDone(text: "  ").text == nil && CorrectDone(text: " Mine ").text == "Mine")
    }

    @Test("a calendar item reads its calendar, travel, status and all-day days")
    func calendarItems() throws {
        let items = try JSONValue(json: Self.desk).decode(Desk.self).comingUp
        let prep = items[0]
        #expect(prep.calendar == CalendarName(name: "Kumo", kumo: true))
        #expect(prep.status == .hold && prep.motion == "job-search")
        let halcyon = items[1]
        #expect(halcyon.uid == "040000008200E00074C5B7101A82E008")
        #expect(halcyon.location == "Teams" && !halcyon.allDay && halcyon.status == .confirmed)
        #expect(halcyon.leaveAt == Timestamp("2026-11-05T13:20:00.000Z"))
        #expect(!halcyon.calendar.kumo)
        #expect(halcyon.start.instant == Timestamp("2026-11-05T14:00:00.000Z")?.date)
        #expect(halcyon.start.day == nil)
        let florence = items[2]
        #expect(florence.allDay && florence.location == nil && florence.leaveAt == nil)
        #expect(florence.start.day == DateComponents(year: 2026, month: 11, day: 12))
        #expect(florence.end.day == DateComponents(year: 2026, month: 11, day: 15))
        #expect(florence.start.instant == nil)
    }

    @Test("a calendar time is an instant, with or without seconds and in any offset, or a day")
    func calendarTimes() throws {
        let utc = try #require(When("2026-11-12T14:00:00Z")?.instant)
        #expect(When("2026-11-12T14:00Z")?.instant == utc)
        #expect(When("2026-11-12T15:00:00.000+01:00")?.instant == utc)
        #expect(When("2026-11-12")?.day == DateComponents(year: 2026, month: 11, day: 12))
        for text in ["2026-11-12T14:00:00", "2026-13-12", "12 November", "2026-11-12T25:00Z", ""] {
            #expect(When(text) == nil, "\(text)")
        }
        #expect(When(year: 2026, month: 11, day: 1).rawValue == "2026-11-01")
        #expect(When(utc).instant == utc)
    }

    @Test("each kind of card carries its own part, and only that")
    func cards() throws {
        let cards = try JSONValue(json: Self.desk).decode(Desk.self).waiting

        let draft = try #require(cards[0].draft)
        #expect(cards[0].title == "Draft to Hotel Orto")
        #expect(cards[0].motion == "florence" && cards[0].invite == nil)
        #expect(cards[0].allowsText && cards[0].options.map(\.label) == ["Drop it"])
        #expect(draft.account == "icloud" && draft.from == "divy@icloud.com")
        #expect(draft.to == ["Hotel Orto <info@hotelorto.it>"] && draft.cc == nil)
        #expect(draft.subject == "Re: Booking confirmed, 12–15 Nov")
        #expect(draft.body.hasPrefix("Ciao! We land at 22:10"))
        #expect(draft.messageID == "draft-7f3a91@divy.icloud.com")
        #expect(draft.inReplyTo == "confirm-48213@hotelorto.it")

        let invite = try #require(cards[1].invite)
        #expect(invite.event.title == "Freya: Northwind, second round")
        #expect(invite.clash?.title == "Dentist")
        #expect(cards[1].options.map(\.acts) == [true, false, false])
        #expect(cards[1].draft == nil)

        let times = try #require(cards[2].times)
        #expect(times.purpose == "Halcyon technical interview")
        #expect(times.slots.map(\.note) == ["WFH", nil, "WFH"])
        #expect(cards[2].state == .working)

        let question = try #require(cards[3].question)
        #expect(question.text == "I binned “Your account update” from Revolut. Right?")

        let offer = try #require(cards[4].offer)
        #expect(offer.text == "You log your runs by hand. Shall I read them from Strava?")
        #expect(offer.capability == "strava")
    }

    @Test("a draft without its Message-ID doesn't decode: there'd be nothing to open in Mail")
    func draftWithoutMessageID() throws {
        let desk = try JSONValue(json: Self.desk)
        var card = try #require(desk["waiting"]?.array?.first)
        card["draft"]?["message_id"] = nil
        #expect(throws: DecodingError.self) { try card.decode(DeskCard.self) }
    }

    @Test("a card of a kind Ari doesn't know decodes, keeping its kind's text and its title")
    func unknownCardKind() throws {
        let card = try JSONValue(
            json: """
                {"id":"c_parcel","kind":"parcel","at":"2026-11-05T10:00:00.000Z",
                 "title":"Your DPD parcel arrives between 14:00 and 15:00","options":[],
                 "allows_text":false,"parcel":{"carrier":"DPD","window":["14:00","15:00"]}}
                """
        ).decode(DeskCard.self)
        #expect(card.kind == CardKind(rawValue: "parcel") && !card.kind.isKnown)
        #expect(card.title == "Your DPD parcel arrives between 14:00 and 15:00")
        #expect(card.draft == nil && card.invite == nil && card.times == nil)
        #expect(card.question == nil && card.offer == nil)
    }

    @Test("values Ari doesn't know decode and keep their text")
    func unknownValues() throws {
        var json = try JSONValue(json: Self.desk)
        json["moment"]?["kind"] = .string("evening")
        var item = try #require(json["coming_up"]?.array?.first)
        item["status"] = .string("pencilled")
        json["coming_up"] = .array([item])
        let desk = try json.decode(Desk.self)
        #expect(desk.moment?.kind.rawValue == "evening" && desk.moment?.kind.isKnown == false)
        #expect(desk.comingUp.first?.status?.rawValue == "pencilled")
    }

    @Test("fields Ari doesn't know are ignored, at every level")
    func unknownFields() throws {
        let plain = try JSONValue(json: Self.desk).decode(Desk.self)
        let extended = try JSONValue(json: Self.desk).addingUnknownFields().decode(Desk.self)
        #expect(extended == plain)
        let page = try JSONValue(json: Self.done).decode(DonePage.self)
        let extendedPage = try JSONValue(json: Self.done).addingUnknownFields().decode(
            DonePage.self)
        #expect(extendedPage == page)
    }

    @Test("a quiet Desk has nothing on it")
    func quietDesk() throws {
        let desk = try JSONValue(json: #"{"coming_up":[],"waiting":[],"handled":0}"#)
            .decode(Desk.self)
        #expect(desk == Desk())
    }

    @Test("a page of Done: actions, quiet reads with their reasons, and whether there's more")
    func done() throws {
        let page = try JSONValue(json: Self.done).decode(DonePage.self)
        #expect(page.hasMore)
        #expect(page.entries.map(\.id) == ["d1", "q1", "d2"])
        #expect(page.entries[0].undo && !page.entries[0].quiet && page.entries[0].reason == nil)
        #expect(page.entries[1].quiet && page.entries[1].reason == "routine, nothing due")
        #expect(page.entries[1].mail?.messageID == "statement-1105@monzo.com")
        #expect(!page.entries[2].undo && page.entries[2].motion == "florence")
        #expect(page.entries[2].event?.title == "Hotel Orto")
        let last = try JSONValue(json: #"{"entries":[],"has_more":false}"#).decode(DonePage.self)
        #expect(last.entries.isEmpty && !last.hasMore)
    }

    @Test(
        "Kumo's work before today: each earlier day with anything on it, read whole, then the end")
    func history() async throws {
        let today = KumoWork(day: "2026-11-05", handled: [Self.entry("d9", "2026-11-05T09:00")])
        // Done goes back one entry at a time: Tuesday's, then Saturday's (a quiet weekend), then
        // nothing more.
        let done: [String?: DonePage] = [
            "d9": DonePage(entries: [Self.entry("d8", "2026-11-04T18:00")], hasMore: true),
            "d6": DonePage(entries: [Self.entry("d5", "2026-11-01T11:00")], hasMore: false),
        ]
        let days: [String: KumoWork] = [
            "2026-11-04": KumoWork(
                day: "2026-11-04", handled: [Self.entry("d8", "2026-11-04T18:00")],
                cleared: [Self.entry("d6", "2026-11-04T07:00", quiet: true)]),
            "2026-11-01": KumoWork(
                day: "2026-11-01", handled: [Self.entry("d5", "2026-11-01T11:00")]),
        ]
        var asked: [String] = []
        var history = WorkHistory()
        for _ in 0..<2 {
            try await history.readNext(
                after: today, calendar: Self.london,
                done: { before in done[before?.rawValue] ?? DonePage(entries: []) },
                work: { day in
                    asked.append(day)
                    return days[day] ?? KumoWork(day: day)
                })
        }
        #expect(asked == ["2026-11-04", "2026-11-01"])
        #expect(history.days.map(\.day) == ["2026-11-04", "2026-11-01"])
        #expect(history.isFinished)

        let undone = Self.entry("d8", "2026-11-04T18:00", text: "Undone: filed a bill")
        #expect(history.replacing(undone).days[0].handled == [undone])
    }

    @Test("an empty page of Done ends Kumo's work, though it says there's more")
    func historyEnds() async throws {
        var history = WorkHistory()
        var worked = false
        try await history.readNext(
            after: KumoWork(day: "2026-11-05"), calendar: Self.london,
            done: { _ in DonePage(entries: [], hasMore: true) },
            work: { day in
                worked = true
                return KumoWork(day: day)
            })
        #expect(history.isFinished && history.days.isEmpty && !worked)
    }

    @Test("Kumo's work never reads a day twice, where the phone's days and the box's disagree")
    func historyGoesBack() async throws {
        // The entry falls on the 5th by this phone's clock, which the box already counted as today.
        let today = KumoWork(day: "2026-11-05")
        var asked: [String] = []
        var history = WorkHistory()
        try await history.readNext(
            after: today, calendar: Self.london,
            done: { _ in DonePage(entries: [Self.entry("d1", "2026-11-05T08:00")], hasMore: true) },
            work: { day in
                asked.append(day)
                return KumoWork(day: day)
            })
        #expect(asked == ["2026-11-04"] && history.days.isEmpty && !history.isFinished)
    }

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private static func entry(
        _ id: String, _ at: String, quiet: Bool = false, text: String = "Filed a bill"
    ) -> DoneEntry {
        DoneEntry(
            id: DoneID(rawValue: id), at: Timestamp("\(at):00.000Z")!, text: text, quiet: quiet)
    }

    @Test("an answer sends only what it says: an option, the clear slots, or words")
    func answers() throws {
        let option = try JSONValue(encoding: CardAnswer(option: "Accept"))
        #expect(option == .object(["option": .string("Accept")]))
        let slots = try JSONValue(encoding: CardAnswer(slots: [0, 2]))
        #expect(slots == .object(["slots": .array([.int(0), .int(2)])]))
        let words = try JSONValue(encoding: CardAnswer(text: "a bit more casual"))
        #expect(words == .object(["text": .string("a bit more casual")]))
    }

    @Test("a calendar item without a status decodes: it's optional in the contract")
    func itemWithoutStatus() throws {
        let desk = try JSONValue(json: Self.desk)
        var item = try #require(desk["coming_up"]?.array?[1])
        item["status"] = nil
        #expect(try item.decode(CalendarItem.self).status == nil)
    }

    // MARK: Fixtures

    /// `GET /v0/desk` on the Thursday of Halcyon.
    static let desk = """
        {
          "moment": {
            "id": "o_0001", "kind": "news", "at": "2026-11-05T15:20:00.000Z",
            "text": "How did the call with Northwind go? Tell me and I'll draft the thank-you.",
            "message": "m_0042", "options": [{"label": "Ask me tonight"}], "allows_text": true
          },
          "handled": 9,
          "last_mail_at": "2026-11-05T15:18:00.000Z",
          "coming_up": [
            {"id": "prep", "uid": "prep-halcyon@kumo", "title": "Prep: Halcyon technical",
             "start": "2026-11-05T13:00:00.000Z", "end": "2026-11-05T14:00:00.000Z",
             "all_day": false, "calendar": {"name": "Kumo", "kumo": true},
             "motion": "job-search", "status": "hold"},
            {"id": "halcyon", "uid": "040000008200E00074C5B7101A82E008", "title": "Halcyon technical",
             "start": "2026-11-05T14:00:00.000Z", "end": "2026-11-05T15:00:00.000Z",
             "all_day": false, "location": "Teams", "calendar": {"name": "Home", "kumo": false},
             "leave_at": "2026-11-05T13:20:00.000Z", "motion": "job-search",
             "status": "confirmed"},
            {"id": "florence", "uid": "florence@icloud.com", "title": "Florence with Mira",
             "start": "2026-11-12", "end": "2026-11-15",
             "all_day": true, "calendar": {"name": "Home", "kumo": false},
             "motion": "florence", "status": "confirmed"}
          ],
          "waiting": [
            {"id": "c_hotel", "kind": "draft", "motion": "florence",
             "at": "2026-11-05T07:02:00.000Z", "changed_at": "2026-11-05T09:30:00.000Z",
             "title": "Draft to Hotel Orto",
             "options": [{"label": "Drop it"}], "allows_text": true,
             "draft": {"account": "icloud", "from": "divy@icloud.com",
                       "to": ["Hotel Orto <info@hotelorto.it>"],
                       "subject": "Re: Booking confirmed, 12–15 Nov",
                       "body": "Ciao! We land at 22:10, could you hold the room?\\n\\nGrazie,\\nDivy",
                       "message_id": "draft-7f3a91@divy.icloud.com",
                       "in_reply_to": "confirm-48213@hotelorto.it"}},
            {"id": "c_northwind", "kind": "invite", "motion": "job-search",
             "at": "2026-11-05T12:58:00.000Z", "title": "Invite: Northwind, second round",
             "options": [{"label": "Accept", "acts": true}, {"label": "Maybe"}, {"label": "Decline"}],
             "allows_text": false,
             "invite": {
               "event": {"id": "northwind", "uid": "northwind-2@northwind.example",
                         "title": "Freya: Northwind, second round",
                         "start": "2026-11-17T16:00:00.000Z", "end": "2026-11-17T17:00:00.000Z",
                         "all_day": false, "location": "Zoom",
                         "calendar": {"name": "Kumo", "kumo": true}, "status": "hold"},
               "clash": {"id": "dentist", "uid": "dentist@icloud.com", "title": "Dentist",
                         "start": "2026-11-17T16:30:00.000Z", "end": "2026-11-17T17:00:00.000Z",
                         "all_day": false, "calendar": {"name": "Home", "kumo": false},
                         "status": "confirmed"}}},
            {"id": "c_times", "kind": "times", "motion": "job-search",
             "at": "2026-11-05T08:15:00.000Z", "title": "Times for Halcyon",
             "options": [{"label": "Send these", "acts": true}], "allows_text": false,
             "state": "working",
             "times": {"purpose": "Halcyon technical interview",
                       "slots": [
                         {"start": "2026-11-09T10:00:00.000Z",
                          "end": "2026-11-09T11:00:00.000Z", "note": "WFH"},
                         {"start": "2026-11-11T11:00:00.000Z",
                          "end": "2026-11-11T12:00:00.000Z"},
                         {"start": "2026-11-13T10:00:00.000Z",
                          "end": "2026-11-13T11:00:00.000Z", "note": "WFH"}]}},
            {"id": "c_revolut", "kind": "question", "at": "2026-11-05T09:20:00.000Z", "title": "Binned a Revolut mail",
             "options": [{"label": "Right"}, {"label": "No, keep it"}], "allows_text": true,
             "question": {"text": "I binned “Your account update” from Revolut. Right?"}},
            {"id": "c_strava", "kind": "offer", "at": "2026-11-03T20:00:00.000Z",
             "title": "Strava for your runs",
             "options": [{"label": "Switch it on", "acts": true}, {"label": "Not now"}],
             "allows_text": false,
             "offer": {"text": "You log your runs by hand. Shall I read them from Strava?",
                       "capability": "strava"}}
          ]
        }
        """

    /// `GET /v0/done`: newest first.
    static let done = """
        {
          "entries": [
            {"id": "d1", "at": "2026-11-05T09:14:00.000Z",
             "text": "Domino's: unsubscribed, binned", "undo": true, "quiet": false},
            {"id": "q1", "at": "2026-11-05T09:10:00.000Z", "text": "Monzo statement",
             "reason": "routine, nothing due",
             "mail": {"account": "icloud", "message_id": "statement-1105@monzo.com",
                      "from": "Monzo <help@monzo.com>", "subject": "Your November statement"},
             "undo": false, "quiet": true},
            {"id": "d2", "at": "2026-11-05T09:02:00.000Z",
             "text": "Hotel Orto booking → Florence › Stay, on your calendar",
             "event": {"id": "orto", "uid": "orto@icloud.com", "title": "Hotel Orto",
                       "start": "2026-11-12", "end": "2026-11-15", "all_day": true,
                       "calendar": {"name": "Home", "kumo": false}},
             "motion": "florence", "undo": false, "quiet": false}
          ],
          "has_more": true
        }
        """
}
