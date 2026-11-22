import AriKit
import Foundation
import Testing

/// A recording starts its own thread: sent to the main chat, it goes into a thread started here at
/// once, which the server names, and the thread's top says how it's getting on.
@MainActor
@Suite("A recording's own thread")
struct RecordingThreadTests {
    private let memo = PendingAttachment(
        id: "00000000-0000-4000-8000-0000000000c1", name: "Fernhill second round.m4a",
        mediaType: "audio/mp4", bytes: Data(count: 2048))
    private let photo = PendingAttachment(
        id: "00000000-0000-4000-8000-0000000000a1", name: "riverside.jpg", mediaType: "image/jpeg",
        bytes: Data(count: 1454))
    private let said: MessageID = "6a1d2c38-0f1e-4c5b-9d1f-2b7e4b1c9a10"

    /// A session resumed after the idle conversation of scenario 4, with its stream open.
    private func live() async throws -> Rehearsal {
        let bench = try Rehearsal(try Fixtures.transcript("04-the-agent-stirs"))
        bench.session.start()
        _ = try await bench.nextRequest()
        try await bench.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await bench.settle()
        return bench
    }

    private func uploaded(_ attachment: PendingAttachment) -> String {
        let kind = attachment.attachment.kind.rawValue
        return
            #"{"attachment":{"id":"\#(attachment.id)","kind":"\#(kind)","name":"\#(attachment.name)","media_type":"\#(attachment.mediaType)","size":\#(attachment.bytes.count)}}"#
    }

    private func body(_ request: HTTPRequest) throws -> JSONValue? {
        try request.body.map { try JSONValue(data: $0) }
    }

    @Test("A recording for the main chat starts a thread at once, and the server names it")
    func startsItsThread() async throws {
        let bench = try await live()
        defer { bench.close() }
        let session = bench.session
        session.attach(memo)
        let id = try #require(
            session.send("Second round done. How did I do?", id: said, attachments: [memo.id]))

        // It shows in a thread of its own, not the main chat, which keeps a line for it.
        let draft = try #require(session.draft(holding: id))
        #expect(session.conversation[id] == nil)
        #expect(session.conversation(in: draft)[id]?.attachments == [memo.attachment])
        #expect(session.drafts[draft] == .some(nil), "a thread of its own, not a reply")
        #expect(session.waitingThreads == [draft])

        let upload = try await bench.nextRequest()
        #expect(upload.path.hasPrefix("/v0/attachments/\(memo.id)"))
        try await bench.server.answer(201, json: uploaded(memo))
        let send = try await bench.nextRequest()
        #expect(send.path == "/v0/messages")
        let sent = try body(send)
        #expect(sent?["new_thread"] == .bool(true))
        #expect(sent?["thread"] == nil && sent?["reply_to"] == nil)

        try await bench.server.answer(
            201,
            json:
                #"{"message":{"id":"\#(id)","role":"user","text":"Second round done. How did I do?","at":"2026-10-12T08:41:02.055Z","thread":"h_0001_16040"}}"#
        )
        await bench.settle()
        #expect(session.resolved(draft) == "h_0001_16040")
        #expect(session.drafts.isEmpty && session.waitingThreads.isEmpty)
        #expect(session.conversation(in: draft)[id]?.delivery == .delivered)
    }

    @Test(
        "Only a recording for the main chat starts one: a photo, or a recording in a thread, stays")
    func staysWhereSent() async throws {
        #expect(Session.startsThread(carrying: [memo.attachment]))
        #expect(!Session.startsThread(carrying: [photo.attachment]))

        let bench = try await live()
        defer { bench.close() }
        let session = bench.session
        session.attach(photo)
        let look = try #require(session.send("Look", attachments: [photo.id]))
        #expect(session.conversation[look] != nil && session.draft(holding: look) == nil)
        _ = try await bench.nextRequest()
        try await bench.server.answer(201, json: uploaded(photo))
        let photoSent = try body(try await bench.nextRequest())
        #expect(photoSent?["new_thread"] == nil && photoSent?["thread"] == nil)
        try await bench.server.answer(
            201,
            json:
                #"{"message":{"id":"\#(look)","role":"user","text":"Look","at":"2026-10-12T08:41:02.055Z"}}"#
        )

        session.attach(memo)
        let inThread = try #require(
            session.send("The second half", attachments: [memo.id], in: "h_0002"))
        #expect(session.conversation(in: "h_0002")[inThread] != nil)
        #expect(session.waitingThreads.isEmpty)
        _ = try await bench.nextRequest()
        try await bench.server.answer(201, json: uploaded(memo))
        let memoSent = try body(try await bench.nextRequest())
        #expect(memoSent?["thread"] == .string("h_0002") && memoSent?["new_thread"] == nil)
    }

    @Test("Sent again, as a shared recording is each time Ari comes back, it keeps its one thread")
    func sentAgain() async throws {
        let bench = try await live()
        defer { bench.close() }
        let session = bench.session
        session.attach(memo)
        session.send("Second round done", id: said, attachments: [memo.id])
        session.send("Second round done", id: said, attachments: [memo.id])
        #expect(session.waitingThreads.count == 1)
        #expect(session.drafts.count == 1)
    }

    @Test("A recording still going up when Ari closes is in its thread again when Ari opens")
    func afterARestart() async throws {
        let transcript = try Fixtures.transcript("04-the-agent-stirs")
        let first = try Rehearsal(transcript)
        first.session.start()
        _ = try await first.nextRequest()
        first.session.attach(memo)
        first.session.send("Second round done", id: said, attachments: [memo.id])
        // The upload hangs, then Ari closes.
        _ = try await first.nextRequest()
        first.session.close()

        let second = try Rehearsal(transcript, outboxDirectory: first.outboxDirectory)
        defer { second.close() }
        second.session.start()
        let draft = try #require(second.session.draft(holding: said))
        #expect(second.session.waitingThreads == [draft])
        #expect(second.session.conversation[said] == nil)
        #expect(second.session.conversation(in: draft)[said]?.attachments == [memo.attachment])
    }

    // MARK: - The thread's top

    private let thread: ThreadID = "h_0001_16040"

    /// A thread holding your recording, just sent from this phone, or with the server's answer.
    private func conversation(delivered: Bool = false, attaching: [PendingAttachment]? = nil)
        throws -> Conversation
    {
        var conversation = Conversation(place: thread)
        conversation.send(
            said, text: "Second round done",
            attachments: (attaching ?? [memo]).map(\.attachment))
        if delivered {
            let answer =
                #"{"message":{"id":"\#(said)","role":"user","text":"Second round done","at":"2026-11-21T16:04:00.000Z","thread":"\#(thread)"}}"#
            conversation.confirm(
                try JSONDecoder().decode(MessageResult.self, from: Data(answer.utf8)))
        }
        return conversation
    }

    private func upload(received: Int, state: BigUpload.State = .sending) -> BigUpload {
        var upload = BigUpload(
            id: memo.id, name: memo.name, mediaType: memo.mediaType, size: 74_000_000,
            chunkLimit: 8_000_000)
        upload.received = received
        upload.state = state
        return upload
    }

    private func recording(_ state: String, progress: String = "") throws -> [AttachmentID:
        Recording]
    {
        let json =
            #"{"attachment":"\#(memo.id)","message":"\#(said)","name":"\#(memo.name)","state":"\#(state)"\#(progress),"changed_at":"2026-11-21T16:06:00.000Z"}"#
        return [memo.id: try JSONDecoder().decode(Recording.self, from: Data(json.utf8))]
    }

    @Test("The thread's top: uploading with how far, then waiting, then transcribing, then nothing")
    func header() throws {
        let sending = try conversation()
        let going = [memo.id: upload(received: 31_100_000)]
        #expect(
            RecordingProgress(in: sending, uploads: going, recordings: [:])?.line
                == "Uploading your recording · 42%")
        // The chunk on its way counts, for a bar that moves smoothly.
        #expect(
            RecordingProgress(
                in: sending, uploads: going, sent: { $0.received + 7_380_000 }, recordings: [:]
            ) == .uploading(0.52))
        // Never 100% while it's still going.
        #expect(
            RecordingProgress(
                in: sending, uploads: [memo.id: upload(received: 74_000_000)],
                recordings: [:])?.line == "Uploading your recording · 99%")
        // A small one goes in one go, without a share to count.
        #expect(
            RecordingProgress(in: sending, uploads: [:], recordings: [:])?.line
                == "Uploading your recording")

        // Up, before the server says more.
        let attachment = Attachment(
            id: memo.id, kind: .audio, name: memo.name, mediaType: memo.mediaType,
            size: 74_000_000)
        let up = [memo.id: upload(received: 74_000_000, state: .finished(attachment))]
        #expect(
            RecordingProgress(in: sending, uploads: up, recordings: [:])?.line
                == "Waiting to transcribe your recording")

        let delivered = try conversation(delivered: true)
        #expect(
            RecordingProgress(in: delivered, uploads: up, recordings: try recording("queued"))
                == .waiting)
        #expect(
            RecordingProgress(
                in: delivered, uploads: up,
                recordings: try recording(
                    "transcribing",
                    progress: #","progress":{"done_seconds":950,"total_seconds":3120}"#)
            )?.line == "Transcribing your recording · 30%")
        #expect(
            RecordingProgress(
                in: delivered, uploads: up,
                recordings: try recording(
                    "transcribing", progress: #","progress":{"done_seconds":60}"#)
            )?.line == "Transcribing your recording")

        // Then the thread's own header again: heard, failed, refused, or never known here.
        for state in ["ready", "failed", "deleted"] {
            #expect(
                RecordingProgress(in: delivered, uploads: up, recordings: try recording(state))
                    == nil)
        }
        let refused = upload(
            received: 0,
            state: .refused(
                ServerError(code: ErrorCode(rawValue: "too_large"), message: "Too big.")))
        #expect(RecordingProgress(in: sending, uploads: [memo.id: refused], recordings: [:]) == nil)
        #expect(RecordingProgress(in: delivered, uploads: [:], recordings: [:]) == nil)
        #expect(
            RecordingProgress(
                in: try conversation(attaching: [photo]), uploads: [:], recordings: [:])
                == nil)
    }
}
