import AriKit
import Foundation
import Testing

/// Kumo's dream and Understanding you: the stores behind the moon and sun, the dream's page and
/// Getting to know you, played against the golden transcripts, and the readings that decide what
/// the Desk shows.
@Suite("The dream and Understanding you")
@MainActor
struct DreamTests {
    // MARK: The dream

    @Test("Scenario 92: the morning after, the record opens, is seen, and a line is taken back")
    func aNightsDream() async throws {
        let transcript = try Fixtures.transcript("92-a-nights-dream")
        let server = TranscriptServer(transcript, only: Self.dreamRoutes)
        let dreams = Dreams(client: server.client)
        // The stream brings the record while you sleep: with nothing read yet, it asks for all of
        // the dream.
        for event in transcript.events.map(\.event) {
            if case .snapshot = event.payload { continue }
            dreams.apply(event)
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while dreams.state == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let dream = try #require(dreams.latest)
        #expect(dream.isNew && dream.trigger == .scheduled && dream.day == "2026-11-26")
        #expect(dreams.state?.time == "04:00")
        #expect(dream.groups.map(\.group) == [.planned, .noticed, .saved])
        let saturday = try #require(dream.lines.first { $0.done == "d_0003_45037" })
        #expect(saturday.group == .planned && saturday.undo && saturday.wakeUp != nil)

        await dreams.see(dream.id)
        #expect(dreams.latest?.isNew == false, "seen at once, and as the server keeps it")

        let undone = try await dreams.undo(saturday)
        #expect(undone?.text.hasPrefix("Undone: ") == true)
        let after = try #require(dreams.latest?.lines.first { $0.done == "d_0003_45037" })
        #expect(after.undone && !after.undo)
        #expect(dreams.latest?.isNew == false)

        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("Scenario 93: Dream now shows the dream under way, then its record, and the time moves")
    func dreamNow() async throws {
        let transcript = try Fixtures.transcript("93-dream-now")
        let server = TranscriptServer(transcript, only: Self.dreamRoutes)
        let dreams = Dreams(client: server.client)
        await dreams.refresh()
        #expect(dreams.latest == nil && dreams.dreaming == nil)

        try await dreams.dreamNow()
        #expect(dreams.dreaming?.trigger == .manual)

        let finished = transcript.events.map(\.event).filter {
            if case .dreamFinished = $0.payload { true } else { false }
        }
        try #require(finished.count == 2)
        dreams.apply(finished[0])
        #expect(dreams.dreaming == nil)
        #expect(dreams.latest?.trigger == .manual && dreams.latest?.isNew == true)

        // Dream now is an extra: the night's dream still runs, over what came since.
        await dreams.refresh()
        dreams.apply(finished[1])
        #expect(dreams.latest?.trigger == .scheduled)

        await dreams.refresh()
        try await dreams.setTime("03:30")
        #expect(dreams.state?.time == "03:30")
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("a refresh that fails keeps the dream it had")
    func failedRefresh() async throws {
        let transcript = try Fixtures.transcript("93-dream-now")
        // Only its three reads of the dream: a fourth finds the server gone.
        let server = TranscriptServer(transcript) { $0 == .dream }
        let dreams = Dreams(client: server.client)
        await dreams.refresh()
        await dreams.refresh()
        await dreams.refresh()
        let shown = try #require(dreams.state)
        await dreams.refresh()
        #expect(dreams.state == shown && dreams.load == .loaded)
    }

    private nonisolated static func dreamRoutes(_ route: Route) -> Bool {
        switch route {
        case .dream, .dreamNow, .dreamTime, .seeDream, .undo: true
        default: false
        }
    }

    // MARK: Understanding you

    @Test("Scenario 97: questions arrive quietly, one is set aside, one answered, one settled")
    func understandingYou() async throws {
        let transcript = try Fixtures.transcript("97-understanding-you")
        let server = TranscriptServer(transcript, only: Self.understandingRoutes)
        let understanding = UnderstandingYou(client: server.client)
        let events = transcript.events.map(\.event)
        let questions = events.filter {
            if case .questionChanged = $0.payload { true } else { false }
        }

        await understanding.refresh()
        #expect(understanding.current?.tracks.map(\.name) == ["Planning with you"])
        #expect(understanding.shown().isEmpty)

        // Kumo adds two, which every app hears.
        for event in questions.prefix(2) { understanding.apply(event) }
        let shown = understanding.shown()
        #expect(shown.count == 2)
        let restful = try #require(shown.first)
        let packed = try #require(shown.last)
        #expect(restful.options.count == 4 && !restful.understood.isEmpty)

        await understanding.refresh()
        let later = try await understanding.notNow(packed.id)
        #expect(later.laterAt != nil && later.isOpen)
        #expect(understanding.shown().map(\.id) == [restful.id, packed.id], "set aside goes last")

        let reply = QuestionReply(
            picked: ["Unplanned time", "Being outdoors"],
            text: "A slow morning and a long walk, with nothing booked before noon.")
        // The filing arrives on the stream before the answer's own response.
        for event in questions.dropFirst(3).prefix(2) { understanding.apply(event) }
        let answered = try await understanding.answer(restful.id, reply)
        #expect(answered.state == .answered && answered.answer?.picked.count == 2)
        #expect(understanding.settled.first?.filed != nil, "an answer after its filing keeps it")
        #expect(understanding.shown().map(\.id) == [packed.id])

        await understanding.refresh()
        for event in questions.dropFirst(5) { understanding.apply(event) }
        #expect(understanding.shown().isEmpty)
        #expect(understanding.settled.first?.state == .settled)
        #expect(understanding.settled.first?.note != nil)

        await understanding.refresh()
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("an answer is evidence on its track, naming the question")
    func answeredEvidence() throws {
        let transcript = try Fixtures.transcript("97-understanding-you")
        let work = try #require(
            transcript.steps.compactMap { step -> KumoWork? in
                guard case .server(let response) = step, let body = response.body else {
                    return nil
                }
                return try? body.decode(KumoWork.self)
            }.first)
        let evidence = try #require(work.tracks.first?.evidence.first)
        #expect(evidence.kind == .answered && evidence.question != nil)
    }

    @Test("a reply sends only what you said")
    func replyEncodes() throws {
        #expect(
            try JSONValue(encoding: QuestionReply(noneFit: true))
                == JSONValue(json: #"{"none_fit":true}"#))
        #expect(
            try JSONValue(encoding: QuestionReply(text: "Mostly", notSure: true))
                == JSONValue(json: #"{"text":"Mostly","not_sure":true}"#))
        #expect(QuestionReply().isEmpty)
        #expect(!QuestionReply(picked: ["Sleep"]).isEmpty)
    }

    private nonisolated static func understandingRoutes(_ route: Route) -> Bool {
        switch route {
        case .understanding, .answerQuestion, .notNowQuestion: true
        default: false
        }
    }

    // MARK: The sky over Kumo's shoulder

    private static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.london.date(
            from: DateComponents(year: 2026, month: 12, day: day, hour: hour, minute: minute))!
    }

    private func dream(endedAt: Date, seen: Bool, trigger: DreamTrigger = .scheduled) -> Dream {
        Dream(
            id: "z_1", day: "2026-11-30", trigger: trigger,
            startedAt: Timestamp(endedAt.addingTimeInterval(-1800)), endedAt: Timestamp(endedAt),
            lines: [DreamLine(group: .planned, text: "Your run moves to 07:30")],
            seenAt: seen ? Timestamp(endedAt.addingTimeInterval(3600)) : nil)
    }

    private func state(_ latest: Dream?, dreaming: Bool = false) -> DreamState {
        DreamState(
            time: "04:00", nextAt: Timestamp(at(2, 4)),
            dreaming: dreaming ? .init(since: Timestamp(at(1, 4)), trigger: .scheduled) : nil,
            latest: latest)
    }

    @Test("the moon from the dream until it's seen, the sun by day, amber in the evening")
    func sky() {
        let night = dream(endedAt: at(1, 4, 31), seen: false)
        let calendar = Self.london
        #expect(
            DreamReading.sky(now: at(1, 7, 40), state: state(night), calendar: calendar) == .moon)
        #expect(
            DreamReading.sky(now: at(1, 4, 31), state: state(night), calendar: calendar) == .moon)
        let seen = dream(endedAt: at(1, 4, 31), seen: true)
        #expect(
            DreamReading.sky(now: at(1, 16, 30), state: state(seen), calendar: calendar) == .sun)
        #expect(
            DreamReading.sky(now: at(1, 21, 30), state: state(seen), calendar: calendar) == .dusk)
        #expect(
            DreamReading.sky(now: at(1, 21, 30), state: state(night), calendar: calendar) == .moon,
            "unseen, the moon stays into the evening")
    }

    @Test("nothing from midnight until the dream, nor while it runs")
    func nightSky() {
        let calendar = Self.london
        let lastNight = dream(endedAt: at(1, 4, 31), seen: false)
        #expect(
            DreamReading.sky(now: at(2, 3, 50), state: state(lastNight), calendar: calendar)
                == .none)
        #expect(
            DreamReading.sky(
                now: at(2, 4, 6), state: state(lastNight, dreaming: true), calendar: calendar)
                == .none)
        // An early dream you asked for stands in for the night's: after the dream time, its moon.
        let early = dream(endedAt: at(1, 23, 15), seen: false, trigger: .manual)
        #expect(
            DreamReading.sky(now: at(2, 2, 0), state: state(early), calendar: calendar) == .none)
        #expect(
            DreamReading.sky(now: at(2, 6, 0), state: state(early), calendar: calendar) == .moon)
    }

    @Test("Kumo sleeps from midnight until morning, and while it dreams")
    func asleep() {
        let calendar = Self.london
        #expect(DreamReading.asleep(now: at(1, 3, 50), state: state(nil), calendar: calendar))
        #expect(!DreamReading.asleep(now: at(1, 7, 40), state: state(nil), calendar: calendar))
        #expect(
            DreamReading.asleep(
                now: at(1, 14, 20), state: state(nil, dreaming: true), calendar: calendar),
            "a dream you asked for by day")
    }

    @Test("the page leads with the dream while it's new, or one you asked for today")
    func leads() {
        let calendar = Self.london
        let new = dream(endedAt: at(1, 4, 31), seen: false)
        let seen = dream(endedAt: at(1, 4, 31), seen: true)
        let asked = dream(endedAt: at(1, 14, 20), seen: true, trigger: .manual)
        #expect(DreamReading.leadsWithDream(new, now: at(1, 16), calendar: calendar))
        #expect(!DreamReading.leadsWithDream(seen, now: at(1, 16), calendar: calendar))
        #expect(DreamReading.leadsWithDream(asked, now: at(1, 16), calendar: calendar))
        #expect(!DreamReading.leadsWithDream(asked, now: at(2, 9), calendar: calendar))
    }

    @Test("words to drift up are names, short enough to read in dots")
    func words() {
        #expect(
            DreamReading.words(from: ["Northwind prep", "Mira's birthday", "Shoes", "the long run"])
                == ["Northwind", "Mira", "Shoes", "long"])
        #expect(DreamReading.pageWord("memory:people/leo") == "Leo")
        #expect(DreamReading.pageWord("memory:journal/2026-11-26") == "Journal")
    }

    @Test("the weave of scenario 92: its strands, the pages it tied and tomorrow's knots")
    func weave() throws {
        let transcript = try Fixtures.transcript("92-a-nights-dream")
        let finished = try #require(
            transcript.events.compactMap { logged -> Dream? in
                if case .dreamFinished(let event) = logged.event.payload {
                    event.dream
                } else {
                    nil
                }
            }.first)
        let desk = try #require(
            transcript.events.compactMap { logged -> Desk? in
                if case .deskChanged(let event) = logged.event.payload { event.desk } else { nil }
            }.max { $0.plans.count < $1.plans.count })
        let scene = WeaveScene.make(
            day: "Thursday", threads: ["The long run with Leo"], mailRead: 6, dream: finished,
            plans: desk.plans)
        #expect(scene.strands == ["Main chat", "The long run with Leo", "Mail · 6 you read"])
        #expect(scene.gathering == "Gathering Thursday: two threads, six emails you read.")
        #expect(scene.pages.map(\.word) == ["Journal"])
        #expect(scene.pages.first?.note == "Thursday")
        #expect(!scene.plans.isEmpty && scene.isRecorded)
        #expect(scene.tomorrow.first == "Moved the check on your legs to 09:30, after your lie-in")

        let live = WeaveScene.make(day: "Thursday", threads: [], mailRead: 0, dream: nil)
        #expect(!live.isRecorded && live.pages.isEmpty && live.strands == ["Main chat"])
    }

    // MARK: Plans

    private func plan(
        _ id: String, _ when: Date, title: String? = nil, repeats: [Weekday]? = nil,
        time: String = "23:45"
    ) -> WakeUp {
        WakeUp(
            id: WakeUpID(id), at: Timestamp(when), title: title, what: "Look at \(id)",
            why: "Because", repeat: repeats.map { Repeat(days: $0, time: time) },
            source: WakeUpSource(kind: .chat, title: ""), setAt: Timestamp(at(1, 1)))
    }

    @Test("plans group by day, each repeat once, tonight's also under Today")
    func planGroups() {
        // Tuesday 1 December 2026.
        let now = at(1, 16, 31)
        let calendar = Self.london
        let aligner = plan("aligner", at(1, 23, 45), title: "Aligner change", repeats: [.tuesday])
        let basil = plan("basil", at(2, 9), repeats: [.wednesday, .saturday], time: "09:00")
        let groups = PlanReading.group(
            [
                plan("ask", at(1, 18, 45)), aligner, plan("sam", at(2, 10)), basil,
                plan("gift", at(3, 12)), plan("far", at(9, 9)),
            ], now: now, calendar: calendar)
        #expect(groups.today.map(\.id) == ["ask", "aligner"])
        #expect(groups.tomorrow.map(\.id) == ["sam"])
        #expect(groups.laterThisWeek.map(\.id) == ["gift"])
        #expect(groups.later.map(\.id) == ["far"])
        #expect(groups.repeating.map(\.id) == ["aligner", "basil"])
        #expect(groups.beyondToday == 4)
        #expect(!groups.allThisWeek)
        #expect(aligner.shownTitle == "Aligner change" && basil.shownTitle == "Look at basil")
    }

    @Test("a repeat's coming times, and skipping tonight's")
    func comingTimes() {
        let calendar = Self.london
        let aligner = plan("aligner", at(1, 23, 45), repeats: [.tuesday])
        let times = PlanReading.nextTimes(of: aligner, calendar: calendar)
        #expect(times == [at(1, 23, 45), at(8, 23, 45), at(15, 23, 45), at(22, 23, 45)])
        #expect(PlanReading.afterSkipping(aligner, calendar: calendar) == at(8, 23, 45))
        let once = plan("once", at(1, 18))
        #expect(PlanReading.nextTimes(of: once, calendar: calendar) == [at(1, 18)])
        #expect(PlanReading.afterSkipping(once, calendar: calendar) == nil)
    }

    @Test("a plan from a server before titles shows what it's for; a title encodes in a change")
    func titles() throws {
        let json = #"""
            {"id":"w_1","at":"2026-12-01T18:45:00.000Z","what":"Ask how Northwind went","why":"It ends at 15:00",
             "by":"kumo","source":{"kind":"chat","title":""},"set_at":"2026-12-01T08:00:00.000Z"}
            """#
        let old = try JSONValue(json: json).decode(WakeUp.self)
        #expect(old.title == nil && old.shownTitle == "Ask how Northwind went")
        #expect(
            try JSONValue(encoding: WakeUpChange(title: "Ask about Northwind"))
                == JSONValue(json: #"{"title":"Ask about Northwind"}"#))
    }
}
