import AriKit
import Foundation
import Testing

/// In motion: the things Ari keeps going for you, how they follow the stream, and how a trip reads.
@Suite("In motion")
@MainActor
struct MotionTests {
    private let florence: MotionID = "florence-with-janki"
    private let english = Locale(identifier: "en_GB")

    @Test("Scenario 62: a trip starts pinned, and the app lists it and opens it")
    func tripStarts() async throws {
        let transcript = try Fixtures.transcript("62-a-trip-in-motion")
        let server = TranscriptServer(transcript, only: Self.motionRoutes)
        let list = try await server.client.motions()
        #expect(list.motions.map(\.id) == [florence])
        #expect(list.motions.first?.pinned == true)
        let detail = try await server.client.motion(florence)
        let trip = try #require(Self.trip(detail))
        #expect(trip.destination == "Florence")
        #expect(trip.cover?.credit == "Wikimedia Commons, CC BY-SA 4.0")
        #expect(trip.days.map(\.id) == ["fri", "sat", "sun"])
        let line = TripReading.line(trip, state: detail.state, locale: english)
        #expect(line.name == "Florence" && line.when == "6–9 Nov" && line.left == 4)
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("Scenario 63: your tick goes to the box, and what it books shows booked at once")
    func keepingCurrent() async throws {
        let transcript = try Fixtures.transcript("63-keeping-it-current")
        let server = TranscriptServer(transcript, only: Self.motionRoutes)
        let state = try await server.client.tick(
            florence, list: TripReading.todoList, item: "book-pisa", done: true)
        #expect(state[TripReading.todoList]?["book-pisa"]?.done == true)
        let detail = try await server.client.motion(florence)
        let trip = try #require(Self.trip(detail))
        // The Uffizi as Ari wrote it, the Pisa train by your tick.
        #expect(
            TripReading.left(trip, state: detail.state).map(\.id) == ["book-duomo", "book-pitti"])
        let train = try #require(trip.days.flatMap(\.stops).first { $0.id == "pisa-train" })
        #expect(train.booking?.status == .toBook)
        #expect(
            TripReading.booking(train.booking, of: train.id, in: trip, state: detail.state)?.status
                == .booked)
        #expect(
            detail.changes.map(\.note) == ["Booked the Uffizi, 8:15 Saturday", "Started the trip"])
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("the store follows the stream: Ari's changes, your ticks, and the pinned line")
    func followsTheStream() async throws {
        let transcript = try Fixtures.transcript("63-keeping-it-current")
        let stub = MotionStub(detail: try Self.lastDetail(in: transcript))
        let motions = Motions(client: stub.client, defaults: Self.scratchDefaults())
        for logged in transcript.events { motions.apply(logged.event) }

        #expect(motions.going.map(\.id) == [florence])
        let pinned = try #require(motions.pinned)
        #expect(pinned.motion.version == 2 && pinned.more == 0)
        #expect(motions.change(florence, version: 2)?.note == "Booked the Uffizi, 8:15 Saturday")
        try await until { motions.details[florence] != nil }
        #expect(motions.details[florence]?.state[TripReading.todoList]?["book-pisa"]?.done == true)

        // Your tick shows at once, and stays once the box has it.
        #expect(
            await motions.tick(florence, list: TripReading.todoList, item: "book-duomo", done: true)
        )
        let trip = try #require(motions.details[florence].flatMap(Self.trip))
        let state = try #require(motions.details[florence]?.state)
        #expect(TripReading.left(trip, state: state).map(\.id) == ["book-pitti"])
    }

    @Test("a tick the box refuses goes back")
    func refusedTick() async throws {
        let transcript = try Fixtures.transcript("63-keeping-it-current")
        let stub = MotionStub(detail: try Self.lastDetail(in: transcript), refusesTicks: true)
        let motions = Motions(client: stub.client, defaults: Self.scratchDefaults())
        try await motions.detail(florence)
        #expect(
            !(await motions.tick(
                florence, list: TripReading.todoList, item: "book-duomo", done: true)))
        #expect(motions.details[florence]?.state[TripReading.todoList]?["book-duomo"] == nil)
    }

    @Test("a swiped-away pinned line comes back when Ari next changes the thing")
    func dismissing() throws {
        let defaults = Self.scratchDefaults()
        let motions = Motions(client: MotionStub(detail: nil).client, defaults: defaults)
        motions.apply(try Self.event("motion.started", version: 1))
        let motion = try #require(motions.pinned?.motion)
        motions.dismiss(motion)
        #expect(motions.pinned == nil)
        #expect(
            Motions(client: MotionStub(detail: nil).client, defaults: defaults).dismissed[florence]
                == 1)
        motions.apply(try Self.event("motion.changed", version: 2))
        #expect(motions.pinned?.motion.version == 2)
    }

    @Test("finished things move to done, and forgotten ones go")
    func finishingAndForgetting() throws {
        let motions = Motions(
            client: MotionStub(detail: nil).client, defaults: Self.scratchDefaults())
        motions.apply(try Self.event("motion.started", version: 1))
        motions.apply(try Self.event("motion.finished", version: 2, status: "done"))
        #expect(motions.going.isEmpty && motions.done.map(\.id) == [florence])
        #expect(motions.pinned == nil)
        motions.apply(
            try JSONValue(
                json:
                    #"{"id":"e_9","type":"motion.removed","at":"2026-10-29T12:00:00Z","motion":"florence-with-janki"}"#
            ).decode(Event.self))
        #expect(motions.all.isEmpty)
    }

    @Test("a trip reads as its dates, days and the way between stops")
    func reading() throws {
        let november = Trip.Dates(start: "2026-11-06", end: "2026-11-09")
        #expect(TripReading.dates(november, locale: english) == "6–9 Nov")
        #expect(
            TripReading.dates(.init(start: "2026-10-30", end: "2026-11-02"), locale: english)
                == "30 Oct – 2 Nov")
        #expect(
            TripReading.dates(.init(start: "2026-11-06", end: "2026-11-06"), locale: english)
                == "6 Nov")
        let trip = Trip(
            destination: "Florence", dates: november, timezone: "Europe/Rome", who: ["Janki"])
        #expect(
            TripReading.subtitle(trip, locale: english) == "Fri 6 – Mon 9 November · You and Janki")
        #expect(
            TripReading.heading(of: .init(id: "fri", date: "2026-11-06"), locale: english)
                == "Friday 6 November")
        #expect(TripReading.move(.init(mode: .walk, minutes: 6)) == "6 min walk")
        #expect(TripReading.move(.init(mode: .tram, minutes: 25)) == "25 min by tram")
        #expect(
            TripReading.move(
                .init(mode: .train, minutes: 60, detail: "Firenze SMN → Pisa Centrale"))
                == "1 h by train · Firenze SMN → Pisa Centrale")
        #expect(TripReading.duration(80) == "1 h 20 min")
        #expect(TripReading.when("2026-11-08T09:12", locale: english) == "Sun 8 Nov, 09:12")
        #expect(TripReading.leftText(3) == "3 to do" && TripReading.leftText(0) == "All done")
    }

    @Test("the map numbers every stop with a place, in order through the trip")
    func mapStops() async throws {
        let transcript = try Fixtures.transcript("63-keeping-it-current")
        let trip = try #require(
            Self.trip(try Self.lastDetail(in: transcript).decode(MotionDetail.self)))
        let stops = TripReading.mapStops(trip)
        #expect(stops.map(\.number) == Array(1...stops.count))
        #expect(stops.first?.stop.id == "duomo")
        #expect(!stops.contains { $0.stop.id == "land" }, "landing has no place to pin")
    }

    @Test("a trip opens on today while it's on, and on its first day otherwise")
    func openingDay() throws {
        let trip = Trip(
            destination: "Florence", dates: .init(start: "2026-11-06", end: "2026-11-08"),
            timezone: "Europe/Rome",
            days: [
                .init(id: "fri", date: "2026-11-06"), .init(id: "sat", date: "2026-11-07"),
                .init(id: "sun", date: "2026-11-08"),
            ])
        // 23:30 in London on Friday is already Saturday in Florence.
        let late = try #require(Timestamp("2026-11-06T23:30:00Z")).date
        #expect(TripReading.openingDay(of: trip, now: late)?.id == "sat")
        let before = try #require(Timestamp("2026-10-29T12:00:00Z")).date
        #expect(TripReading.openingDay(of: trip, now: before)?.id == "fri")
    }

    @Test("a reply's compact line names the thing and the version it's about")
    func compactLine() {
        let shape = ReplyShape(
            language: "ari:motion", json: #"{"motion":"florence-with-janki","change":2}"#)
        guard case .motion(let line) = shape else {
            Issue.record("not a motion line")
            return
        }
        #expect(line.motion == florence && line.change == 2)
    }

    // MARK: - Helpers

    private nonisolated static func motionRoutes(_ route: Route) -> Bool {
        switch route {
        case .motions, .motion, .motionState: true
        default: false
        }
    }

    private static func trip(_ detail: MotionDetail) -> Trip? {
        if case .trip(let trip) = detail.content { trip } else { nil }
    }

    /// The thing as the transcript's last read of it gives it.
    private static func lastDetail(in transcript: Transcript) throws -> JSONValue {
        let bodies = transcript.steps.compactMap { step -> JSONValue? in
            guard case .server(let response) = step, response.body?["content"] != nil else {
                return nil
            }
            return response.body
        }
        return try #require(bodies.last)
    }

    private static func event(_ type: String, version: Int, status: String = "active") throws
        -> Event
    {
        try JSONValue(
            json: """
                {"id":"e_\(version)","type":"\(type)","at":"2026-10-29T1\(version):00:00Z",
                 "motion":{"id":"florence-with-janki","kind":"trip","title":"Florence with Janki",
                  "summary":"6–9 Nov","status":"\(status)","pinned":true,"version":\(version),
                  "started_at":"2026-10-29T10:00:00Z","changed_at":"2026-10-29T1\(version):00:00Z",
                  "position":1},
                 "change":{"version":\(version),"at":"2026-10-29T1\(version):00:00Z","note":"A change",
                  "position":1}}
                """
        ).decode(Event.self)
    }

    private static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "motion-tests-\(UUID().uuidString)")!
    }

    /// Waits for work the store started by itself, such as fetching a thing that changed.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "timed out")
    }
}

/// A server with one thing in motion: it lists it, gives its detail, and takes ticks.
private actor MotionStub: Transport {
    private var detail: JSONValue?
    private let refusesTicks: Bool

    init(detail: JSONValue?, refusesTicks: Bool = false) {
        self.detail = detail
        self.refusesTicks = refusesTicks
    }

    nonisolated var client: ItoClient {
        ItoClient(
            address: try! ServerAddress("http://127.0.0.1:8787"), token: Token("t"), transport: self
        )
    }

    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        guard let detail else { return HTTPResponse(status: 404, headers: [:], body: Data()) }
        switch (request.method, request.path) {
        case (.get, "/v0/motion"):
            return try answer(JSONValue.object(["motions": .array([detail["motion"]!])]))
        case (.get, let path) where path.hasPrefix("/v0/motion/"):
            return try answer(detail)
        case (.patch, _):
            if refusesTicks { return HTTPResponse(status: 500, headers: [:], body: Data()) }
            let patch = try JSONValue(data: request.body ?? Data())
            var state = detail["state"]?.object ?? [:]
            for (list, items) in patch.object ?? [:] {
                var merged = state[list]?.object ?? [:]
                for (item, tick) in items.object ?? [:] { merged[item] = tick }
                state[list] = .object(merged)
            }
            var updated = detail.object ?? [:]
            updated["state"] = .object(state)
            self.detail = .object(updated)
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
