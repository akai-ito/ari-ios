import AriKit
import Foundation
import Testing

/// How a training block reads: the week you're in, today's session, your best and how far is left.
@Suite("Training")
struct TrainingTests {
    private let english = Locale(identifier: "en_GB")
    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }
    /// Wednesday 28 October, intervals day.
    private let wednesday = Timestamp("2026-10-28T07:30:00Z")!.date

    @Test("a training block decodes as one, from the sub-20 5K sample")
    func decodes() throws {
        let detail = try JSONValue(json: Self.detail).decode(MotionDetail.self)
        guard case .training(let training) = detail.content else {
            Issue.record("not training")
            return
        }
        #expect(training.goal.title == "Sub-20 5K" && training.goal.by == "2026-11-30")
        #expect(training.weeks.map(\.id) == ["week-5", "week-6", "week-7"])
        #expect(training.weeks[1].sessions[1].kind == .intervals)
        #expect(training.results.last?.note == "Windy")
    }

    @Test("Scenario 64: your tick goes to the box, and Ari keeps the week's line up at once")
    func scenario() async throws {
        let transcript = try Fixtures.transcript("64-a-training-block")
        let server = TranscriptServer(
            transcript,
            only: { route in
                switch route {
                case .motion, .motionState: true
                default: false
                }
            })
        let state = try await server.client.tick(
            "sub-20-5k", list: TrainingReading.sessionsList, item: "w6-wed", done: true)
        #expect(state[TrainingReading.sessionsList]?["w6-wed"]?.done == true)
        let detail = try await server.client.motion("sub-20-5k")
        guard case .training(let training) = detail.content else {
            Issue.record("not training")
            return
        }
        #expect(training.weeks.count == 10)
        let line = TrainingReading.line(
            training, state: detail.state, now: wednesday, calendar: london)
        #expect(line.when == "Week 6 of 10" && line.today == "Intervals done")
        #expect(
            TrainingReading.currentWeek(of: training, now: wednesday, calendar: london)?.week.note
                == "Intervals done. Keep tomorrow easy; Friday's tempo is next.")
        #expect(detail.changes.first?.note == "Week 6: intervals done")
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("the line says the week you're in and today's session, done once you tick it")
    func line() throws {
        let training = try Self.training()
        let line = TrainingReading.line(training, state: [:], now: wednesday, calendar: london)
        #expect(line.name == "Sub-20 5K")
        #expect(line.when == "Week 2 of 3")
        #expect(line.today == "Intervals today")
        let ticked: MotionState = [
            TrainingReading.sessionsList: ["wed-intervals": .init(done: true)]
        ]
        #expect(
            TrainingReading.line(training, state: ticked, now: wednesday, calendar: london).today
                == "Intervals done")
        let thursday = Timestamp("2026-10-29T12:00:00Z")!.date
        #expect(
            TrainingReading.line(training, state: [:], now: thursday, calendar: london).today == nil
        )
        #expect(
            TrainingReading.subtitle(training, now: wednesday, calendar: london, locale: english)
                == "By 30 November · week 2 of 3")
    }

    @Test("before the block it's on its first week, and after it on its last")
    func edges() throws {
        let training = try Self.training()
        let before = Timestamp("2026-10-01T12:00:00Z")!.date
        #expect(
            TrainingReading.currentWeek(of: training, now: before, calendar: london)?.number == 1)
        let after = Timestamp("2026-12-20T12:00:00Z")!.date
        #expect(
            TrainingReading.currentWeek(of: training, now: after, calendar: london)?.number == 3)
    }

    @Test("your best is the fastest time, and how far is left is the gap to the target")
    func best() throws {
        let training = try Self.training()
        #expect(TrainingReading.best(training)?.result == "20:41")
        #expect(TrainingReading.toGo(training) == "42 s to go")
        let slower = Training(
            goal: .init(title: "Sub-20 5K", target: "19:59"),
            results: [.init(id: "a", date: "2026-09-01", result: "21:30")])
        #expect(TrainingReading.toGo(slower) == "1 min 31 s to go")
        let reached = Training(
            goal: .init(title: "Sub-20 5K", target: "19:59"),
            results: [
                .init(id: "a", date: "2026-09-01", result: "20:30"),
                .init(id: "b", date: "2026-11-29", result: "19:51"),
            ])
        #expect(TrainingReading.toGo(reached) == "Goal reached")
    }

    @Test("a goal to get above reads the other way, and a number isn't a time")
    func higherIsBetter() {
        let lift = Training(
            goal: .init(title: "100 kg deadlift", target: "100"),
            results: [
                .init(id: "a", date: "2026-09-01", result: "90"),
                .init(id: "b", date: "2026-10-01", result: "95"),
            ])
        #expect(TrainingReading.best(lift)?.result == "95")
        #expect(TrainingReading.toGo(lift) == nil)
        #expect(TrainingReading.value("1:02:03") == 3723)
        #expect(TrainingReading.value("Felt strong") == nil)
    }

    @Test("progress counts sessions done, leaving out rest days")
    func progress() throws {
        let training = try Self.training()
        // Week 5's three runs and Monday of week 6 are done, of seven sessions that aren't rest.
        #expect(TrainingReading.progress(training, state: [:]) == 4.0 / 7.0)
        let ticked: MotionState = [
            TrainingReading.sessionsList: ["wed-intervals": .init(done: true)]
        ]
        #expect(TrainingReading.progress(training, state: ticked) == 5.0 / 7.0)
        #expect(
            TrainingReading.weekday(of: training.weeks[1].sessions[1], locale: english) == "Wed")
    }

    // MARK: - The sample

    private static func training() throws -> Training {
        let detail = try JSONValue(json: detail).decode(MotionDetail.self)
        guard case .training(let training) = detail.content else { throw CancellationError() }
        return training
    }

    /// ito-core's sub-20 5K sample, with a week either side.
    private static let detail = """
        {"motion":{"id":"sub-20-5k","kind":"training","title":"Sub-20 5K","summary":"Week 6 of 10",
          "status":"active","pinned":true,"version":1,"started_at":"2026-10-20T08:00:00.000Z",
          "changed_at":"2026-10-20T08:00:00.000Z","position":4},
         "content":{"goal":{"title":"Sub-20 5K","target":"19:59","by":"2026-11-30"},
          "weeks":[
           {"id":"week-5","start":"2026-10-19","focus":"Base","sessions":[
             {"id":"w5-easy","date":"2026-10-19","kind":"easy","title":"Easy run","done":true},
             {"id":"w5-tempo","date":"2026-10-21","kind":"tempo","title":"Tempo","done":true},
             {"id":"w5-rest","date":"2026-10-22","kind":"rest","title":"Rest","done":false},
             {"id":"w5-long","date":"2026-10-25","kind":"long","title":"Long run","done":true}]},
           {"id":"week-6","start":"2026-10-26","focus":"Speed",
            "note":"Two hard days, so keep the easy runs easy.","sessions":[
             {"id":"mon-easy","date":"2026-10-26","kind":"easy","title":"Easy run",
              "detail":"6 km, conversational","done":true},
             {"id":"wed-intervals","date":"2026-10-28","kind":"intervals","title":"Intervals",
              "detail":"6 × 800 m at 3:50/km · 90 s jog · 2 km warm-up","done":false},
             {"id":"fri-tempo","date":"2026-10-30","kind":"tempo","title":"Tempo",
              "detail":"4 km at 4:05/km","done":false},
             {"id":"sun-long","date":"2026-11-01","kind":"long","title":"Long run",
              "detail":"12 km easy","done":false}]},
           {"id":"week-7","start":"2026-11-02","focus":"Sharpen","sessions":[]}],
          "results":[
           {"id":"parkrun-oct-3","date":"2026-10-03","result":"21:02"},
           {"id":"parkrun-oct-24","date":"2026-10-24","result":"20:41","note":"Windy"}]},
         "state":{},"changes":[{"version":1,"at":"2026-10-20T08:00:00.000Z",
          "note":"Started the block","position":4}]}
        """
}
