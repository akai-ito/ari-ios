import AriKit
import Clocks
import Foundation
import Testing

/// The session's Desk and getting started, beside the one conversation on the same stream: what a
/// snapshot replaces, the Desk's and getting started's changes and requests, and the outbox across
/// a restart. Each test talks to a real ``Session`` through the scripted transport.
@MainActor
@Suite("The Desk and getting started")
struct SessionDeskTests {
    @Test("a snapshot replaces the conversation, the Desk and getting started")
    func snapshot() async throws {
        let bench = try Bench()
        defer { bench.close() }
        try await bench.open(
            with: Self.snapshot("e_10", messages: [Self.message("u_1", "Janki's birthday", 1)]))
        let session = bench.session
        #expect(session.conversation.entries.map(\.text) == ["Janki's birthday"])
        #expect(session.desk == Desk())
        #expect(session.onboarding == nil)

        let desk = #"{"coming_up":[],"waiting":[\#(Self.question("k_1"))]}"#
        try await bench.push(
            Self.snapshot(
                "e_20", messages: [Self.message("u_2", "QRT on Thursday", 4)], desk: desk,
                onboarding: #"{"state":"reading","progress":{"mails_read":3,"mails_total":90}}"#))

        #expect(session.conversation.entries.map(\.text) == ["QRT on Thursday"])
        #expect(session.conversation.cursor == "e_20")
        #expect(session.desk?.waiting.map(\.id) == ["k_1"])
        #expect(session.onboarding?.state == .reading)

        // One without getting started leaves none.
        try await bench.push(Self.snapshot("e_21"))
        #expect(session.onboarding == nil && session.desk == Desk())
    }

    @Test("desk.changed replaces the whole Desk, and the stream resumes after it")
    func deskChanged() async throws {
        let bench = try Bench()
        defer { bench.close() }
        try await bench.open(with: Self.snapshot("e_10"))

        let desk = #"""
            {"briefing":{"id":"b_1","kind":"morning","at":"2026-11-10T07:40:00.000Z","lines":[{"text":"QRT moved to 2pm."}],"handled":3},
             "coming_up":[],"waiting":[\#(Self.question("k_1"))]}
            """#
        try await bench.push(
            #"{"id":"e_11","type":"desk.changed","at":"2026-11-10T07:40:00.000Z","desk":\#(desk)}"#)

        let session = bench.session
        #expect(session.desk?.briefing?.lines.map(\.text) == ["QRT moved to 2pm."])
        #expect(session.desk?.waiting.map(\.id) == ["k_1"])
        #expect(session.conversation.cursor == "e_11")

        try await bench.push(
            #"{"id":"e_12","type":"desk.changed","at":"2026-11-10T07:41:00.000Z","desk":{"coming_up":[],"waiting":[]}}"#
        )
        #expect(session.desk == Desk())

        await bench.server.dropStream()
        let resume = try await bench.nextRequest()
        #expect(resume.path == "/v0/events" && resume.headers["Last-Event-ID"] == "e_12")
    }

    @Test("answering a card shows the box at work on it at once")
    func answerCard() async throws {
        let bench = try Bench()
        defer { bench.close() }
        let desk = #"{"coming_up":[],"waiting":[\#(Self.question("k_1"))]}"#
        try await bench.open(with: Self.snapshot("e_10", desk: desk))
        let session = bench.session

        let answering = Task { try await session.answer("k_1", CardAnswer(option: "Right")) }
        let request = try await bench.nextRequest()
        #expect(request.method == .post && request.path == "/v0/desk/cards/k_1/answer")
        #expect(
            try request.body.map { try JSONValue(data: $0) }
                == JSONValue(json: #"{"option":"Right"}"#))
        try await bench.server.answer(
            202, json: #"{"card":\#(Self.question("k_1", working: true))}"#)
        try await answering.value
        #expect(session.desk?.waiting.first?.state == .working)
    }

    @Test("Done, jobs, a briefing read and a calendar event are plain requests")
    func deskRequests() async throws {
        let bench = try Bench()
        defer { bench.close() }
        try await bench.open(with: Self.snapshot("e_10"))
        let session = bench.session

        let paging = Task { try await session.done(before: "d_9", limit: 20) }
        let done = try await bench.nextRequest()
        #expect(done.method == .get && done.path == "/v0/done?before=d_9&limit=20")
        try await bench.server.answer(200, json: DeskTests.done)
        #expect(try await paging.value.entries.map(\.id) == ["d1", "q1", "d2"])

        let latest = Task { try await session.done() }
        #expect(try await bench.nextRequest().path == "/v0/done?limit=50")
        try await bench.server.answer(200, json: #"{"entries":[],"has_more":false}"#)
        #expect(try await latest.value.entries.isEmpty)

        let undoing = Task { try await session.undo("d1") }
        let undo = try await bench.nextRequest()
        #expect(undo.method == .post && undo.path == "/v0/done/d1/undo" && undo.body == nil)
        try await bench.server.answer(
            200,
            json:
                #"{"entry":{"id":"d1","at":"2026-11-05T09:14:00.000Z","text":"Domino's: unsubscribed, binned (undone)","undo":false,"quiet":false}}"#
        )
        #expect(try await undoing.value.text.hasSuffix("(undone)"))

        let looking = Task { try await session.jobs() }
        let jobs = try await bench.nextRequest()
        #expect(jobs.method == .get && jobs.path == "/v0/jobs")
        try await bench.server.answer(
            200,
            json:
                #"{"jobs":[{"id":"j_1","why":"Ask how the QRT interview went","after_event":{"uid":"qrt@icloud.com","title":"QRT technical"}}]}"#
        )
        let job = try #require(try await looking.value.first)
        #expect(
            job.why == "Ask how the QRT interview went" && job.afterEvent?.title == "QRT technical")

        let reading = Task { try await session.readBriefing("b_1") }
        let read = try await bench.nextRequest()
        #expect(read.method == .post && read.path == "/v0/desk/briefing/b_1/read")
        try await bench.server.answer(204)
        try await reading.value

        let event = NewCalendarEvent(
            title: "Dentist", start: When(year: 2026, month: 11, day: 17),
            end: When(year: 2026, month: 11, day: 17))
        let adding = Task { try await session.addEvent(event) }
        let add = try await bench.nextRequest()
        #expect(add.method == .post && add.path == "/v0/calendar/events")
        #expect(try add.body.map { try JSONValue(data: $0) } == JSONValue(encoding: event))
        try await bench.server.answer(
            201,
            json:
                #"{"event":{"id":"dentist","uid":"dentist@icloud.com","title":"Dentist","start":"2026-11-17","end":"2026-11-17","all_day":true,"calendar":{"name":"Home","kumo":false}}}"#
        )
        #expect(try await adding.value.allDay)
    }

    @Test("a reply to a line of Done says which, so Kumo learns from it")
    func replyToDone() async throws {
        let bench = try Bench()
        defer { bench.close() }
        try await bench.open(with: Self.snapshot("e_10"))
        let id: MessageID = "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10"
        #expect(bench.session.send("Keep Domino's mail", id: id, done: "d1") == id)

        let send = try await bench.nextRequest()
        #expect(send.method == .post && send.path == "/v0/messages")
        #expect(
            try send.body.map { try JSONValue(data: $0) }
                == JSONValue(json: #"{"id":"\#(id)","text":"Keep Domino's mail","done":"d1"}"#))
    }

    @Test("getting started follows the snapshot and onboarding.changed, and finishing ends it")
    func onboarding() async throws {
        let bench = try Bench()
        defer { bench.close() }
        try await bench.open(
            with: Self.snapshot(
                "e_10",
                onboarding: #"{"state":"reading","progress":{"mails_read":120,"mails_total":900}}"#
            ))
        let session = bench.session
        #expect(session.onboarding?.state == .reading)
        let progress = Onboarding.Progress(mailsRead: 120, mailsTotal: 900)
        #expect(session.onboarding?.progress == progress)

        try await bench.push(
            #"{"id":"e_11","type":"onboarding.changed","at":"2026-11-10T08:05:00.000Z","onboarding":\#(Self.proposal)}"#
        )
        let proposal = try #require(session.onboarding?.proposal)
        #expect(session.onboarding?.state == .ready)
        #expect(proposal.beliefs.map(\.page) == ["memory:now"] && proposal.beliefs[0].answer == nil)
        #expect(proposal.added.map(\.title) == ["Hotel Orto"])
        #expect(proposal.motions == ["job-search"])
        #expect(session.conversation.cursor == "e_11")

        // Asking again says the same.
        let asking = Task { try await session.refreshOnboarding() }
        let ask = try await bench.nextRequest()
        #expect(ask.method == .get && ask.path == "/v0/onboarding")
        try await bench.server.answer(200, json: Self.proposal)
        try await asking.value
        #expect(session.onboarding?.proposal == proposal)

        let answering = Task {
            try await session.answerBelief("bf_1", answer: .correction("The Valencia half now."))
        }
        let belief = try await bench.nextRequest()
        #expect(belief.method == .post && belief.path == "/v0/onboarding/beliefs/bf_1")
        #expect(
            try belief.body.map { try JSONValue(data: $0) }
                == JSONValue(json: #"{"correction":"The Valencia half now."}"#))
        try await bench.server.answer(202)
        try await answering.value

        // Finishing says it's done here at once, before the stream does.
        let finishing = Task { try await session.finishOnboarding() }
        let finish = try await bench.nextRequest()
        #expect(finish.method == .post && finish.path == "/v0/onboarding/done")
        #expect(finish.body == nil)
        try await bench.server.answer(200, json: #"{"state":"done"}"#)
        try await finishing.value
        #expect(session.onboarding?.state == .done && session.onboarding?.proposal == nil)
    }

    @Test("a belief is confirmed with the word true, or corrected in your words")
    func beliefAnswers() throws {
        #expect(try JSONValue(encoding: BeliefAnswer.confirmed) == .object(["answer": "true"]))
        #expect(
            try JSONValue(encoding: BeliefAnswer.correction("Not a 5K."))
                == .object(["correction": "Not a 5K."]))
        let belief = try JSONValue(
            json: #"{"id":"bf_1","text":"You run 5Ks","page":"memory:now","answer":"corrected"}"#
        ).decode(Belief.self)
        #expect(belief.answer == .corrected)
    }

    @Test("the outbox sends what waited, in order, after a restart")
    func outbox() async throws {
        let first = try Bench()
        first.session.start()
        #expect(try await first.nextRequest().path == "/v0/events")
        // The stream never opens, so both wait.
        first.session.send("Prep me for QRT", id: "00000000-0000-4000-8000-000000000001")
        first.session.send("Book the tickets", id: "00000000-0000-4000-8000-000000000002")
        await first.settle()
        #expect(await first.server.takeRequest() == nil)
        first.session.close()

        let second = try Bench(outboxDirectory: first.outboxDirectory)
        defer { second.close() }
        second.session.start()
        let waiting = second.session.conversation.entries
        #expect(waiting.map(\.text) == ["Prep me for QRT", "Book the tickets"])
        #expect(waiting.allSatisfy { $0.delivery == .sending })

        #expect(try await second.nextRequest().path == "/v0/events")
        try await second.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await second.settle()
        try await second.push(Self.snapshot("e_10"))

        let firstSend = try await second.nextRequest()
        #expect(firstSend.path == "/v0/messages")
        #expect(
            try firstSend.body.map { try JSONValue(data: $0) }?["text"]?.string
                == "Prep me for QRT")
        try await second.server.answer(
            201,
            json:
                #"{"message":{"id":"00000000-0000-4000-8000-000000000001","role":"user","text":"Prep me for QRT","at":"2026-11-10T08:00:01.000Z","position":1}}"#
        )
        let secondSend = try await second.nextRequest()
        #expect(secondSend.path == "/v0/messages")
        #expect(
            try secondSend.body.map { try JSONValue(data: $0) }?["text"]?.string
                == "Book the tickets")
    }

    // MARK: - Fixtures

    private static let proposal = #"""
        {"state":"ready","proposal":{
          "beliefs":[{"id":"bf_1","text":"You're training for a sub-20 5K","page":"memory:now"}],
          "added":[{"id":"orto","uid":"orto@icloud.com","title":"Hotel Orto","start":"2026-11-12",
                    "end":"2026-11-15","all_day":true,"calendar":{"name":"Home","kumo":false}}],
          "motions":["job-search"]}}
        """#

    private static func snapshot(
        _ id: String, messages: [String] = [], desk: String = #"{"coming_up":[],"waiting":[]}"#,
        onboarding: String? = nil
    ) -> String {
        let onboarding = onboarding.map { #","onboarding":\#($0)"# } ?? ""
        return
            #"{"id":"\#(id)","type":"snapshot","at":"2026-11-10T08:00:00.000Z","reason":"no_cursor","messages":[\#(messages.joined(separator: ","))],"has_more":false,"steps":[],"asks":[],"calls":[],"topics":[],"turn":null,"next":[],"desk":\#(desk)\#(onboarding)}"#
    }

    private static func message(_ id: String, _ text: String, _ position: Int) -> String {
        #"{"id":"\#(id)","role":"user","text":"\#(text)","at":"2026-11-10T07:00:00.000Z","position":\#(position)}"#
    }

    private static func question(_ id: String, working: Bool = false) -> String {
        let state = working ? #","state":"working""# : ""
        return
            #"{"id":"\#(id)","kind":"question","at":"2026-11-10T06:00:00.000Z","title":"Binned a Revolut mail","options":[{"label":"Right"},{"label":"Keep it"}],"allows_text":true\#(state),"question":{"text":"I binned it. Right?"}}"#
    }
}

/// A session on its own, with a scripted server, a network and a clock the test controls.
@MainActor
private final class Bench {
    let clock = TestClock<Duration>()
    let server = ScriptedServer()
    let network = FakeNetwork()
    let outboxDirectory: URL
    let session: Session

    init(outboxDirectory: URL? = nil) throws {
        self.outboxDirectory =
            outboxDirectory
            ?? FileManager.default.temporaryDirectory
            .appending(path: "AriKitTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        session = Session(
            connection: try Rehearsal.connection(),
            outbox: OutboxStore(directory: self.outboxDirectory), transport: server,
            network: network, clock: clock)
    }

    /// Starts the session and opens its stream, which begins with `snapshot`.
    func open(with snapshot: String) async throws {
        session.start()
        let request = try await nextRequest()
        #expect(request.path == "/v0/events" && request.headers["Last-Event-ID"] == nil)
        try await server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await settle()
        #expect(session.link == .live)
        try await push(snapshot)
    }

    func push(_ json: String) async throws {
        try await server.push(json: json)
        await settle()
    }

    /// The next request the session makes, letting the clock run for up to ten seconds.
    func nextRequest() async throws -> HTTPRequest {
        for _ in 0..<100 {
            await settle()
            if let request = await server.takeRequest() { return request }
            await clock.advance(by: .milliseconds(100))
        }
        throw TranscriptError("Ari made no request within ten seconds")
    }

    /// Lets every task that can run, run: the session's lanes, and hops to the server's actor.
    func settle() async {
        for _ in 0..<4 {
            for _ in 0..<10 { await Task.yield() }
            _ = await server.isStreaming
        }
    }

    func close() {
        session.close()
        try? FileManager.default.removeItem(at: outboxDirectory)
    }
}
