import AriKit
import Foundation
import Testing

/// The Desk as the box sends it: the morning card, what's coming up, what's waiting on you, and
/// Done, read from JSON written as the 0.16 contract has it.
@Suite("Desk")
struct DeskTests {
    @Test("the Desk decodes whole: briefing, coming up and waiting")
    func desk() throws {
        let desk = try JSONValue(json: Self.desk).decode(Desk.self)
        let briefing = try #require(desk.briefing)
        #expect(briefing.id == "b_0001" && briefing.kind == .morning)
        #expect(briefing.at == Timestamp("2026-11-05T07:40:00.000Z"))
        #expect(briefing.handled == 9 && briefing.readAt == nil)
        #expect(briefing.lines.map(\.card) == [nil, "c_hotel"])
        #expect(briefing.lines.first?.text.hasPrefix("Poppy sent the Teams link") == true)
        #expect(desk.comingUp.map(\.id) == ["prep", "qrt", "florence"])
        #expect(desk.waiting.map(\.kind) == [.draft, .invite, .times, .question, .offer])
    }

    @Test("a calendar item reads its calendar, travel, status and all-day days")
    func calendarItems() throws {
        let items = try JSONValue(json: Self.desk).decode(Desk.self).comingUp
        let prep = items[0]
        #expect(prep.calendar == CalendarName(name: "Kumo", kumo: true))
        #expect(prep.status == .hold && prep.motion == "job-search")
        let qrt = items[1]
        #expect(qrt.uid == "040000008200E00074C5B7101A82E008")
        #expect(qrt.location == "Teams" && !qrt.allDay && qrt.status == .confirmed)
        #expect(qrt.leaveAt == Timestamp("2026-11-05T13:20:00.000Z"))
        #expect(!qrt.calendar.kumo)
        #expect(qrt.start.instant == Timestamp("2026-11-05T14:00:00.000Z")?.date)
        #expect(qrt.start.day == nil)
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
        #expect(invite.event.title == "Katia: Citadel, second round")
        #expect(invite.clash?.title == "Dentist")
        #expect(cards[1].options.map(\.acts) == [true, false, false])
        #expect(cards[1].draft == nil)

        let times = try #require(cards[2].times)
        #expect(times.purpose == "QRT technical interview")
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
        json["briefing"]?["kind"] = .string("evening")
        var item = try #require(json["coming_up"]?.array?.first)
        item["status"] = .string("pencilled")
        json["coming_up"] = .array([item])
        let desk = try json.decode(Desk.self)
        #expect(desk.briefing?.kind.rawValue == "evening" && desk.briefing?.kind.isKnown == false)
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
        let desk = try JSONValue(json: #"{"coming_up":[],"waiting":[]}"#).decode(Desk.self)
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

    /// `GET /v0/desk` on the Thursday of QRT.
    static let desk = """
        {
          "briefing": {
            "id": "b_0001", "kind": "morning", "at": "2026-11-05T07:40:00.000Z",
            "lines": [
              {"text": "Poppy sent the Teams link for this afternoon; it's on the event."},
              {"text": "Hotel Orto confirmed Florence, but you land 22:10 and check-in closes 22:00. I drafted a note asking them to wait.",
               "card": "c_hotel"}
            ],
            "handled": 9
          },
          "coming_up": [
            {"id": "prep", "uid": "prep-qrt@kumo", "title": "Prep: QRT technical",
             "start": "2026-11-05T13:00:00.000Z", "end": "2026-11-05T14:00:00.000Z",
             "all_day": false, "calendar": {"name": "Kumo", "kumo": true},
             "motion": "job-search", "status": "hold"},
            {"id": "qrt", "uid": "040000008200E00074C5B7101A82E008", "title": "QRT technical",
             "start": "2026-11-05T14:00:00.000Z", "end": "2026-11-05T15:00:00.000Z",
             "all_day": false, "location": "Teams", "calendar": {"name": "Home", "kumo": false},
             "leave_at": "2026-11-05T13:20:00.000Z", "motion": "job-search",
             "status": "confirmed"},
            {"id": "florence", "uid": "florence@icloud.com", "title": "Florence with Janki",
             "start": "2026-11-12", "end": "2026-11-15",
             "all_day": true, "calendar": {"name": "Home", "kumo": false},
             "motion": "florence", "status": "confirmed"}
          ],
          "waiting": [
            {"id": "c_hotel", "kind": "draft", "motion": "florence",
             "at": "2026-11-05T07:02:00.000Z", "title": "Draft to Hotel Orto",
             "options": [{"label": "Drop it"}], "allows_text": true,
             "draft": {"account": "icloud", "from": "divy@icloud.com",
                       "to": ["Hotel Orto <info@hotelorto.it>"],
                       "subject": "Re: Booking confirmed, 12–15 Nov",
                       "body": "Ciao! We land at 22:10, could you hold the room?\\n\\nGrazie,\\nDivy",
                       "message_id": "draft-7f3a91@divy.icloud.com",
                       "in_reply_to": "confirm-48213@hotelorto.it"}},
            {"id": "c_citadel", "kind": "invite", "motion": "job-search",
             "at": "2026-11-05T12:58:00.000Z", "title": "Invite: Citadel, second round",
             "options": [{"label": "Accept", "acts": true}, {"label": "Maybe"}, {"label": "Decline"}],
             "allows_text": false,
             "invite": {
               "event": {"id": "citadel", "uid": "citadel-2@citadel.com",
                         "title": "Katia: Citadel, second round",
                         "start": "2026-11-17T16:00:00.000Z", "end": "2026-11-17T17:00:00.000Z",
                         "all_day": false, "location": "Zoom",
                         "calendar": {"name": "Kumo", "kumo": true}, "status": "hold"},
               "clash": {"id": "dentist", "uid": "dentist@icloud.com", "title": "Dentist",
                         "start": "2026-11-17T16:30:00.000Z", "end": "2026-11-17T17:00:00.000Z",
                         "all_day": false, "calendar": {"name": "Home", "kumo": false},
                         "status": "confirmed"}}},
            {"id": "c_times", "kind": "times", "motion": "job-search",
             "at": "2026-11-05T08:15:00.000Z", "title": "Times for QRT",
             "options": [{"label": "Send these", "acts": true}], "allows_text": false,
             "state": "working",
             "times": {"purpose": "QRT technical interview",
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
