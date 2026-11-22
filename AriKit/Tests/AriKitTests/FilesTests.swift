import AriKit
import Foundation
import Testing

@Suite("Big uploads, recordings and files")
@MainActor
struct FilesTests {
    private let id: AttachmentID = "00000000-0000-4000-8000-0000000000b1"
    private let message = SendMessage(
        id: "00000000-0000-4000-8000-000000000011", text: "Second round done. How did I do?",
        attachments: ["00000000-0000-4000-8000-0000000000b1"])

    private func folder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AriKitTests/\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func client(_ server: ScriptedServer) throws -> ItoClient {
        ItoClient(
            address: try ServerAddress("https://studio.example"),
            token: Token("ito_example_not_a_real_token_00000000000000000000"), transport: server)
    }

    /// A 20-byte "recording", sent 8 bytes a chunk.
    private func recording(in directory: URL) throws -> (BigUpload, URL) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "Fernhill second round.m4a")
        try Data((0..<20).map { UInt8($0) }).write(to: file)
        var upload = BigUpload(
            id: id, name: "Fernhill second round.m4a", mediaType: "audio/mp4", size: 20,
            chunkLimit: 8)
        upload.message = message
        return (upload, file)
    }

    private func status(received: Int) -> String {
        #"{"upload":{"id":"\#(id)","name":"Fernhill second round.m4a","media_type":"audio/mp4","kind":"audio","size":20,"received":\#(received),"state":"receiving"}}"#
    }

    private var attachment: String {
        #"{"attachment":{"id":"\#(id)","kind":"audio","name":"Fernhill second round.m4a","media_type":"audio/mp4","size":20}}"#
    }

    private func request(from server: ScriptedServer) async throws -> HTTPRequest {
        for _ in 0..<500 {
            if let request = await server.takeRequest() { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TranscriptError("no request within 5 seconds")
    }

    private func settle(_ uploads: BigUploads, until done: (BigUpload?) -> Bool) async throws {
        for _ in 0..<500 {
            if done(uploads.uploads[id]) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TranscriptError("the upload didn't settle within 5 seconds")
    }

    @Test("a recording goes in chunks, in order, then finishes and sends its message once")
    func chunks() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (upload, file) = try recording(in: directory)
        let server = ScriptedServer()
        let store = BigUploadStore(directory: directory.appending(path: "Uploads"))
        let uploads = BigUploads(
            store: store, client: try client(server), carrier: DirectChunkCarrier())
        var changes: [BigUpload.State] = []
        uploads.changed = { changes.append($0.state) }

        _ = Task { try await uploads.start(upload, file: file) }

        let create = try await request(from: server)
        #expect(create.method == .post && create.path == "/v0/uploads")
        let said = try JSONValue(data: #require(create.body))
        #expect(said["size"]?.int == 20 && said["media_type"]?.string == "audio/mp4")
        try await server.answer(201, json: status(received: 0))
        for (offset, length) in [(0, 8), (8, 8), (16, 4)] {
            let chunk = try await request(from: server)
            #expect(chunk.method == .put && chunk.path == "/v0/uploads/\(id)?offset=\(offset)")
            #expect(chunk.body == Data((offset..<offset + length).map { UInt8($0) }))
            #expect(chunk.headers["Content-Type"] == "application/octet-stream")
            try await server.answer(200, json: status(received: offset + length))
        }
        let finish = try await request(from: server)
        #expect(finish.method == .post && finish.path == "/v0/uploads/\(id)/finish")
        try await server.answer(201, json: attachment)
        let send = try await request(from: server)
        #expect(send.path == "/v0/messages")
        try await server.answer(
            201,
            json:
                #"{"message":{"id":"\#(message.id)","role":"user","text":"\#(message.text)","at":"2026-11-21T16:04:00.000Z"}}"#
        )

        try await settle(uploads) { $0?.messageSent == true }
        guard case .finished(let made) = uploads.uploads[id]?.state else {
            Issue.record("not finished")
            return
        }
        #expect(made.kind == .audio)
        #expect(store.load(id)?.messageSent == true)
        #expect(store.keptFile(id) != nil, "the recording stays on the phone to play")
        #expect(changes.contains(.sending))
        #expect(await server.takeRequest() == nil)
    }

    @Test("it resumes from what the server has, and an early chunk asks where it stands")
    func resumes() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (upload, file) = try recording(in: directory)
        let server = ScriptedServer()
        let uploads = BigUploads(
            store: BigUploadStore(directory: directory.appending(path: "Uploads")),
            client: try client(server), carrier: DirectChunkCarrier())

        _ = Task { try await uploads.start(upload, file: file) }

        _ = try await request(from: server)
        // The server already had the first chunk, from a try before Ari closed.
        try await server.answer(200, json: status(received: 8))
        let early = try await request(from: server)
        #expect(early.path == "/v0/uploads/\(id)?offset=8")
        try await server.answer(
            409,
            json:
                #"{"error":{"code":"offset_mismatch","message":"Send from 16."},"upload":\#(status(received: 16).dropFirst(10).dropLast())}"#
        )
        let asked = try await request(from: server)
        #expect(asked.method == .get && asked.path == "/v0/uploads/\(id)")
        try await server.answer(200, json: status(received: 16))
        let last = try await request(from: server)
        #expect(last.path == "/v0/uploads/\(id)?offset=16" && last.body?.count == 4)
        try await server.answer(200, json: status(received: 20))
        _ = try await request(from: server)
        try await server.answer(201, json: attachment)
        _ = try await request(from: server)
        try await server.answer(
            200,
            json:
                #"{"message":{"id":"\#(message.id)","role":"user","text":"\#(message.text)","at":"2026-11-21T16:04:00.000Z"}}"#
        )
        try await settle(uploads) { $0?.messageSent == true }
    }

    @Test("a recording too big for the server is refused in its words, and goes no further")
    func refused() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (upload, file) = try recording(in: directory)
        let server = ScriptedServer()
        let uploads = BigUploads(
            store: BigUploadStore(directory: directory.appending(path: "Uploads")),
            client: try client(server), carrier: DirectChunkCarrier())
        let session = Session(
            address: try ServerAddress("https://studio.example"),
            token: Token("ito_example_not_a_real_token_00000000000000000000"),
            outbox: OutboxStore(directory: directory.appending(path: "Outbox")), transport: server)
        uploads.changed = { session.bigUploadChanged($0) }

        _ = Task { try await uploads.start(upload, file: file) }
        _ = try await request(from: server)
        try await server.answer(
            413,
            json: #"{"error":{"code":"too_large","message":"Ito takes recordings up to 1 GB."}}"#)

        try await settle(uploads) { $0?.isSending == false }
        #expect(
            uploads.uploads[id]?.state
                == .refused(
                    ServerError(
                        code: ErrorCode(rawValue: "too_large"),
                        message: "Ito takes recordings up to 1 GB.")))
        guard case .refused(let error) = session.uploads[id] else {
            Issue.record("the session doesn't know")
            return
        }
        #expect(error.serverError?.message == "Ito takes recordings up to 1 GB.")
        #expect(await server.takeRequest() == nil)
    }

    @Test("chunks are planned from what the server has, never bigger than it takes")
    func planning() {
        var upload = BigUpload(
            id: id, name: "a.m4a", mediaType: "audio/mp4", size: 20 * 1024 * 1024,
            chunkLimit: 16 * 1024 * 1024)
        #expect(upload.chunkBytes == 8 * 1024 * 1024)
        let megabyte = 1024 * 1024
        let lengths: [Int] = upload.remainingChunks.map(\.length)
        #expect(lengths == [8 * megabyte, 8 * megabyte, 4 * megabyte])
        upload.received = 12 * 1024 * 1024
        #expect(
            upload.remainingChunks == [
                .init(offset: 12 * 1024 * 1024, length: 8 * 1024 * 1024)
            ])
        let small = BigUpload(id: id, name: "a", mediaType: "audio/mp4", size: 10, chunkLimit: 4)
        #expect(small.remainingChunks.map(\.offset) == [0, 4, 8])
    }

    @Test("limits are said before anything goes, in the server's own numbers")
    func limits() {
        let megabyte = 1 << 20
        let audio = UploadLimits.Kind(kind: .audio, maxBytes: 1 << 30, mediaTypes: ["audio/mp4"])
        let file = UploadLimits.Kind(
            kind: .file, maxBytes: 100 * megabyte, mediaTypes: ["application/pdf"])
        let limits = UploadLimits(
            simpleBytes: 20 * megabyte, chunkBytes: 16 * megabyte, kinds: [audio, file])
        #expect(limits.refusal(name: "Memo.m4a", mediaType: "audio/mp4", size: 74 << 20) == nil)
        #expect(
            limits.refusal(name: "Long.m4a", mediaType: "audio/mp4", size: 2 << 30)
                == "Long.m4a is 2 GB: your server takes recordings up to 1 GB.")
        #expect(
            limits.refusal(name: "Trip.mov", mediaType: "video/quicktime", size: 30 << 20)
                == "Trip.mov is 30 MB: your server takes a file of this type up to 20 MB.")
        #expect(limits.refusal(name: "a.mov", mediaType: "video/quicktime", size: 1 << 20) == nil)
    }

    @Test("a tap says it in words and carries exactly what was tapped, hidden in the bubble")
    func taps() throws {
        let decision = YourTap.decision(
            .init(message: "m_kumo", item: "hold-cto", choice: .accept))
        let text = decision.message(saying: "Add · Hold Thursday 15:00 for the CTO round")
        #expect(text.hasPrefix("Add · Hold Thursday 15:00 for the CTO round\n\n```ari:decision\n"))
        #expect(YourTap.taps(in: text) == [decision])
        #expect(YourTap.words(of: text) == "Add · Hold Thursday 15:00 for the CTO round")
        let attach = YourTap.attach(.init(file: "sf_cv", version: 2))
        #expect(YourTap.taps(in: attach.message(saying: "Use version 2 in the draft")) == [attach])
        #expect(YourTap.words(of: "Just words") == "Just words")

        var conversation = Conversation()
        try conversation.apply(
            JSONDecoder().decode(
                Event.self,
                from: Data(
                    #"{"id":"e1","type":"message.posted","at":"2026-11-21T16:10:00.000Z","message":{"id":"m_kumo","role":"agent","kind":"post","text":"What I'd change","at":"2026-11-21T16:10:00.000Z"}}"#
                        .utf8)))
        conversation.send("u1", text: text)
        conversation.send("u2", text: decision.message(saying: "Skip"))
        let undo = YourTap.decision(.init(message: "m_kumo", item: "thanks", choice: .undo))
        conversation.send("u3", text: undo.message(saying: "Undo · Draft a thank-you"))
        let decisions = conversation.decisions(on: "m_kumo")
        #expect(decisions["hold-cto"]?.choice == .accept && decisions["hold-cto"]?.sent == "u2")
        #expect(decisions["thanks"]?.choice == .undo)
        #expect(conversation.isWorking(on: "u1"), "not yet on the server")
    }

    @Test("Kumo's file cards and proposed changes read as shapes")
    func shapes() {
        let file = ReplyShape(language: "ari:file", json: #"{"file":"sf_cv","version":2}"#)
        guard case .file(let card)?? = file else {
            Issue.record("didn't read the file card")
            return
        }
        #expect(card.file == "sf_cv" && card.version == 2)
        let proposals = ReplyShape(
            language: "ari:proposals",
            json:
                #"{"title":"What I'd change","items":[{"id":"hold-cto","kind":"calendar","title":"Hold Thursday 15:00","verb":"Add","done":"Added to your calendar"}]}"#
        )
        guard case .proposals(let read)?? = proposals else {
            Issue.record("didn't read")
            return
        }
        #expect(
            read.items.first?.verb == "Add" && read.items.first?.done == "Added to your calendar")
        #expect(ReplyShape(language: "ari:proposals", json: #"{"items":[{"id":"x"}]}"#) == nil)
    }

    @Test("a quoted moment opens the transcript there")
    func moments() throws {
        let url = try #require(URL(string: "recording:\(id)?t=18:42"))
        let link = try #require(RecordingLink.read(url))
        #expect(link.recording == id && link.seconds == 1122)
        #expect(RecordingLink.seconds("1:02:03") == 3723 && RecordingLink.seconds("95") == 95)
        #expect(RecordingLink.seconds("a:b") == nil)
        #expect(RecordingLink.clock(1122) == "18:42" && RecordingLink.clock(3723) == "1:02:03")
        #expect(RecordingLink.first(in: "Landed. [18:42](recording:\(id)?t=18:42) And") == id)
        #expect(RecordingLink.first(in: "No moments here") == nil)
        let web = try #require(URL(string: "https://example.com"))
        #expect(RecordingLink.read(web) == nil)
    }
}
