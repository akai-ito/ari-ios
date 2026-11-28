import AriKit
import Foundation
import Testing

@Suite("The trail's rhythm: live GPS only while moving")
struct TrailRhythmTests {
    /// Feeds `rhythm` each signal in turn, and gives back the change each made.
    private func play(_ rhythm: inout TrailRhythm, _ signals: [TrailRhythm.Signal])
        -> [TrailRhythm.Change?]
    {
        signals.map { rhythm.hear($0) }
    }

    private func allowed() -> TrailRhythm {
        var rhythm = TrailRhythm()
        rhythm.hear(.power(lowPower: false, level: 0.8))
        rhythm.hear(.allowed(true))
        return rhythm
    }

    @Test("off until allowed: no movement starts the GPS")
    func offUntilAllowed() {
        var rhythm = TrailRhythm()
        #expect(rhythm.mode == .off)
        let changes = play(&rhythm, [.departed, .significantChange(nearStop: false)])
        #expect(changes == [nil, nil])
        #expect(!rhythm.live)
    }

    @Test("a departure starts live points; arriving stops them")
    func departureThenArrival() {
        var rhythm = allowed()
        #expect(rhythm.mode == .full)
        let changes = play(
            &rhythm, [.departed, .significantChange(nearStop: false), .arrived, .arrived])
        // Already running, the change does nothing more; already stopped, nor does arriving.
        #expect(changes == [.startLive, nil, .stopLive, nil])
        #expect(!rhythm.live)
    }

    @Test("a significant change starts live points; stationary stops them")
    func changeThenStationary() {
        var rhythm = allowed()
        let changes = play(&rhythm, [.significantChange(nearStop: false), .stationary])
        #expect(changes == [.startLive, .stopLive])
    }

    @Test("a significant change within the stop you're at is noise")
    func noiseAtAStop() {
        var rhythm = allowed()
        let changes = play(&rhythm, [.significantChange(nearStop: true)])
        #expect(changes == [nil])
        #expect(!rhythm.live)
    }

    @Test("Low Power Mode keeps only the stops, and stops a run under way")
    func lowPower() {
        var rhythm = allowed()
        let changes = play(
            &rhythm, [.departed, .power(lowPower: true, level: 0.8), .departed])
        #expect(changes == [.startLive, .stopLive, nil])
        #expect(rhythm.mode == .stopsOnly)
        // Back to normal: the next sign of moving starts it, not the change of mode.
        let after = play(&rhythm, [.power(lowPower: false, level: 0.8), .departed])
        #expect(after == [nil, .startLive])
        #expect(rhythm.mode == .full)
    }

    @Test("under 20% battery keeps only the stops; an unknown level doesn't")
    func lowBattery() {
        var rhythm = allowed()
        rhythm.hear(.power(lowPower: false, level: 0.15))
        #expect(rhythm.mode == .stopsOnly)
        rhythm.hear(.power(lowPower: false, level: 0.2))
        #expect(rhythm.mode == .full)
        rhythm.hear(.power(lowPower: false, level: nil))
        #expect(rhythm.mode == .full)
    }

    @Test("turning places off or pausing stops a run")
    func turnedOff() {
        var rhythm = allowed()
        let changes = play(&rhythm, [.significantChange(nearStop: false), .allowed(false)])
        #expect(changes == [.startLive, .stopLive])
        #expect(rhythm.mode == .off)
    }
}

@Suite("Thinning live points")
struct TrailThinnerTests {
    private func point(_ seconds: TimeInterval, north metres: Double, accuracy: Double = 5)
        -> TrailPoint
    {
        TrailPoint(
            at: Date(timeIntervalSince1970: 1_000_000 + seconds),
            latitude: 55.95 + metres / 111_195, longitude: -3.19, accuracy: accuracy,
            source: .live)
    }

    private func kept(_ points: [TrailPoint], by thinner: inout TrailThinner) -> [Bool] {
        points.map { thinner.keep($0) }
    }

    @Test("keeps about one point every 10 seconds and 20 metres")
    func spacing() {
        var thinner = TrailThinner()
        let kept = kept(
            [
                point(0, north: 0),
                point(5, north: 30),  // too soon
                point(12, north: 10),  // too near
                point(12, north: 30),
                point(30, north: 40),  // only 10 m on from the last kept
                point(30, north: 55),
            ], by: &thinner)
        #expect(kept == [true, false, false, true, false, true])
    }

    @Test("drops fixes worse than 100 m, and invalid ones")
    func accuracy() {
        var thinner = TrailThinner()
        let kept = kept(
            [
                point(0, north: 0, accuracy: 150), point(0, north: 0, accuracy: -1),
                point(0, north: 0, accuracy: 40),
            ], by: &thinner)
        #expect(kept == [false, false, true])
    }

    @Test("a new run starts afresh")
    func reset() {
        var thinner = TrailThinner()
        let first = thinner.keep(point(0, north: 0))
        thinner.reset()
        let second = thinner.keep(point(1, north: 1))
        #expect(first && second)
    }
}

/// A queue in its own temporary folder.
private func makeQueue(batchSize: Int = 200) -> TrailQueue {
    TrailQueue(
        directory: FileManager.default.temporaryDirectory.appending(
            path: "trail-\(UUID().uuidString)"),
        batchSize: batchSize)
}

private func livePoint(_ at: Date, _ n: Double = 0) -> TrailPoint {
    TrailPoint(at: at, latitude: 55.95 + n / 1000, longitude: -3.19, accuracy: 8, source: .live)
}

private let day = Date(timeIntervalSince1970: 1_795_000_000)

@Suite("The trail's queue on the phone")
struct TrailQueueTests {
    @Test("points wait in an open batch, which seals when full or asked")
    func sealing() throws {
        let queue = makeQueue(batchSize: 3)
        try queue.add(livePoint(day))
        try queue.add(livePoint(day.addingTimeInterval(10), 1))
        #expect(queue.sealed().isEmpty)
        #expect(queue.waiting() == 2)
        try queue.add(livePoint(day.addingTimeInterval(20), 2))
        #expect(queue.sealed().count == 1)
        try queue.add(livePoint(day.addingTimeInterval(30), 3))
        try queue.seal()
        let sealed = queue.sealed()
        #expect(sealed.map(\.batch.count) == [3, 1])
        #expect(Set(sealed.map(\.batch.id)).count == 2)
        // A sealed batch's file is the body to upload.
        let body = try JSONSerialization.jsonObject(with: Data(contentsOf: sealed[0].file))
        let json = try #require(body as? [String: Any])
        #expect(json["batch"] as? String == sealed[0].batch.id.rawValue)
        #expect((json["samples"] as? [Any])?.count == 3)
        #expect(json["time_zone"] as? String == TimeZone.current.identifier)
    }

    @Test("a visit's departure replaces its arrival while the batch is open, keeping its name")
    func visitDelivery() throws {
        let queue = makeQueue()
        let arrived = TrailVisit(
            arrived: day, departed: nil, latitude: 55.9483, longitude: -3.1996, accuracy: 18,
            placemark: Placemark(name: "Northwind"))
        try queue.add(arrived)
        var left = arrived
        left.departed = day.addingTimeInterval(3600)
        left.placemark = nil
        try queue.add(left)
        try queue.seal()
        let visits = try #require(queue.sealed().first).batch.visits
        #expect(visits.count == 1)
        #expect(visits[0].departed == left.departed)
        #expect(visits[0].placemark?.name == "Northwind")
    }

    @Test("survives a restart: a new queue on the same folder reads what was left")
    func restart() throws {
        let queue = makeQueue()
        try queue.add(livePoint(day))
        let again = TrailQueue(directory: queue.directory)
        #expect(again.waiting() == 1)
        try again.seal()
        #expect(again.sealed().first?.batch.points.first?.at == day)
    }

    @Test("deleting a day drops what's waiting from it, sealed or not")
    func deletingADay() throws {
        let queue = makeQueue(batchSize: 2)
        try queue.add(livePoint(day))
        try queue.add(livePoint(day.addingTimeInterval(86_400)))
        try queue.add(livePoint(day.addingTimeInterval(10)))
        try queue.remove(from: day.addingTimeInterval(-1), to: day.addingTimeInterval(3600))
        #expect(queue.waiting() == 1)
        try queue.seal()
        let left = queue.sealed().flatMap(\.batch.points).map(\.at)
        #expect(left == [day.addingTimeInterval(86_400)])
        queue.removeAll()
        #expect(queue.waiting() == 0)
    }
}

/// The box's answer to every trail batch, set by the test, with what it was sent.
private actor TrailServer: Transport {
    var status = 200
    var offline = false
    private(set) var batches: [String] = []

    nonisolated var client: ItoClient {
        ItoClient(
            address: try! ServerAddress("http://127.0.0.1:8787"), token: Token("t"), transport: self
        )
    }

    func set(status: Int) { self.status = status }
    func set(offline: Bool) { self.offline = offline }

    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        guard !offline else { throw URLError(.cannotConnectToHost) }
        #expect(request.method == .post && request.path == "/v0/location/batches")
        #expect(request.headers["Authorization"] == "Bearer t")
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data())
        batches.append((body as? [String: Any])?["batch"] as? String ?? "")
        return HTTPResponse(
            status: status, headers: ["ito-protocol": ProtocolVersion.supported.description],
            body: Data(#"{"batch":"x","kept":1,"repeated":false}"#.utf8))
    }

    func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
        throw URLError(.unsupportedURL)
    }
}

@Suite("Uploading the trail")
@MainActor
struct TrailUploadsTests {
    private let carrier = DirectTrailCarrier()

    /// Until every batch handed over has its answer.
    private func settle(_ uploads: TrailUploads) async {
        for _ in 0..<10_000 {
            await Task.yield()
            if await carrier.inFlight().isEmpty { return }
        }
        Issue.record("batches still in flight")
    }

    @Test("offline, the trail waits; back online, every batch goes, oldest first")
    func offlineThenOnline() async throws {
        let server = TrailServer()
        let queue = makeQueue(batchSize: 2)
        let uploads = TrailUploads(
            queue: queue, carrier: carrier, defaults: UserDefaults(suiteName: #function)!)
        uploads.client = server.client
        for n in 0..<5 {
            try queue.add(livePoint(day.addingTimeInterval(Double(n) * 10), Double(n)))
        }
        let ids = queue.sealed().map(\.batch.id.rawValue)
        await server.set(offline: true)
        await uploads.send()
        await settle(uploads)
        #expect(uploads.waiting == 5)
        #expect(uploads.problem == nil, "offline isn't a problem to show")
        await server.set(offline: false)
        await uploads.send()
        await settle(uploads)
        #expect(uploads.waiting == 0)
        let sent = await server.batches
        #expect(Array(sent.prefix(2)) == ids)
        #expect(sent.count == 3)
        #expect(uploads.lastSent != nil)
    }

    @Test("a batch the box already has counts as sent")
    func repeated() async throws {
        let server = TrailServer()
        await server.set(status: 409)
        let queue = makeQueue()
        let uploads = TrailUploads(
            queue: queue, carrier: carrier, defaults: UserDefaults(suiteName: #function)!)
        uploads.client = server.client
        try queue.add(livePoint(day))
        await uploads.send()
        await settle(uploads)
        #expect(uploads.waiting == 0)
    }

    @Test("a refused batch stays on the phone, and says why")
    func refused() async throws {
        let server = TrailServer()
        await server.set(status: 404)
        let queue = makeQueue()
        let uploads = TrailUploads(
            queue: queue, carrier: carrier, defaults: UserDefaults(suiteName: #function)!)
        uploads.client = server.client
        try queue.add(livePoint(day))
        await uploads.send()
        await settle(uploads)
        #expect(uploads.waiting == 1)
        guard case .refused(status: 404, _, _) = uploads.problem else {
            Issue.record("expected the 404 to show, got \(String(describing: uploads.problem))")
            return
        }
        // The box is updated: the same batch goes again, and the problem clears.
        await server.set(status: 200)
        await uploads.send()
        await settle(uploads)
        #expect(uploads.waiting == 0)
        #expect(uploads.problem == nil)
        let sent = await server.batches
        #expect(sent.count == 2 && sent[0] == sent[1])
    }

    @Test("with no box, nothing is sent and the trail waits")
    func noBox() async throws {
        let queue = makeQueue()
        let uploads = TrailUploads(
            queue: queue, carrier: carrier, defaults: UserDefaults(suiteName: #function)!)
        try queue.add(livePoint(day))
        await uploads.send()
        #expect(uploads.waiting == 1)
        #expect(queue.sealed().count == 1)
    }

    @Test("a background answer reads the same way")
    func backgroundAnswer() {
        let headers = ["ito-protocol": ProtocolVersion.supported.description]
        func kept(_ status: Int) -> Bool {
            if case .success = ItoClient.trailAnswer(status: status, headers: headers, body: Data())
            {
                return true
            }
            return false
        }
        #expect(kept(200))
        #expect(kept(409))
        #expect(!kept(400))
        #expect(!kept(503))
    }
}

@Suite("The live GPS diary")
struct LiveLogTests {
    @Test("adds up a day's runs, cutting at midnight and at now")
    func day() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: TrailQueueTestsDay.date)
        let log = LiveLog(
            file: FileManager.default.temporaryDirectory.appending(path: "live-\(UUID()).json"))
        func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }
        log.add(.init(at: at(-0.5), kind: .liveOn, detail: "departed"))
        log.add(.init(at: at(0.5), kind: .liveOff, detail: "arrived · 120 points"))
        log.add(.init(at: at(8), kind: .liveOn, detail: "significant change", battery: 0.6))
        log.add(.init(at: at(8.25), kind: .liveOff, detail: "stationary · 40 points"))
        log.add(.init(at: at(9), kind: .mode, detail: "stopsOnly", lowPower: true))
        log.add(.init(at: at(18), kind: .liveOn, detail: "departed"))
        let summary = log.day(start, calendar: calendar, now: at(18.5))
        #expect(summary.runs == 3)
        #expect(abs(summary.live - (0.5 + 0.25 + 0.5) * 3600) < 1)
        #expect(log.entries().count == 6)
    }
}

private enum TrailQueueTestsDay {
    static let date = Date(timeIntervalSince1970: 1_795_000_000)
}

@Suite("Matching a person to the phone's contacts")
struct ContactMatchTests {
    private let omar = ContactMatch.Facts(
        id: "box-omar", names: ["Omar Haddad", "Omar"], phones: ["+44 7700 900142"],
        emails: ["omar.haddad@example.com"])

    @Test("a shared number is sure, however it's written")
    func number() {
        let candidates = [
            ContactMatch.Facts(id: "1", names: ["Omar Farouk"], phones: ["07700 900999"]),
            ContactMatch.Facts(id: "2", names: ["O. Haddad"], phones: ["07700 900142"]),
        ]
        #expect(ContactMatch.best(for: omar, among: candidates) == "2")
    }

    @Test("an address is sure, whatever its case")
    func email() {
        let candidates = [
            ContactMatch.Facts(id: "1", names: ["Omar"], emails: ["Omar.Haddad@Example.com"])
        ]
        #expect(ContactMatch.best(for: omar, among: candidates) == "1")
    }

    @Test("a name alone counts only when one contact has it")
    func nameAlone() {
        let person = ContactMatch.Facts(id: "box-clara", names: ["Clara Voss"])
        #expect(
            ContactMatch.best(
                for: person, among: [ContactMatch.Facts(id: "1", names: ["clara  voss"])]) == "1")
        #expect(
            ContactMatch.best(
                for: person,
                among: [
                    ContactMatch.Facts(id: "1", names: ["Clara Voss"]),
                    ContactMatch.Facts(id: "2", names: ["Clára Voss"]),
                ]) == nil)
    }

    @Test("two equally sure contacts are no match, unless the name settles it")
    func ties() {
        let shared = [
            ContactMatch.Facts(id: "1", names: ["Leo"], phones: ["+44 7700 900142"]),
            ContactMatch.Facts(id: "2", names: ["Omar Haddad"], phones: ["+44 7700 900142"]),
        ]
        #expect(ContactMatch.best(for: omar, among: shared) == "2")
        let unnamed = [
            ContactMatch.Facts(id: "1", names: ["Leo"], phones: ["+44 7700 900142"]),
            ContactMatch.Facts(id: "2", names: ["Tilly"], phones: ["+44 7700 900142"]),
        ]
        #expect(ContactMatch.best(for: omar, among: unnamed) == nil)
    }

    @Test("nobody: no match")
    func nobody() {
        #expect(ContactMatch.best(for: omar, among: []) == nil)
        #expect(
            ContactMatch.best(for: omar, among: [ContactMatch.Facts(id: "1", names: ["Mira"])])
                == nil)
    }
}

@Suite("One-tap ways to reach someone")
struct ReachLinksTests {
    @Test("the row in its order, each with its link")
    func row() {
        let row = ReachLinks.actions(
            phones: ["+44 7700 900142"], emails: ["omar.haddad@example.com"],
            address: "21 Kestrel Lane, Edinburgh")
        #expect(row.map(\.action) == [.call, .message, .faceTime, .email, .directions])
        #expect(row[0].url?.absoluteString == "tel:+447700900142")
        #expect(row[1].url?.absoluteString == "sms:+447700900142")
        #expect(row[2].url?.absoluteString == "facetime:+447700900142")
        #expect(row[3].url?.absoluteString == "mailto:omar.haddad@example.com")
        #expect(row[4].url?.absoluteString == "maps://?daddr=21%20Kestrel%20Lane,%20Edinburgh")
    }

    @Test("with only an address, Messages and FaceTime use it; the rest are dimmed")
    func emailOnly() {
        let row = ReachLinks.actions(phones: [], emails: ["mira@example.com"], address: nil)
        #expect(row[0].url == nil)
        #expect(row[1].url?.absoluteString == "sms:mira@example.com")
        #expect(row[2].url?.absoluteString == "facetime:mira@example.com")
        #expect(row[4].url == nil)
    }
}

@Suite("What goes up to the box, as the spec has it")
struct LocationWireTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("a batch, its samples and its visits carry only the spec's fields")
    func batch() throws {
        let batch = TrailBatch(
            id: "b-1", timeZone: "Europe/London",
            points: [
                TrailPoint(
                    at: day, latitude: 55.9467, longitude: -3.2049, accuracy: 8, altitude: 71,
                    speed: -1, course: 92, source: .live)
            ],
            visits: [
                TrailVisit(
                    arrived: day, departed: nil, latitude: 55.9483, longitude: -3.1996,
                    accuracy: 18, placemark: Placemark(name: "Northwind", countryCode: "gb"))
            ])
        let body = try json(batch)
        #expect(Set(body.keys) == ["batch", "time_zone", "samples", "visits"])
        let sample = try #require((body["samples"] as? [[String: Any]])?.first)
        // iOS's negative speed means unknown: left out.
        #expect(
            Set(sample.keys) == [
                "at", "latitude", "longitude", "accuracy", "altitude", "course", "source",
            ])
        #expect(sample["source"] as? String == "live")
        #expect((sample["at"] as? String)?.hasSuffix("Z") == true)
        let visit = try #require((body["visits"] as? [[String: Any]])?.first)
        #expect(
            Set(visit.keys) == ["arrived_at", "latitude", "longitude", "accuracy", "placemark"])
        let placemark = try #require(visit["placemark"] as? [String: Any])
        #expect(placemark["country_code"] as? String == "GB")
        #expect(
            try JSONDecoder().decode(TrailBatch.self, from: JSONEncoder().encode(batch)) == batch)
    }

    @Test("forgetting a day, a range or everything")
    func forget() throws {
        #expect(
            try json(ForgetLocation.day("2026-11-20")) as? [String: String] == ["day": "2026-11-20"]
        )
        #expect(
            try json(ForgetLocation.range(from: "2026-11-20", to: "2026-11-22"))
                as? [String: String]
                == ["from": "2026-11-20", "to": "2026-11-22"])
        #expect(try json(ForgetLocation.everything) as? [String: Bool] == ["everything": true])
    }

    @Test("photo seeds, and a placemark trimmed to what the box takes")
    func photos() throws {
        let seeds = PhotoSeeds(
            batch: "photos-1-of-2", timeZone: "Europe/Lisbon",
            photos: [
                PhotoSeed(
                    takenAt: day, latitude: 38.7139, longitude: -9.1394,
                    placemark: Placemark(
                        name: String(repeating: "a", count: 200), locality: " Lisbon ",
                        countryCode: "PRT"))
            ])
        let body = try json(seeds)
        #expect(Set(body.keys) == ["batch", "time_zone", "photos"])
        let photo = try #require((body["photos"] as? [[String: Any]])?.first)
        #expect(Set(photo.keys) == ["taken_at", "latitude", "longitude", "placemark"])
        let placemark = try #require(photo["placemark"] as? [String: Any])
        #expect((placemark["name"] as? String)?.count == 120)
        #expect(placemark["locality"] as? String == "Lisbon")
        #expect(placemark["country_code"] == nil)
    }
}
