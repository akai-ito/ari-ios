import AriKit
import Foundation
import Testing

/// What the transcripts don't reach: a silent connection, Stop while the stream is down or before
/// the turn is announced, Retry-After, a token the server stops accepting, a protocol it no longer
/// speaks, a restart with messages still waiting, and a stale view while scrolling back.
@MainActor
@Suite("The client, at the edges")
struct SessionEdgeTests {
    /// A session resumed after the idle conversation of scenario 4, with its stream open.
    private func live(_ name: String = "04-the-agent-stirs") async throws -> Rehearsal {
        let bench = try Rehearsal(try Fixtures.transcript(name))
        bench.session.start()
        let open = try await bench.nextRequest()
        #expect(open.path == "/v0/events")
        try await bench.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await bench.settle()
        #expect(bench.session.link == .live)
        return bench
    }

    @Test("45 seconds without even a ping means the connection is gone: Ari resumes")
    func silence() async throws {
        let bench = try await live()
        defer { bench.close() }

        // Pings keep a quiet stream alive.
        await bench.advance(to: 120_000)
        #expect(await bench.server.takeRequest() == nil)

        // Silence doesn't.
        await bench.clock.advance(by: .seconds(46))
        let resume = try await bench.nextRequest()
        #expect(resume.path == "/v0/events")
        #expect(resume.headers["Last-Event-ID"] == "e_0009_44455")
    }

    @Test("Stop goes at once, even while the stream is still reconnecting")
    func stopWhileReconnecting() async throws {
        let bench = try await live()
        defer { bench.close() }
        try await pushTurn(to: bench, writing: "Here's a shape for Saturday:")

        await bench.server.dropStream()
        let reconnect = try await bench.nextRequest()
        #expect(reconnect.path == "/v0/events")
        #expect(bench.session.link == .reconnecting)

        // The reconnect hangs unanswered; Stop doesn't wait for it.
        let cut = Cut(message: "m_0100", offset: 6)
        bench.session.stop(cut: cut)
        let stop = try await bench.nextRequest()
        #expect(stop.path == "/v0/turns/t_0100/stop")
        #expect(
            try stop.body.map { try JSONValue(data: $0) } == JSONValue(encoding: StopTurn(cut: cut))
        )
        #expect(
            bench.session.conversation.visibleText(
                of: try #require(bench.session.conversation["m_0100"])) == "Here's")
    }

    @Test("Stop tapped before the turn is announced goes as soon as it is")
    func stopBeforeTheTurn() async throws {
        let bench = try await live()
        defer { bench.close() }
        let id = try #require(bench.session.send("Hi", id: "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10"))
        _ = try await bench.nextRequest()
        try await bench.server.answer(201, json: accepted(id))
        try await bench.server.push(json: acceptedEvent(id))
        await bench.settle()

        bench.session.stop(cut: nil)
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil)

        try await bench.server.push(json: turnStarted(answering: id))
        let stop = try await bench.nextRequest()
        #expect(stop.path == "/v0/turns/t_0100/stop")
    }

    @Test("A busy server's Retry-After is honoured before sending again")
    func retryAfter() async throws {
        let bench = try await live()
        defer { bench.close() }
        let id = try #require(bench.session.send("Hi", id: "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10"))
        _ = try await bench.nextRequest()
        try await bench.server.answer(
            429, headers: ["Retry-After": "5"],
            json: #"{"error":{"code":"busy","message":"Ito is busy. Trying again shortly."}}"#)
        await bench.settle()

        await bench.tick(.milliseconds(4_900))
        #expect(await bench.server.takeRequest() == nil)
        await bench.tick(.milliseconds(200))
        let again = try await bench.nextRequest()
        #expect(again.path == "/v0/messages")
        #expect(try again.body.map { try JSONValue(data: $0) }?["id"]?.string == id.rawValue)
    }

    @Test("A token the server stops accepting needs you: Ari stops reconnecting")
    func tokenRejected() async throws {
        let bench = try Rehearsal(try Fixtures.transcript("04-the-agent-stirs"))
        defer { bench.close() }
        bench.session.start()
        _ = try await bench.nextRequest()
        try await bench.server.answer(
            401,
            json:
                #"{"error":{"code":"token_rejected","message":"The server didn't accept this token."}}"#
        )
        await bench.settle()

        guard case .tokenRejected(let error) = bench.session.problem else {
            Issue.record(
                "expected a rejected token, not \(String(describing: bench.session.problem))")
            return
        }
        #expect(error?.message == "The server didn't accept this token.")
        await bench.advance(to: 120_000)
        #expect(await bench.server.takeRequest() == nil)
    }

    @Test("A server that moves to a newer protocol asks you to update Ari")
    func protocolMismatch() async throws {
        let bench = try Rehearsal(try Fixtures.transcript("04-the-agent-stirs"))
        defer { bench.close() }
        bench.session.start()
        _ = try await bench.nextRequest()
        try await bench.server.answer(200, headers: ["Ito-Protocol": "0.5"])
        await bench.settle()

        guard case .protocolMismatch(let mismatch) = bench.session.problem else {
            Issue.record(
                "expected a protocol mismatch, not \(String(describing: bench.session.problem))")
            return
        }
        #expect(mismatch.update == .ari)
    }

    @Test("Messages still waiting when Ari closes are sent, in order, when it opens again")
    func restartWithWaitingMessages() async throws {
        let transcript = try Fixtures.transcript("04-the-agent-stirs")
        let first = try Rehearsal(transcript)
        first.session.start()
        _ = try await first.nextRequest()
        // The stream never opens, so the messages wait.
        first.session.send("One", id: "00000000-0000-4000-8000-000000000001")
        first.session.send("Two", id: "00000000-0000-4000-8000-000000000002")
        await first.settle()
        #expect(await first.server.takeRequest() == nil)
        first.session.close()

        let second = try Rehearsal(transcript, outboxDirectory: first.outboxDirectory)
        defer { second.close() }
        second.session.start()
        #expect(second.session.conversation.entries.suffix(2).map(\.text) == ["One", "Two"])
        _ = try await second.nextRequest()
        try await second.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        let send = try await second.nextRequest()
        #expect(try send.body.map { try JSONValue(data: $0) }?["text"]?.string == "One")
    }

    @Test("Scrolling back past what the server still has replaces the view with a snapshot")
    func staleHistory() async throws {
        let bench = try await live("09-scrolling-back")
        defer { bench.close() }
        let session = bench.session
        Task { await session.loadEarlier() }
        let page = try await bench.nextRequest()
        #expect(page.path.hasPrefix("/v0/messages?before="))
        try await bench.server.answer(
            404,
            json: #"{"error":{"code":"not_found","message":"That message isn't on the server."}}"#)
        let resume = try await bench.nextRequest()
        #expect(resume.path == "/v0/events")
        #expect(resume.headers["Last-Event-ID"] == nil)
    }

    @Test("Nothing, or more than the server takes, isn't sent")
    func unsendable() async throws {
        let bench = try await live()
        defer { bench.close() }
        #expect(bench.session.send("  \n ") == nil)
        #expect(bench.session.send(String(repeating: "a", count: Session.maximumLength + 1)) == nil)
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil)
    }

    // MARK: - Attachments

    private let photo = PendingAttachment(
        id: "00000000-0000-4000-8000-0000000000a1", name: "riverside.jpg", mediaType: "image/jpeg",
        bytes: Data(count: 1454))

    @Test("A message waits for its photo's upload, and goes once the server has it")
    func waitsForItsPhoto() async throws {
        let bench = try await live()
        defer { bench.close() }
        bench.session.attach(photo)
        let id = bench.session.send(
            "", id: "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10", attachments: [photo.id])
        #expect(id != nil)
        #expect(bench.session.conversation.entries.last?.attachments == [photo.attachment])
        let upload = try await bench.nextRequest()
        #expect(upload.path == "/v0/attachments/\(photo.id)?name=riverside.jpg")
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil, "the message went before its photo")

        try await bench.server.answer(201, json: uploaded(photo))
        let send = try await bench.nextRequest()
        #expect(send.path == "/v0/messages")
        #expect(
            try send.body.map { try JSONValue(data: $0) }?["attachments"]
                == JSONValue(json: #"["\#(photo.id)"]"#))
    }

    @Test("A message isn't sent when its photo is refused, and says why")
    func refusedPhoto() async throws {
        let bench = try await live()
        defer { bench.close() }
        bench.session.attach(photo)
        let id = try #require(
            bench.session.send(
                "Look", id: "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10", attachments: [photo.id]))
        _ = try await bench.nextRequest()
        try await bench.server.answer(
            413,
            json:
                #"{"error":{"code":"too_large","message":"That file is larger than Ito accepts."}}"#
        )
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil)
        #expect(bench.session.refusedMessages[id]?.status == 413)
        guard case .refused = bench.session.uploads[photo.id] else {
            Issue.record("expected the upload to be refused")
            return
        }
    }

    @Test("An attachment's bytes are fetched once and kept; your own photo is never fetched")
    func fetchedOnce() async throws {
        let bench = try await live()
        defer { bench.close() }
        let session = bench.session
        let theirs: AttachmentID = "9f590555-6aa5-480f-832f-950cc1f5b651"
        let first = Task { await session.bytes(of: theirs) }
        let second = Task { await session.bytes(of: theirs) }
        let fetch = try await bench.nextRequest()
        #expect(fetch.path == "/v0/attachments/\(theirs)")
        try await bench.server.answer(200, headers: ["Content-Length": "1454"])
        #expect(await first.value?.count == 1454)
        #expect(await second.value?.count == 1454)
        #expect(await session.bytes(of: theirs)?.count == 1454)

        session.attach(photo)
        #expect(await session.bytes(of: photo.id) == photo.bytes)
        let upload = try await bench.nextRequest()
        #expect(upload.method == .put)
        #expect(await bench.server.takeRequest() == nil)
    }

    @Test("A photo still uploading when Ari closes uploads when it opens again, then its message")
    func restartWithAPhoto() async throws {
        let transcript = try Fixtures.transcript("04-the-agent-stirs")
        let first = try Rehearsal(transcript)
        first.session.start()
        _ = try await first.nextRequest()
        first.session.attach(photo)
        first.session.send(
            "Look", id: "00000000-0000-4000-8000-000000000001", attachments: [photo.id])
        // The upload hangs, then Ari closes.
        _ = try await first.nextRequest()
        first.session.close()

        let second = try Rehearsal(transcript, outboxDirectory: first.outboxDirectory)
        defer { second.close() }
        second.session.start()
        #expect(second.session.conversation.entries.last?.attachments == [photo.attachment])
        var paths: [String] = []
        for _ in 0..<2 { paths.append(try await second.nextRequest().path) }
        #expect(Set(paths) == ["/v0/events", "/v0/attachments/\(photo.id)?name=riverside.jpg"])
    }

    @Test("A photo the server no longer has goes again, under the same id, then the message")
    func photoGoneOvernight() async throws {
        let bench = try await live()
        defer { bench.close() }
        bench.session.attach(photo)
        let id = try #require(
            bench.session.send(
                "Look", id: "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10", attachments: [photo.id]))
        let upload = try await bench.nextRequest()
        try await bench.server.answer(201, json: uploaded(photo))
        _ = try await bench.nextRequest()
        let missing =
            #"{"error":{"code":"attachment_missing","message":"Upload every attachment before sending."}}"#
        try await bench.server.answer(400, json: missing)

        let again = try await bench.nextRequest()
        #expect(again.path == upload.path && again.body == upload.body)
        try await bench.server.answer(200, json: uploaded(photo))
        let resend = try await bench.nextRequest()
        #expect(resend.path == "/v0/messages")
        #expect(try resend.body.map { try JSONValue(data: $0) }?["id"]?.string == id.rawValue)

        // Only once: the same answer again means the message can't go.
        try await bench.server.answer(400, json: missing)
        await bench.settle()
        #expect(await bench.server.takeRequest() == nil)
        #expect(bench.session.refusedMessages[id]?.serverError?.code == .attachmentMissing)
    }

    @Test("A photo no waiting message names, left from a draft, is dropped when Ari opens again")
    func restartWithADraftPhoto() async throws {
        let transcript = try Fixtures.transcript("04-the-agent-stirs")
        let first = try Rehearsal(transcript)
        first.session.start()
        _ = try await first.nextRequest()
        first.session.attach(photo)
        _ = try await first.nextRequest()
        first.session.close()

        let second = try Rehearsal(transcript, outboxDirectory: first.outboxDirectory)
        defer { second.close() }
        second.session.start()
        #expect(try await second.nextRequest().path == "/v0/events")
        await second.settle()
        #expect(await second.server.takeRequest() == nil)
    }

    @Test("A + in a file's name reaches the server as a +")
    func plusInName() async throws {
        let bench = try await live()
        defer { bench.close() }
        let notes = PendingAttachment(
            id: "00000000-0000-4000-8000-0000000000b2", name: "C++ notes.pdf",
            mediaType: "application/pdf", bytes: Data(count: 10))
        bench.session.attach(notes)
        let upload = try await bench.nextRequest()
        #expect(upload.path == "/v0/attachments/\(notes.id)?name=C%2B%2B%20notes.pdf")
    }

    private func uploaded(_ attachment: PendingAttachment) -> String {
        #"{"attachment":{"id":"\#(attachment.id)","kind":"image","name":"\#(attachment.name)","media_type":"image/jpeg","size":1454}}"#
    }

    // MARK: - Events

    private func pushTurn(to bench: Rehearsal, writing text: String) async throws {
        try await bench.server.push(
            json:
                #"{"id":"e_0100","type":"turn.started","at":"2026-10-12T08:41:02.061Z","turn":"t_0100","inputs":[]}"#
        )
        try await bench.server.push(
            json: #"""
                {"id":"e_0101","type":"message.started","at":"2026-10-12T08:41:03.000Z","message":{"id":"m_0100","role":"agent","kind":"reply","turn":"t_0100","text":"","at":"2026-10-12T08:41:03.000Z"}}
                """#)
        try await bench.server.push(
            json: #"""
                {"id":"e_0102","type":"message.delta","at":"2026-10-12T08:41:03.100Z","message":"m_0100","offset":0,"text":"\#(text)"}
                """#)
        await bench.settle()
    }

    private func accepted(_ id: MessageID) -> String {
        #"{"message":{"id":"\#(id)","role":"user","text":"Hi","at":"2026-10-12T08:41:02.055Z"}}"#
    }

    private func acceptedEvent(_ id: MessageID) -> String {
        #"""
        {"id":"e_0100","type":"message.accepted","at":"2026-10-12T08:41:02.055Z","message":{"id":"\#(id)","role":"user","text":"Hi","at":"2026-10-12T08:41:02.055Z"}}
        """#
    }

    private func turnStarted(answering id: MessageID) -> String {
        #"{"id":"e_0101","type":"turn.started","at":"2026-10-12T08:41:02.061Z","turn":"t_0100","inputs":["\#(id)"]}"#
    }
}
