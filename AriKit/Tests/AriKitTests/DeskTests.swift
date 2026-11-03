import AriKit
import Foundation
import Testing

/// The Desk as the box sends it: Kumo's line and mood, the weather, Kumo's plans, what's coming up,
/// what's waiting on you, and Done, read from JSON written as the 0.18 contract has it.
@Suite("Desk")
struct DeskTests {
    @Test("the Desk decodes whole: Kumo's line, the weather, plans, coming up, waiting and more")
    func desk() throws {
        let desk = try JSONValue(json: Self.desk).decode(Desk.self)
        let line = try #require(desk.line)
        #expect(line.text == "Big day: Northwind at 2. You've prepped well.")
        #expect(line.mood == .bright && line.at == Timestamp("2026-11-05T09:00:00.000Z"))
        let ambient = try #require(desk.ambient)
        #expect(ambient.temperature == 14 && ambient.condition == .partlyCloudy && ambient.isDay)
        #expect(
            ambient.sunset == Timestamp("2026-11-05T16:21:00.000Z") && ambient.place == "London")
        #expect(desk.plans.map(\.id) == ["w_1", "w_2"])
        let weekday = desk.plans[1]
        #expect(weekday.repeat == Repeat(days: Weekday.weekdays, time: "08:30"))
        #expect(weekday.by == .you && weekday.source.kind == .chat)
        let mail = desk.plans[0].source
        #expect(mail.kind == .mail && mail.mail?.messageID == "tess-1104@halcyon.example")
        #expect(desk.plans[0].motion == "job-search" && desk.plans[0].repeat == nil)
        #expect(desk.handled == 9)
        #expect(desk.lastMailAt == Timestamp("2026-11-05T15:18:00.000Z"))
        #expect(desk.comingUp.map(\.id) == ["prep", "halcyon", "florence"])
        #expect(desk.waiting.map(\.kind) == [.draft, .invite, .times, .question, .offer])
        #expect(desk.waiting[0].changedAt == Timestamp("2026-11-05T09:30:00.000Z"))
        #expect(desk.waiting[1].changedAt == nil)
    }

    @Test("a mood or a sky Ari doesn't know shows as calm, or cloudy")
    func unknownMoodAndSky() throws {
        var json = try JSONValue(json: Self.desk)
        json["line"]?["mood"] = .string("wistful")
        json["ambient"]?["condition"] = .string("hail")
        let desk = try json.decode(Desk.self)
        #expect(desk.line?.mood.rawValue == "wistful" && desk.line?.mood.shown == .calm)
        #expect(desk.ambient?.condition.shown == .cloudy)
        #expect(KumoMood.proud.shown == .proud && Weather.snow.shown == .snow)
    }

    @Test("Kumo's plans as you change them: moved, still soonest first, then cancelled")
    func plans() throws {
        let desk = try JSONValue(json: Self.desk).decode(Desk.self)
        let later = desk.plans[0]
        let moved = WakeUp(
            id: later.id, at: try #require(Timestamp("2026-11-07T09:00:00.000Z")),
            what: later.what, why: later.why, source: later.source, setAt: later.setAt)
        #expect(desk.replacing(plan: moved).plans.map(\.id) == ["w_2", "w_1"])
        #expect(desk.removing(plan: "w_1").plans.map(\.id) == ["w_2"])
        #expect(desk.replacing(plans: []).plans.isEmpty)
        #expect(desk.replacing(plans: []).line == desk.line)
        #expect(
            try JSONValue(encoding: WakeUpChange(repeat: .some(nil), what: "Plan the week"))
                == JSONValue(json: #"{"repeat":null,"what":"Plan the week"}"#))
        #expect(
            try JSONValue(
                encoding: WakeUpChange(repeat: Repeat(days: [.saturday], time: "10:00")))
                == JSONValue(json: #"{"repeat":{"days":["sat"],"time":"10:00"}}"#))
        #expect(try JSONValue(encoding: WakeUpChange()) == JSONValue(json: "{}"))
    }

    @Test("a guess in Coming up, and answers that change it")
    func picture() throws {
        var json = try JSONValue(json: Self.desk)
        var items = try #require(json["coming_up"]?.array)
        items[0]["guess"] = .object([
            "activity": .string("chilling"), "why": .string("Sunday evenings you switch off."),
        ])
        json["coming_up"] = .array(items)
        let desk = try json.decode(Desk.self)
        let guessed = desk.comingUp[0]
        #expect(guessed.guess == Guess(activity: .chilling, why: "Sunday evenings you switch off."))
        let yours = CalendarItem(
            id: guessed.id, uid: guessed.uid, title: "Building", start: guessed.start,
            end: guessed.end, calendar: guessed.calendar)
        #expect(desk.replacing(item: yours).comingUp[0] == yours)
        #expect(desk.replacing(item: yours).comingUp[1] == desk.comingUp[1])
        #expect(try JSONValue(encoding: GuessAnswer.right) == JSONValue(json: #"{"right":true}"#))
        #expect(
            try JSONValue(encoding: GuessAnswer(activity: .people))
                == JSONValue(json: #"{"activity":"people"}"#))
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
        #expect(work.tracks.isEmpty)
    }

    @Test("Kumo's work carries the areas it's learning, and a call its track")
    func tracks() throws {
        let work = try JSONValue(
            json: """
                {"day":"2026-11-05",
                 "handled":[{"id":"d1","at":"2026-11-05T15:02:00.000Z","text":"Drafted a reply to Clara",
                             "undo":false,"quiet":false,"track":"l_1",
                             "corrected_at":"2026-11-05T16:00:00.000Z"}],
                 "cleared":[],
                 "tracks":[{"id":"l_1","name":"Writing as you","stage":"learning",
                            "since":"2026-11-05T16:00:00.000Z","note":"Back to learning.",
                            "confirmed":12,"corrected":1,
                            "evidence":[{"at":"2026-11-05T16:00:00.000Z","kind":"corrected",
                                         "text":"Too formal for Clara","stage":"learning",
                                         "done":"d1"},
                                        {"at":"2026-11-01T09:00:00.000Z","kind":"moved",
                                         "text":"Three weeks of drafts you sent","stage":"spot_checks"}]},
                           {"id":"l_2","name":"Your weekends","stage":"climbing",
                            "since":"2026-11-01T09:00:00.000Z","confirmed":0,"corrected":0,
                            "evidence":[]}]}
                """
        ).decode(KumoWork.self)
        #expect(work.handled[0].track == "l_1" && work.handled[0].isCorrected)
        #expect(work.tracks.map(\.stage.rung) == [0, 0])
        #expect(work.tracks.map(\.stage.isKnown) == [true, false])
        let writing = work.tracks[0]
        #expect(writing.name == "Writing as you" && writing.note == "Back to learning.")
        #expect(writing.confirmed == 12 && writing.corrected == 1)
        #expect(writing.evidence.map(\.kind) == [.corrected, .moved])
        #expect(writing.evidence[0].done == "d1" && writing.evidence[1].stage == .spotChecks)
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
        var item = try #require(json["coming_up"]?.array?.first)
        item["status"] = .string("pencilled")
        json["coming_up"] = .array([item])
        let desk = try json.decode(Desk.self)
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
          "line": {
            "text": "Big day: Northwind at 2. You've prepped well.", "mood": "bright",
            "at": "2026-11-05T09:00:00.000Z"
          },
          "ambient": {
            "temperature": 14, "condition": "partly_cloudy", "is_day": true,
            "sunset": "2026-11-05T16:21:00.000Z", "place": "London"
          },
          "plans": [
            {"id": "w_1", "at": "2026-11-05T15:30:00.000Z",
             "what": "Ask how the Halcyon technical went",
             "why": "It ends at 15:30, and you wanted to talk it through while it's fresh.",
             "by": "kumo", "motion": "job-search", "set_at": "2026-11-04T18:00:00.000Z",
             "source": {"kind": "mail", "title": "Tess Harlow: Thursday's technical",
                        "mail": {"account": "icloud", "message_id": "tess-1104@halcyon.example"}}},
            {"id": "w_2", "at": "2026-11-06T08:30:00.000Z",
             "what": "Shape the day with you if it's unplanned",
             "why": "You asked for a look at each weekday morning.",
             "repeat": {"days": ["mon", "tue", "wed", "thu", "fri"], "time": "08:30"},
             "by": "you", "set_at": "2026-11-01T19:00:00.000Z",
             "source": {"kind": "chat", "title": "Chat"}}
          ],
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
