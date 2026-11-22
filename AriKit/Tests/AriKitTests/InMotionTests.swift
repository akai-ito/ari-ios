import AriKit
import Foundation
import Testing

/// In motion, rethought: each kind in its own shape, sections loud inside by Kumo's judgement,
/// Kumo's notes kept apart, charts only from real results, and honest endings in History.
@Suite("In motion, rethought")
struct InMotionTests {
    private let english = Locale(identifier: "en_GB")
    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }
    /// Saturday 21 November, the morning of the moved run.
    private let saturday = Timestamp("2026-11-21T08:00:00Z")!.date

    @Test("a role decodes in its one stage, with its dates, next step, facts and Kumo's notes")
    func role() throws {
        let detail = try JSONValue(json: Self.role).decode(MotionDetail.self)
        guard case .career(let career) = detail.content else {
            Issue.record("not a role")
            return
        }
        #expect(detail.motion.salience == .loud && detail.motion.section == .career)
        #expect(career.org == "Northwind" && career.stage == .interviewing)
        #expect(CareerReading.position(of: career) == 2)
        #expect(
            CareerReading.dates(of: career, locale: english) == ["2 Nov", "12 Nov", "19 Nov", nil])
        #expect(career.next?.link?.label == "The invite")
        #expect(career.rounds.map(\.status) == [.done, .next, .planned])
        #expect(career.facts.map(\.label) == ["Through", "Pay"])
        // A note in a shape this Ari can't read is skipped; the rest still read.
        #expect(detail.extras.notes.map(\.tag) == [.source, .guess, .ids])
        #expect(detail.extras.notes.first?.tag.name == "Source")
        #expect(
            CareerReading.countdown(
                to: try #require(career.next?.at), now: saturday, calendar: london) == "in 16 days")
    }

    @Test("an ended role sits on the pipeline where it got to")
    func endedRole() {
        let career = Career(
            org: "Halcyon", role: "Senior AI Engineer", stage: .ended,
            stages: [
                .lead: LocalTime("2026-10-01")!, .talking: LocalTime("2026-10-08")!,
                .interviewing: LocalTime("2026-10-15")!, .ended: LocalTime("2026-11-06")!,
            ])
        #expect(CareerReading.position(of: career) == 2)
    }

    @Test(
        "a week reads as a coach shows it: done solid, planned dotted, a moved run's ghost dashed")
    func week() throws {
        let block = try Self.block()
        let week = try #require(BodyReading.currentWeek(of: block, now: saturday, calendar: london))
        #expect(week.number == 1)
        #expect(BodyReading.weekLine(of: block, now: saturday, calendar: london) == "Week 1 of 2")
        let days = BodyReading.strip(
            week.week, in: block, state: [:], now: saturday, calendar: london)
        #expect(days.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(days.map(\.number) == [16, 17, 18, 19, 20, 21, 22])
        #expect(days[0].sessions.map(\.mark) == [.done])
        #expect(days[3].sessions.map(\.mark) == [.moved])
        #expect(days[5].isToday && days[5].sessions.map(\.mark) == [.planned])
        #expect(BodyReading.doneLine(week.week, state: [:]) == "3 of 4 done")
        #expect(BodyReading.timeLine(week.week, state: [:]) == "2h 31m of 3h 06m")
        let today = try #require(
            BodyReading.today(in: block, state: [:], now: saturday, calendar: london))
        #expect(today.id == "w1-sat")
        // Your tick wins over how Kumo wrote it.
        let ticked: MotionState = [BodyReading.sessionsList: ["w1-sat": .init(done: true)]]
        #expect(BodyReading.doneLine(week.week, state: ticked) == "4 of 4 done")
    }

    @Test("planned against done says how each measure went, from the session's own numbers")
    func plannedAgainstDone() throws {
        let block = try Self.block()
        let run = try #require(block.weeks[0].sessions.first { $0.id == "w1-tue" })
        let rows = BodyReading.comparison(run)
        #expect(rows.map(\.label) == ["Time", "Distance", "Pace", "Heart", "Felt"])
        #expect(
            rows.map(\.done) == [
                "31:12", "5.2 km", "5:59 /km", "146 avg", "easy, heavy legs at first",
            ])
        #expect(rows.map(\.verdict) == [.onPlan, .onPlan, .quick, .onPlan, nil])
        #expect(
            BodyReading.did(run, state: [:])
                == "31 min · 5.2 km · 5:59/km · 146 bpm · felt easy, heavy legs at first")
        let lift = try #require(block.weeks[0].sessions.first { $0.id == "w1-mon" })
        #expect(
            BodyReading.did(lift, state: [:]) == "Squat 3×5 at 80 · Bench 3×5 at 60 · felt 7/10")
    }

    @Test("a chart shows only where there's real data, and is never filled in")
    func charts() throws {
        let block = try Self.block()
        let hours = try #require(
            BodyReading.hours(block, state: [:], now: saturday, calendar: london))
        #expect(hours.map(\.number) == [1, 2])
        #expect(hours[0].isCurrent && hours[1].done == 0 && hours[1].planned > 0)
        // One run with a pace is no trend; two lifts with a squat are.
        #expect(BodyReading.pace(block, state: [:]) == nil)
        let load = try #require(BodyReading.load(block, state: [:]))
        #expect(load.exercise == "Squat" && load.points.map(\.value) == [80, 82.5])
        // A block with no lengths, results or sets has no charts at all.
        let bare = BodyBlock(weeks: [
            .init(
                id: "w1", start: LocalTime("2026-11-16")!,
                sessions: [
                    .init(
                        id: "a", date: LocalTime("2026-11-17")!, kind: .run, title: "Run",
                        done: true)
                ])
        ])
        #expect(BodyReading.hours(bare, state: [:], now: saturday, calendar: london) == nil)
        #expect(BodyReading.load(bare, state: [:]) == nil)
        #expect(BodyReading.results(bare) == nil)
    }

    @Test("sections keep their order, loudest big, quiet folded, 0.18's kinds where they belong")
    func sections() {
        let going = [
            Self.motion("quillmoor", .career, .normal, changed: "2026-11-20T09:00:00Z"),
            Self.motion("northwind", .career, .loud, changed: "2026-11-01T09:00:00Z"),
            Self.motion("tindlewick-lead", .career, .quiet),
            Self.motion("old-search", .pursuit, .normal, changed: "2026-11-19T09:00:00Z"),
            Self.motion("back-to-rhythm", .training, .normal),
            Self.motion("visa", .caseFile, .normal),
            Self.motion("japan", .trip, .quiet),
            Self.motion("mystery", MotionKind(rawValue: "garden"), .normal),
        ]
        let sections = InMotionReading.sections(going)
        #expect(sections.map(\.kind) == [.career, .body, .trips, .projects, .learning, .other])
        let career = sections[0]
        #expect(career.lead?.id == "northwind")
        #expect(career.rows.map(\.id) == ["quillmoor", "old-search"])
        #expect(career.quieter.map(\.id) == ["tindlewick-lead"])
        #expect(sections[1].lead?.id == "back-to-rhythm")
        // A section with only quiet things has nothing big, and folds them all.
        #expect(sections[2].lead == nil && sections[2].quieter.map(\.id) == ["japan"])
        #expect(sections[3].isEmpty && sections[4].isEmpty)
        #expect(sections[5].all.map(\.id.rawValue).sorted() == ["mystery", "visa"])
    }

    @Test("History tells how each ended, by month, and never shows a copy, a test or admin")
    func history() {
        let done = [
            Self.motion("sub-20", .body, .normal, outcome: .notMet, ended: "2026-11-09T09:00:00Z"),
            Self.motion(
                "florence", .trip, .normal, outcome: .achieved, ended: "2026-11-09T08:00:00Z"),
            Self.motion(
                "northwind-copy", .career, .quiet, outcome: .duplicate,
                ended: "2026-11-08T09:00:00Z"),
            Self.motion("a-test", .other, .normal, outcome: .test, ended: "2026-11-07T09:00:00Z"),
            Self.motion(
                "dentist", .other, .normal, outcome: .elsewhere, ended: "2026-11-07T09:00:00Z"),
            Self.motion(
                "spanish", .learning, .normal, outcome: .letGo, ended: "2026-10-20T09:00:00Z"),
            Self.motion(
                "old-search", .pursuit, .normal, outcome: .merged, ended: "2026-10-31T09:00:00Z"),
            // Ended before 0.19, with no outcome yet: shown as ended, never as achieved.
            Self.motion(
                "morning-runs", .training, .normal, outcome: nil, ended: "2026-10-12T09:00:00Z"),
        ]
        let months = InMotionReading.history(done, calendar: london)
        #expect(months.count == 2)
        #expect(months[0].items.map(\.id) == ["sub-20", "florence"])
        #expect(months[1].items.map(\.id) == ["old-search", "spanish", "morning-runs"])
        let tally = InMotionReading.tally(done)
        #expect(tally.map(\.outcome.name) == ["Achieved", "Not met", "Let go", "Merged", "Ended"])
        #expect(tally.map(\.count) == [1, 1, 1, 1, 1])
        #expect(MotionOutcome(rawValue: "postponed").isShown)
        #expect(MotionOutcome(rawValue: "postponed").name == "Ended")
    }

    @Test("a thing from before 0.19, with no salience, reads as normal")
    func olderThing() throws {
        let motion = try JSONValue(
            json: """
                {"id":"trip","kind":"trip","title":"Rome","summary":"Soon","status":"active",
                 "pinned":true,"version":1,"started_at":"2026-10-20T08:00:00.000Z",
                 "changed_at":"2026-10-20T08:00:00.000Z","position":1}
                """
        ).decode(Motion.self)
        #expect(motion.salience == .normal && motion.outcome == nil && motion.section == .trips)
    }

    // MARK: - Samples

    private static func motion(
        _ id: String, _ kind: MotionKind, _ salience: Salience, outcome: MotionOutcome? = nil,
        changed: String = "2026-11-10T09:00:00Z", ended: String? = nil
    ) -> Motion {
        Motion(
            id: MotionID(id), kind: kind, title: id, summary: "",
            status: ended == nil ? .active : .done,
            salience: salience, outcome: outcome, startedAt: Timestamp("2026-10-01T09:00:00Z")!,
            changedAt: Timestamp(changed)!, doneAt: ended.flatMap(Timestamp.init))
    }

    private static func block() throws -> BodyBlock {
        let detail = try JSONValue(json: hybrid).decode(MotionDetail.self)
        guard case .body(let block) = detail.content else { throw CancellationError() }
        return block
    }

    /// A role in the pipeline, with a note in a shape from a newer server.
    private static let role = """
        {"motion":{"id":"northwind","kind":"career","title":"Northwind",
          "summary":"Virtual 1 · Python PR review","status":"active","pinned":true,"salience":"loud",
          "version":3,"started_at":"2026-11-02T08:00:00.000Z","changed_at":"2026-11-19T08:00:00.000Z",
          "position":4},
         "content":{"org":"Northwind","role":"Software Engineer, Agents","where":"London",
          "stage":"interviewing",
          "stages":{"lead":"2026-11-02","talking":"2026-11-12","interviewing":"2026-11-19"},
          "next":{"text":"Virtual 1 · Python PR review","at":"2026-12-07T14:00","end":"2026-12-07T15:15",
           "link":{"label":"The invite","url":"message://%3Cinvite-7%40northwind.example%3E"}},
          "rounds":[{"id":"recruiter","title":"Recruiter","status":"done"},
           {"id":"virtual-1","title":"Virtual 1","status":"next","at":"2026-12-07T14:00"},
           {"id":"on-site","title":"On site","status":"planned"}],
          "facts":[{"id":"through","label":"Through","value":"Applied on their site"},
           {"id":"pay","label":"Pay","value":"£120–150k and equity, said on the call"}],
          "notes":[{"id":"invite","tag":"source","text":"The invite, 60 minutes.","at":"2026-11-19"},
           {"id":"odd","tag":"source"},
           {"id":"repo","tag":"guess","text":"Likely a shared repo with a planted bug."},
           {"id":"ids","tag":"ids","text":"calendar 7c1e9b2a@northwind.example"}]},
         "state":{},"changes":[]}
        """

    /// A hybrid block's first two weeks: Monday's lift and Tuesday's run from the Watch, Wednesday's
    /// lift as planned, Thursday's run moved to Saturday.
    private static let hybrid = """
        {"motion":{"id":"hybrid-restart","kind":"body","title":"Hybrid restart",
          "summary":"Three done this week. Today's easy run is the last.","status":"active",
          "pinned":true,"salience":"loud","version":4,"started_at":"2026-11-14T08:00:00.000Z",
          "changed_at":"2026-11-19T08:00:00.000Z","position":4},
         "content":{"plan":"2 lifts and 2 easy runs a week","hours_a_week":7,
          "weeks":[
           {"id":"week-1","start":"2026-11-16","sessions":[
             {"id":"w1-mon","date":"2026-11-16","kind":"lift","title":"Lift A",
              "plan":"Squat 3×5 at 80 · bench 3×5 at 60","planned":{"minutes":60},"done":true,
              "result":{"source":"you","minutes":60,"effort":7,
               "sets":[{"exercise":"Squat","sets":3,"reps":5,"load_kg":80},
                {"exercise":"Bench","sets":3,"reps":5,"load_kg":60}]}},
             {"id":"w1-tue","date":"2026-11-17","kind":"run","title":"Easy run",
              "plan":"30 min easy · heart under 150",
              "planned":{"minutes":30,"distance_km":5,"pace":{"from":"6:00","to":"6:20"},
               "heart_under":150,"effort":"easy"},
              "done":true,
              "result":{"source":"watch","at":"07:12","minutes":31.2,"distance_km":5.2,"pace":"5:59",
               "heart_avg":146,"heart_max":158,"zones":[{"zone":2,"minutes":21}],
               "splits":["6:08","6:01","5:57","5:55","5:54"],"felt":"easy, heavy legs at first"}},
             {"id":"w1-wed","date":"2026-11-18","kind":"lift","title":"Lift B",
              "planned":{"minutes":60},"done":true,
              "result":{"source":"you","sets":[{"exercise":"Squat","sets":3,"reps":5,"load_kg":82.5}]}},
             {"id":"w1-sat","date":"2026-11-21","kind":"run","title":"Easy run",
              "plan":"35 min easy · heart under 150","planned":{"minutes":35,"heart_under":150},
              "moved_from":"2026-11-19","done":false}]},
           {"id":"week-2","start":"2026-11-23","sessions":[
             {"id":"w2-mon","date":"2026-11-23","kind":"lift","title":"Lift A",
              "planned":{"minutes":60},"done":false}]}],
          "reasons":[{"id":"moved-thu","date":"2026-11-19","change":"Moved Thursday's run to Saturday",
           "because":"5h sleep on Wednesday"}]},
         "state":{},"changes":[]}
        """
}
