import AriKit
import Foundation
import Testing

/// The new shapes of a matter: a Pursuit, an Occasion and a Case. How each decodes, a kind Ari
/// doesn't know still decoding, and how each reads.
@Suite("Matters")
struct MattersTests {
    private let english = Locale(identifier: "en_GB")
    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }
    /// Thursday 29 October, 8:00 in London, the day of the QRT technical.
    private let thursday = Timestamp("2026-10-29T08:00:00Z")!.date

    // MARK: - Decoding

    @Test("a pursuit decodes with its options, stages, people and next steps")
    func pursuitDecodes() throws {
        let detail = try JSONValue(json: Self.jobSearch).decode(MotionDetail.self)
        #expect(detail.motion.kind == .pursuit && detail.motion.title == "Job search")
        let pursuit = try #require(Self.pursuit(detail))
        #expect(pursuit.after.hasPrefix("AI engineering or C++ HFT systems"))
        #expect(pursuit.play.count == 4)
        #expect(pursuit.options.map(\.id) == ["qrt", "citadel", "optiver"])
        let qrt = pursuit.options[0]
        #expect(qrt.role == "Senior AI Engineer" && qrt.org == nil)
        #expect(qrt.stages == ["Screened", "Interviews", "Awaiting answer", "Offer"])
        #expect(qrt.people.first?.page == "memory:people/poppy")
        #expect(qrt.next == NextStep(text: "Technical", at: Timestamp("2026-10-29T14:00:00Z")))
        let citadel = pursuit.options[1]
        #expect(citadel.waitingOn?.who == "them" && citadel.next == nil)
        // Stages, people and the rest can be left out.
        let optiver = pursuit.options[2]
        #expect(optiver.people.isEmpty && optiver.note == "The online test went well")
    }

    @Test("an occasion decodes, `where` and all, and prep Kumo hasn't ticked isn't done")
    func occasionDecodes() throws {
        let detail = try JSONValue(json: Self.dentist).decode(MotionDetail.self)
        let occasion = try #require(Self.occasion(detail))
        #expect(occasion.start.rawValue == "2026-11-13T09:30:00Z")
        #expect(occasion.end?.rawValue == "2026-11-13T10:15:00Z")
        #expect(occasion.place == "Bright Smile Dental, 14 Upper Street")
        #expect(occasion.people == [Occasion.Person(name: "Dr Shah")])
        #expect(occasion.prep.map(\.done) == [false, true])
        #expect(occasion.checkIn && !occasion.allDay)
        #expect(detail.state[OccasionReading.prepList]?["forms"]?.done == true)
    }

    @Test("an occasion needs only its start")
    func bareOccasion() throws {
        let occasion = try JSONValue(json: #"{"start":"2026-11-14T00:00:00Z"}"#).decode(
            Occasion.self)
        #expect(occasion.end == nil && occasion.place == nil && occasion.people.isEmpty)
        #expect(occasion.prep.isEmpty && !occasion.checkIn)
    }

    @Test("a case decodes as kind `case`, with its timeline, who it's waiting on and what's next")
    func caseDecodes() throws {
        #expect(MotionKind.caseFile.rawValue == "case")
        let detail = try JSONValue(json: Self.boiler).decode(MotionDetail.self)
        #expect(detail.motion.kind == .caseFile)
        let file = try #require(Self.caseFile(detail))
        #expect(file.status == "Waiting on the landlord")
        #expect(file.waitingOn?.since.rawValue == "2026-10-22T10:00:00Z")
        #expect(file.timeline.count == 3)
        #expect(file.next?.text == "Chase the agency")
    }

    @Test("the three new kinds are known, and the old ones still are")
    func kinds() {
        #expect(MotionKind.known == [.trip, .training, .pursuit, .occasion, .caseFile])
        #expect(MotionKind(rawValue: "case").isKnown)
        #expect(!MotionKind(rawValue: "career").isKnown)
    }

    @Test("a kind Ari doesn't know still decodes, as a plain card")
    func unknownKind() throws {
        let detail = try JSONValue(
            json: Self.detail(kind: "shopping", content: #"{"basket":["oat milk"]}"#)
        ).decode(MotionDetail.self)
        #expect(detail.content == .unknown)
        #expect(!detail.motion.kind.isKnown && detail.motion.kind.rawValue == "shopping")
        #expect(detail.motion.title == "A thing")
    }

    @Test("a known kind in a shape Ari can't read is unreadable, not a failure")
    func unreadable() throws {
        for kind in ["pursuit", "occasion", "case"] {
            let detail = try JSONValue(
                json: Self.detail(kind: kind, content: #"{"options":"nope"}"#)
            ).decode(MotionDetail.self)
            #expect(detail.content == .unreadable, "\(kind)")
        }
    }

    // MARK: - Reading a pursuit

    @Test("an option's stage is where it sits in its stages, and the furthest along leads")
    func stages() throws {
        let pursuit = try #require(Self.pursuit(try JSONValue(json: Self.jobSearch).decode()))
        let (qrt, citadel, optiver) = (pursuit.options[0], pursuit.options[1], pursuit.options[2])
        #expect(PursuitReading.stage(of: qrt)! == (1, 4))
        #expect(PursuitReading.progress(of: qrt) == 0.5)
        #expect(PursuitReading.progress(of: citadel) == 0.25)
        // "test done" matches "Test done": case doesn't matter.
        #expect(PursuitReading.stage(of: optiver)! == (0, 4))
        #expect(PursuitReading.leading(in: pursuit) == ["qrt"])

        let unmeasured = Pursuit.Option(id: "yc", name: "YC", stage: "Applied")
        #expect(PursuitReading.stage(of: unmeasured) == nil)
        let offStages = Pursuit.Option(
            id: "x", name: "X", stage: "On hold", stages: ["Applied", "Offer"])
        #expect(PursuitReading.progress(of: offStages) == nil)
        #expect(PursuitReading.leading(in: Pursuit(after: "", options: [unmeasured])).isEmpty)
        // Level options both lead.
        let level = Pursuit(after: "", options: [citadel, optiver])
        #expect(PursuitReading.leading(in: level) == ["citadel", "optiver"])
    }

    @Test("an option's line is its next step, else who it's waiting on, else Kumo's note")
    func optionLines() throws {
        let pursuit = try #require(Self.pursuit(try JSONValue(json: Self.jobSearch).decode()))
        func line(_ index: Int) -> String? {
            PursuitReading.line(
                of: pursuit.options[index], now: thursday, calendar: london, locale: english)
        }
        #expect(line(0) == "Technical · today 14:00 · Poppy")
        #expect(line(1) == "Waiting on them since 15 Oct")
        #expect(line(2) == "The online test went well")
        let later = Pursuit.Option(
            id: "c", name: "Citadel", stage: "Interviews",
            people: [.init(name: "Katia", role: "Recruiter")],
            next: .init(text: "Second round", at: Timestamp("2026-11-17T14:00:00Z")))
        #expect(
            PursuitReading.line(of: later, now: thursday, calendar: london, locale: english)
                == "Second round · Tue 17 Nov · Katia")
    }

    @Test("a pursuit's line says the option furthest along and the soonest next step")
    func pursuitLine() throws {
        let pursuit = try #require(Self.pursuit(try JSONValue(json: Self.jobSearch).decode()))
        let line = PursuitReading.line(pursuit, now: thursday, calendar: london, locale: english)
        #expect(line.detail == "QRT: Interviews")
        #expect(line.soon == "Technical today 14:00")
        // The next day, QRT's technical is past, and nothing else is set.
        let friday = Timestamp("2026-10-30T08:00:00Z")!.date
        #expect(
            PursuitReading.line(pursuit, now: friday, calendar: london, locale: english).soon
                == nil)
        #expect(PursuitReading.line(Pursuit(after: "A flat")) == (nil, nil))
    }

    // MARK: - Reading an occasion

    @Test("an occasion's prep counts your ticks, and its line says when and what's left")
    func occasionPrep() throws {
        let detail = try JSONValue(json: Self.dentist).decode(MotionDetail.self)
        let occasion = try #require(Self.occasion(detail))
        // Kumo wrote the Bupa card as done, and you ticked the form.
        #expect(OccasionReading.left(occasion, state: [:]).map(\.id) == ["forms"])
        #expect(OccasionReading.left(occasion, state: detail.state).isEmpty)
        #expect(OccasionReading.progress(occasion, state: [:]) == 0.5)
        let untick: MotionState = [OccasionReading.prepList: ["insurance": .init(done: false)]]
        #expect(OccasionReading.left(occasion, state: untick).map(\.id) == ["forms", "insurance"])
        let line = OccasionReading.line(
            occasion, state: detail.state, now: thursday, calendar: london, locale: english)
        #expect(line.when == "Fri 13 Nov" && line.left == 0)
        #expect(OccasionReading.people(occasion) == "With Dr Shah")
        #expect(OccasionReading.progress(Occasion(start: occasion.start), state: [:]) == nil)
    }

    @Test("when an occasion is reads in full, a whole day without a time")
    func occasionWhen() throws {
        func when(_ occasion: Occasion) -> String {
            OccasionReading.when(occasion, now: thursday, calendar: london, locale: english)
        }
        let start = Timestamp("2026-11-13T09:30:00Z")!
        #expect(
            when(Occasion(start: start, end: Timestamp("2026-11-13T10:15:00Z")))
                == "Friday 13 November · 09:30–10:15")
        #expect(when(Occasion(start: start)) == "Friday 13 November · 09:30")
        #expect(
            when(
                Occasion(
                    start: Timestamp("2026-11-13T18:00:00Z")!,
                    end: Timestamp("2026-11-15T12:00:00Z")))
                == "Fri 13 Nov, 18:00 – Sun 15 Nov, 12:00")
        let birthday = Timestamp("2026-11-14T00:00:00Z")!
        #expect(when(Occasion(start: birthday, allDay: true)) == "Saturday 14 November")
        // A whole-day end is the midnight after the last day.
        #expect(
            when(Occasion(start: birthday, end: Timestamp("2026-11-15T00:00:00Z"), allDay: true))
                == "Saturday 14 November")
        #expect(
            when(Occasion(start: birthday, end: Timestamp("2026-11-16T00:00:00Z"), allDay: true))
                == "Sat 14 – Sun 15 November")
        #expect(
            when(Occasion(start: Timestamp("2027-01-05T10:00:00Z")!))
                == "Tuesday, 5 January 2027 · 10:00")
        #expect(
            OccasionReading.line(
                Occasion(start: Timestamp("2026-10-30T00:00:00Z")!, allDay: true), state: [:],
                now: thursday, calendar: london, locale: english
            ).when == "Tomorrow")
        #expect(OccasionReading.people(Occasion(start: birthday)) == nil)
    }

    // MARK: - Reading a case

    @Test(
        "a case's timeline is newest first, and its line says what's next or how long it's waited")
    func caseReading() throws {
        let file = try #require(Self.caseFile(try JSONValue(json: Self.boiler).decode()))
        #expect(
            CaseReading.timeline(file).map(\.text) == [
                "Chased: no reply yet", "Emailed the landlord the fault code and a video",
                "The boiler showed fault F28; reset it twice",
            ])
        let line = CaseReading.line(file, now: thursday, calendar: london, locale: english)
        #expect(line.status == "Waiting on the landlord")
        #expect(line.soon == "Chase the agency Mon 09:00")
        let undated = CaseFile(
            problem: file.problem, status: file.status, waitingOn: file.waitingOn,
            next: .init(text: "Chase the agency"))
        #expect(
            CaseReading.line(undated, now: thursday, calendar: london, locale: english).soon
                == "since 22 Oct")
        #expect(CaseReading.line(CaseFile(problem: "", status: "Sorted")).soon == nil)
        // Entries at the same time keep Kumo's order.
        let at = Timestamp("2026-10-22T10:00:00Z")!
        let same = CaseFile(
            problem: "", status: "", timeline: [.init(at: at, text: "a"), .init(at: at, text: "b")])
        #expect(CaseReading.timeline(same).map(\.text) == ["a", "b"])
    }

    // MARK: - Times

    @Test("times read as today, tomorrow, a weekday, then a date, in the device's time zone")
    func times() {
        func when(_ text: String, first: Bool = true, calendar: Calendar? = nil) -> String {
            MatterReading.when(
                Timestamp(text)!, first: first, now: thursday, calendar: calendar ?? london,
                locale: english)
        }
        #expect(when("2026-10-29T14:00:00Z") == "Today 14:00")
        #expect(when("2026-10-29T14:00:00Z", first: false) == "today 14:00")
        #expect(when("2026-10-30T09:30:00Z") == "Tomorrow 09:30")
        #expect(when("2026-10-28T18:00:00Z") == "Yesterday 18:00")
        #expect(when("2026-11-02T09:00:00Z") == "Mon 09:00")
        #expect(when("2026-10-31T00:00:00Z") == "Sat")
        #expect(when("2026-11-17T14:00:00Z") == "Tue 17 Nov")
        #expect(when("2026-10-15T09:00:00Z") == "Thu 15 Oct")
        #expect(when("2027-02-01T09:00:00Z") == "1 Feb 2027")
        // 23:30 in London is half past midnight on Friday in Amsterdam.
        var amsterdam = Calendar(identifier: .gregorian)
        amsterdam.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        #expect(when("2026-10-29T23:30:00Z", calendar: amsterdam) == "Tomorrow 00:30")

        let since = Timestamp("2026-10-15T09:00:00Z")!
        #expect(
            MatterReading.waiting(
                .init(who: "Poppy", since: since), now: thursday, calendar: london, locale: english)
                == "Waiting on Poppy since 15 Oct")
        #expect(
            MatterReading.waiting(
                .init(who: "QRT", since: Timestamp("2026-10-29T07:00:00Z")!), now: thursday,
                calendar: london, locale: english) == "Waiting on QRT since today")
        #expect(
            MatterReading.day(
                Timestamp("2025-12-01T09:00:00Z")!, now: thursday, calendar: london,
                locale: english) == "1 Dec 2025")
        #expect(
            MatterReading.next(.init(text: "Send the CV"), now: thursday, calendar: london)
                == "Send the CV")
    }

    // MARK: - Ticking prep

    @Test("a tick on an occasion's prep goes to the box as the prep list, and shows at once")
    @MainActor
    func tickPrep() async throws {
        let stub = PrepStub(detail: try JSONValue(json: Self.dentist))
        let motions = Motions(
            client: stub.client,
            defaults: UserDefaults(suiteName: "matters-tests-\(UUID().uuidString)")!)
        let detail = try await motions.detail("dentist")
        let occasion = try #require(Self.occasion(detail))
        #expect(
            await motions.tick(
                "dentist", list: OccasionReading.prepList, item: "insurance", done: false))
        let state = try #require(motions.details["dentist"]?.state)
        #expect(OccasionReading.left(occasion, state: state).map(\.id) == ["insurance"])
        let patch = try #require(await stub.patches.first)
        #expect(patch == (try JSONValue(json: #"{"prep":{"insurance":{"done":false}}}"#)))
    }

    // MARK: - Samples

    private static func pursuit(_ detail: MotionDetail) -> Pursuit? {
        if case .pursuit(let pursuit) = detail.content { pursuit } else { nil }
    }

    private static func occasion(_ detail: MotionDetail) -> Occasion? {
        if case .occasion(let occasion) = detail.content { occasion } else { nil }
    }

    private static func caseFile(_ detail: MotionDetail) -> CaseFile? {
        if case .caseFile(let file) = detail.content { file } else { nil }
    }

    private static func detail(kind: String, content: String) -> String {
        """
        {"motion":{"id":"a-thing","kind":"\(kind)","title":"A thing",
          "summary":"Somewhere","status":"active","pinned":false,"version":1,
          "started_at":"2026-10-20T08:00:00.000Z","changed_at":"2026-10-20T08:00:00.000Z",
          "position":1},
         "content":\(content),"state":{},"changes":[]}
        """
    }

    /// Divy's job search.
    static let jobSearch = """
        {"motion":{"id":"job-search","kind":"pursuit","title":"Job search",
          "summary":"QRT technical today · Citadel waiting","status":"active","pinned":true,
          "version":4,"started_at":"2026-10-01T09:00:00.000Z",
          "changed_at":"2026-10-28T18:00:00.000Z","position":12},
         "content":{
          "after":"AI engineering or C++ HFT systems, at quant firms, in London or Amsterdam.",
          "play":["New reach-out: why you're excited, CV, offer a call.",
           "Interviews a week or two out if the type is new to you.",
           "Calls on WFH days; check work with you first.",
           "Off-target recruiters: a kind note on what you do want."],
          "options":[
           {"id":"qrt","name":"QRT","role":"Senior AI Engineer","stage":"Interviews",
            "stages":["Screened","Interviews","Awaiting answer","Offer"],
            "people":[{"name":"Poppy","role":"Recruiter","page":"memory:people/poppy"}],
            "next":{"text":"Technical","at":"2026-10-29T14:00:00Z"}},
           {"id":"citadel","name":"Citadel","role":"AI Engineering, FI","stage":"Screened",
            "stages":["Screened","Interviews","Awaiting answer","Offer"],
            "people":[{"name":"Katia","role":"Recruiter"}],
            "waiting_on":{"who":"them","since":"2026-10-15T09:00:00Z"}},
           {"id":"optiver","name":"Optiver","role":"Software Engineer","stage":"test done",
            "stages":["Test done","Interviews","Awaiting answer","Offer"],
            "note":"The online test went well"}]},
         "state":{},"changes":[{"version":4,"at":"2026-10-28T18:00:00.000Z",
          "note":"QRT moved Thursday to 2pm","position":12}]}
        """

    /// A dentist appointment, with one prep item you ticked.
    static let dentist = """
        {"motion":{"id":"dentist","kind":"occasion","title":"Dentist",
          "summary":"Fri 13 Nov, 09:30","status":"active","pinned":false,"version":2,
          "started_at":"2026-10-20T08:00:00.000Z","changed_at":"2026-10-28T18:20:00.000Z",
          "position":3},
         "content":{"start":"2026-11-13T09:30:00Z","end":"2026-11-13T10:15:00Z",
          "where":"Bright Smile Dental, 14 Upper Street","people":[{"name":"Dr Shah"}],
          "prep":[{"id":"forms","text":"Fill in the new-patient form"},
           {"id":"insurance","text":"Bring your Bupa card","done":true}],
          "check_in":true},
         "state":{"prep":{"forms":{"done":true}}},
         "changes":[{"version":2,"at":"2026-10-28T18:20:00.000Z",
          "note":"Moved to Fri 13, 9:30","position":3}]}
        """

    /// The boiler, waiting on the landlord.
    static let boiler = """
        {"motion":{"id":"boiler","kind":"case","title":"Boiler repair",
          "summary":"Waiting on the landlord","status":"active","pinned":false,"version":3,
          "started_at":"2026-10-21T19:00:00.000Z","changed_at":"2026-10-26T09:00:00.000Z",
          "position":7},
         "content":{"problem":"The boiler cuts out after ten minutes, so there's no hot water.",
          "status":"Waiting on the landlord",
          "waiting_on":{"who":"the landlord","since":"2026-10-22T10:00:00Z"},
          "timeline":[
           {"at":"2026-10-21T19:00:00Z","text":"The boiler showed fault F28; reset it twice"},
           {"at":"2026-10-22T10:00:00Z","text":"Emailed the landlord the fault code and a video"},
           {"at":"2026-10-26T09:00:00Z","text":"Chased: no reply yet"}],
          "next":{"text":"Chase the agency","at":"2026-11-02T09:00:00Z"}},
         "state":{},"changes":[]}
        """
}

extension JSONValue {
    fileprivate func decode() throws -> MotionDetail { try decode(MotionDetail.self) }
}

/// A server with one occasion: it gives its detail and takes ticks, keeping each patch it got.
private actor PrepStub: Transport {
    private var detail: JSONValue
    private(set) var patches: [JSONValue] = []

    init(detail: JSONValue) { self.detail = detail }

    nonisolated var client: ItoClient {
        ItoClient(
            address: try! ServerAddress("http://127.0.0.1:8787"), token: Token("t"), transport: self
        )
    }

    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        switch request.method {
        case .get:
            return try answer(detail)
        case .patch:
            let patch = try JSONValue(data: request.body ?? Data())
            patches.append(patch)
            var state = detail["state"]?.object ?? [:]
            for (list, items) in patch.object ?? [:] {
                var merged = state[list]?.object ?? [:]
                for (item, tick) in items.object ?? [:] { merged[item] = tick }
                state[list] = .object(merged)
            }
            var updated = detail.object ?? [:]
            updated["state"] = .object(state)
            detail = .object(updated)
            return try answer(JSONValue.object(["state": .object(state)]))
        default:
            return HTTPResponse(status: 404, headers: [:], body: Data())
        }
    }

    func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
        throw URLError(.unsupportedURL)
    }

    private func answer(_ json: JSONValue) throws -> HTTPResponse {
        HTTPResponse(
            status: 200, headers: ["content-type": "application/json"],
            body: try JSONEncoder().encode(json))
    }
}
