import AriKit
import Clocks
import Foundation
import Testing

/// Reading without a connection, through the scripted server: what you loaded is kept on the
/// device, shows at once after a relaunch in airplane mode, and when the server returns, its fresh
/// state replaces the copy without blanking it or doubling anything.
@MainActor
@Suite("Reading offline")
struct OfflineReadingTests {
    @Test(
        "the chat, a thread and the Desk survive a relaunch offline, then refresh without doubles")
    func relaunchOffline() async throws {
        let phone = try Phone()
        defer { phone.remove() }

        // Online: the snapshot, a post that came after it, and a thread you opened.
        try await phone.open(with: Self.snapshot("e_10", messages: [Self.ask, Self.reply]))
        try await phone.push(Self.posted("e_11", "a_2", "Kiln moved you to 7:30.", position: 5))
        let opening = Task { await phone.session.openThread("th_1") }
        #expect(try await phone.nextRequest().path == "/v0/threads/th_1")
        try await phone.server.answer(200, json: Self.threadPage)
        await opening.value
        let loaded = phone.session.conversation.entries.map(\.text)
        #expect(loaded.count == 3)

        // A few quiet seconds later the copy is on the device, before Ari ever leaves the screen.
        await phone.clock.advance(by: Session.copyDelay)
        try await phone.waitForCopy()

        // Airplane mode: nothing on screen goes.
        await phone.goOffline()
        await phone.settle()
        #expect(phone.session.link == .offline)
        #expect(phone.session.isOffline)
        #expect(phone.session.conversation.entries.map(\.text) == loaded)
        let updated = try #require(phone.session.updatedAt)

        // Force-quit and open again, still offline: everything is there before the stream is.
        let again = phone.relaunch()
        #expect(again.conversation.entries.map(\.text) == loaded)
        #expect(again.conversation.isCopy)
        #expect(again.conversation.steps.map(\.id) == ["s_1"])
        #expect(again.conversation.threads["th_1"]?.title == "Kiln menu")
        #expect(again.conversation(in: "th_1").entries.map(\.text) == ["What's on the menu?"])
        #expect(again.desk?.line?.text == "Kiln is booked for Saturday.")
        #expect(again.desk?.waiting.map(\.id) == ["k_1"])
        #expect(again.updatedAt.map { abs($0.timeIntervalSince(updated)) < 1 } == true)
        again.start()
        await phone.settle()
        #expect(again.link == .offline)
        #expect(again.conversation.entries.map(\.text) == loaded)
        #expect(await phone.server.takeRequest() == nil)

        // Sending still queues.
        let waiting = try #require(again.send("Book the 7:30?", id: Self.sent))
        #expect(again.conversation[waiting]?.delivery == .sending)

        // Back online: a snapshot with what's new replaces the copy, in place.
        await phone.goOnline()
        let resume = try await phone.nextRequest()
        #expect(resume.path == "/v0/events" && resume.headers["Last-Event-ID"] == nil)
        try await phone.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await phone.settle()
        let newer = Self.posted("e_12", "a_3", "Mira says yes.", position: 6, wrapped: false)
        try await phone.push(
            Self.snapshot("e_12", messages: [Self.ask, Self.reply, Self.post, newer]))
        #expect(!again.conversation.isCopy)
        let texts = again.conversation.entries.map(\.text)
        #expect(texts == loaded + ["Mira says yes.", "Book the 7:30?"])

        // Your waiting message goes once, and takes its place once.
        var requests: [HTTPRequest] = []
        for _ in 0..<2 { requests.append(try await phone.nextRequest()) }
        #expect(requests.map(\.path).sorted() == ["/v0/messages", "/v0/threads/th_1"])
        for request in requests {
            if request.path == "/v0/messages" {
                try await phone.server.answer(201, json: Self.accepted)
            } else {
                try await phone.server.answer(200, json: Self.threadPage)
            }
            await phone.settle()
        }
        try await phone.push(
            #"{"id":"e_13","type":"message.accepted","at":"2026-11-10T09:00:00.000Z","message":\#(Self.mine)}"#
        )
        let ids = again.conversation.entries.map(\.id)
        #expect(ids == ["u_1", "a_1", "a_2", "a_3", Self.sent])
        #expect(again.conversation[Self.sent]?.delivery == .delivered)
        #expect(again.conversation(in: "th_1").entries.map(\.id) == ["u_t1"])
        again.close()
    }

    @Test("reconnecting to a copy that reaches further back keeps that history above the snapshot")
    func historyStays() async throws {
        let phone = try Phone()
        defer { phone.remove() }
        try await phone.open(
            with: Self.snapshot("e_10", messages: [Self.ask, Self.reply, Self.post]))
        await phone.session.keepCopy()
        await phone.goOffline()
        let again = phone.relaunch()
        again.start()
        await phone.goOnline()
        _ = try await phone.nextRequest()
        try await phone.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await phone.settle()

        // The server's snapshot starts later than the copy does.
        let snapshot = Self.snapshot("e_12", messages: [Self.reply, Self.post], more: true)
        try await phone.push(snapshot)
        #expect(again.conversation.entries.map(\.id) == ["u_1", "a_1", "a_2"])
        #expect(again.conversation.steps.map(\.id) == ["s_1"])
        #expect(!again.conversation.hasEarlierMessages)

        // A snapshot once it's live replaces it as ever.
        try await phone.push(Self.snapshot("e_13", messages: [Self.post], more: true))
        #expect(again.conversation.entries.map(\.id) == ["a_2"])
        #expect(again.conversation.hasEarlierMessages)
        again.close()
    }

    @Test("leaving the server forgets its copy")
    func forgetting() async throws {
        let phone = try Phone()
        defer { phone.remove() }
        try await phone.open(with: Self.snapshot("e_10", messages: [Self.ask]))
        await phone.session.keepCopy()
        #expect(phone.copies.data("session/conversation") != nil)

        await phone.session.forgetCopy()
        phone.session.close()
        #expect(phone.copies.data("session/conversation") == nil)
        #expect(phone.copies.data("/v0/desk") == nil)
        #expect(phone.relaunch().conversation.entries.isEmpty)
    }

    @Test("In motion, Made pages and the Library show what was read last, at once and offline")
    func storesKeepWhatTheyRead() async throws {
        let phone = try Phone()
        defer { phone.remove() }
        let client = phone.client
        let trip = try Fixtures.transcript("62-a-trip-in-motion")
        let made = try Fixtures.transcript("91-a-page-kumo-made")
        let chapters = try Fixtures.transcript("87-chapters-and-what-kumo-learnt")
        let remembers = try Fixtures.transcript("34-ari-uses-what-it-remembers")
        let page = PageAddress("memory:people/alex")

        // Online, each answer is kept as it arrives.
        let list = try await phone.fetch(from: trip, "/v0/motion") { try await client.motions() }
        let going = try #require(list.motions.first)
        _ = try await phone.fetch(from: trip, "/v0/motion/\(going.id)") {
            try await client.motion(going.id)
        }
        let shelf = try await phone.fetch(from: made, "/v0/made") { try await client.madePages() }
        _ = try await phone.fetch(from: made, "/v0/made/va-guide") {
            try await client.madePage("va-guide")
        }
        _ = try await phone.fetch(from: remembers, "/v0/memory/in-mind") {
            try await client.inMind()
        }
        _ = try await phone.fetch(from: chapters, "/v0/memory/shelves") {
            try await client.shelves()
        }
        let noticed = try await phone.fetch(from: chapters, "/v0/memory/chapters") {
            try await client.chapters()
        }
        _ = try await phone.fetch(from: chapters, "/v0/memory/learnt") { try await client.learnt() }
        let alex = try await phone.fetch(from: remembers, "/v0/memory/page?address=\(page)") {
            try await client.page(page)
        }

        // Offline, and opened again: each shows at once, without asking.
        await phone.goOffline()
        let motions = Motions(client: client, defaults: try #require(UserDefaults(suiteName: "o")))
        #expect(motions.load == .loaded)
        #expect(motions.all.map(\.id) == list.motions.map(\.id))
        #expect(motions.details[going.id] != nil)
        let pages = MadePages(client: client)
        #expect(pages.load == .loaded && pages.all.map(\.id) == shelf.made.map(\.id))
        let memory = Memory(client: client)
        #expect(memory.load == .loaded)
        #expect(memory.chapters.map(\.id) == noticed.chapters.map(\.id))
        #expect(!memory.learnt.isEmpty)
        #expect(memory.keptPage(page) == alex)

        // Asked again, the copy stands in for what the server can't say.
        #expect(try await pages.detail("va-guide").made.id == "va-guide")
        #expect(try await memory.page(page) == alex)
        await motions.refresh()
        #expect(motions.load == .loaded && motions.all.map(\.id) == list.motions.map(\.id))
        #expect(await phone.server.takeRequest() == nil)
    }

    @Test("a page the server says is gone isn't shown from the copy")
    func goneIsGone() async throws {
        let phone = try Phone()
        defer { phone.remove() }
        let client = phone.client
        let made = try Fixtures.transcript("91-a-page-kumo-made")
        _ = try await phone.fetch(from: made, "/v0/made/va-guide") {
            try await client.madePage("va-guide")
        }
        let pages = MadePages(client: client)
        let asking = Task { try await pages.detail("va-guide") }
        _ = try await phone.nextRequest()
        #expect(pages.details["va-guide"] != nil, "the copy shows while it's asked for")
        try await phone.server.answer(
            404, json: #"{"error":{"code":"not_found","message":"That page is gone."}}"#)
        await #expect(throws: RequestError.self) { try await asking.value }
        #expect(pages.details["va-guide"] == nil)
        #expect(pages.forgotten.contains("va-guide"))
    }

    @Test("without the server, Threads by day lists the threads Ari knows")
    func threadsOffline() async throws {
        let phone = try Phone()
        defer { phone.remove() }
        try await phone.open(with: Self.snapshot("e_10", messages: [Self.ask]))
        await phone.goOffline()
        let all = try await phone.session.threads()
        #expect(all.open.map(\.id) == ["th_1"])
        #expect(try await phone.session.threads(matching: "menu").open.count == 1)
        #expect(try await phone.session.threads(matching: "dentist").open.isEmpty)
        phone.session.close()
    }

    @Test(
        "every conversation the transcripts leave is kept and read back as it was",
        arguments: try Fixtures.transcripts())
    func copiesRoundTrip(_ transcript: Transcript) throws {
        var replay = Replay(transcript)
        try replay.play()
        for conversation in [replay.conversation] + Array(replay.threads.values) {
            let copy = conversation.copy()
            let read = try JSONDecoder().decode(
                Conversation.Copy.self, from: try JSONEncoder().encode(copy))
            #expect(read == copy, "\(transcript.name)")
            let restored = Conversation(copy: read)
            #expect(restored.copy() == copy, "\(transcript.name)")
            let shown = conversation.entries.prefix(restored.entries.count)
            #expect(restored.entries.map(\.id) == shown.map(\.id), "\(transcript.name)")
            #expect(restored.entries.map(\.text) == shown.map(\.text), "\(transcript.name)")
        }
    }

    @Test("the note says when the copy was last brought up to date")
    func note() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        let locale = Locale(identifier: "en_GB")
        let now = try #require(Timestamp("2026-11-10T15:30:00.000Z")).date
        func words(_ at: String?) -> String {
            OfflineNote.words(
                updatedAt: at.flatMap { Timestamp($0)?.date }, now: now, calendar: calendar,
                locale: locale)
        }
        #expect(words(nil) == "Offline")
        #expect(words("2026-11-10T14:02:00.000Z") == "Offline · updated 14:02")
        #expect(words("2026-11-09T22:14:00.000Z") == "Offline · updated yesterday 22:14")
        #expect(words("2026-11-03T09:00:00.000Z") == "Offline · updated 3 Nov")
    }

    // MARK: - The server's side

    private static let sent: MessageID = "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10"

    private static let ask =
        #"{"id":"u_1","role":"user","text":"Plan Saturday with Mira","at":"2026-11-10T07:00:00.000Z","position":1}"#
    private static let reply =
        #"{"id":"a_1","role":"agent","kind":"reply","turn":"t_1","text":"Kiln at 7, then the river.","at":"2026-11-10T07:00:05.000Z","position":3,"ended_at":"2026-11-10T07:00:09.000Z","outcome":"completed"}"#
    private static let post =
        #"{"id":"a_2","role":"agent","kind":"post","text":"Kiln moved you to 7:30.","at":"2026-11-10T08:10:00.000Z","position":5,"outcome":"completed"}"#
    private static let step =
        #"{"id":"s_1","turn":"t_1","kind":"web_search","title":"Searched for Kiln","at":"2026-11-10T07:00:02.000Z","position":2,"ended_at":"2026-11-10T07:00:04.000Z","outcome":"completed","query":"Kiln menu"}"#
    private static let thread =
        #"{"id":"th_1","title":"Kiln menu","by":"you","state":"open","started_at":"2026-11-10T07:10:00.000Z","position":4,"replies":1,"last_at":"2026-11-10T07:12:00.000Z"}"#
    private static let threadPage =
        #"{"thread":\#(thread),"anchor":null,"messages":[{"id":"u_t1","role":"user","text":"What's on the menu?","at":"2026-11-10T07:12:00.000Z","position":1,"thread":"th_1"}],"steps":[],"asks":[],"turn":null,"next":[],"has_more":false}"#
    private static let desk =
        #"{"line":{"text":"Kiln is booked for Saturday.","mood":"content","at":"2026-11-10T08:00:00.000Z"},"coming_up":[],"waiting":[{"id":"k_1","kind":"question","at":"2026-11-10T06:00:00.000Z","title":"Binned a mail from Halcyon","options":[{"label":"Right"},{"label":"Keep it"}],"allows_text":true,"question":{"text":"I binned it. Right?"}}]}"#
    private static let mine =
        #"{"id":"\#(sent.rawValue)","role":"user","text":"Book the 7:30?","at":"2026-11-10T09:00:00.000Z","position":7}"#
    private static let accepted = #"{"message":\#(mine)}"#

    private static func snapshot(_ id: String, messages: [String], more: Bool = false) -> String {
        #"{"id":"\#(id)","type":"snapshot","at":"2026-11-10T08:00:00.000Z","reason":"no_cursor","messages":[\#(messages.joined(separator: ","))],"has_more":\#(more),"steps":[\#(step)],"asks":[],"calls":[],"threads":[\#(thread)],"turn":null,"next":[],"desk":\#(desk)}"#
    }

    /// Kumo's post, as `message.posted`, or (not `wrapped`) the message alone.
    private static func posted(
        _ event: String, _ id: String, _ text: String, position: Int, wrapped: Bool = true
    ) -> String {
        let message =
            #"{"id":"\#(id)","role":"agent","kind":"post","text":"\#(text)","at":"2026-11-10T08:10:00.000Z","position":\#(position),"outcome":"completed"}"#
        guard wrapped else { return message }
        return
            #"{"id":"\#(event)","type":"message.posted","at":"2026-11-10T08:10:00.000Z","message":\#(message)}"#
    }
}

/// One phone, through launches: a scripted server, a network and a clock the test controls, and
/// the copy kept on the device, which outlives each session.
@MainActor
private final class Phone {
    let clock = TestClock<Duration>()
    let server = ScriptedServer()
    let network = FakeNetwork()
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "AriKitTests/\(UUID().uuidString)", directoryHint: .isDirectory)
    private(set) var session: Session

    var copies: LocalCopy { LocalCopy(directory: directory.appending(path: "copy")) }

    var client: ItoClient {
        ItoClient(
            address: session.address, token: Rehearsal.token, transport: server, copies: copies)
    }

    init() throws {
        session = Session(
            connection: try Rehearsal.connection(),
            outbox: OutboxStore(directory: directory.appending(path: "outbox")),
            copies: LocalCopy(directory: directory.appending(path: "copy")), transport: server,
            network: network, clock: clock)
    }

    /// Ari is opened again from cold, with what the last run left on the device.
    func relaunch() -> Session {
        session.close()
        session = Session(
            address: session.address, token: Rehearsal.token,
            outbox: OutboxStore(directory: directory.appending(path: "outbox")), copies: copies,
            transport: server, network: network, clock: clock)
        return session
    }

    func open(with snapshot: String) async throws {
        session.start()
        let request = try await nextRequest()
        #expect(request.path == "/v0/events" && request.headers["Last-Event-ID"] == nil)
        try await server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await settle()
        try await push(snapshot)
    }

    func push(_ json: String) async throws {
        try await server.push(json: json)
        await settle()
    }

    func goOffline() async {
        network.set(false)
        await server.setOnline(false)
    }

    func goOnline() async {
        await server.setOnline(true)
        network.set(true)
    }

    /// Makes a request, and answers it as `transcript`'s server answered `path`.
    func fetch<Answer: Sendable>(
        from transcript: Transcript, _ path: String,
        _ call: @escaping @Sendable () async throws -> Answer
    ) async throws -> Answer {
        let asking = Task { try await call() }
        let request = try await nextRequest()
        #expect(request.path == path)
        var asked = false
        for step in transcript.steps {
            if case .app(let made) = step, made.path == path { asked = true }
            if asked, case .server(let response) = step {
                try await server.answer(response)
                return try await asking.value
            }
        }
        throw TranscriptError("\(transcript.name) never answers \(path)")
    }

    /// Waits, for a few real seconds at most, for the copy to be on the device.
    func waitForCopy() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while copies.data("session/conversation") == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(copies.data("session/conversation") != nil)
        #expect(copies.data("/v0/desk") != nil)
    }

    func nextRequest() async throws -> HTTPRequest {
        for _ in 0..<100 {
            await settle()
            if let request = await server.takeRequest() { return request }
            await clock.advance(by: .milliseconds(100))
        }
        throw TranscriptError("Ari made no request within ten seconds")
    }

    func settle() async {
        for _ in 0..<4 {
            for _ in 0..<10 { await Task.yield() }
            _ = await server.isStreaming
        }
    }

    func remove() {
        session.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
