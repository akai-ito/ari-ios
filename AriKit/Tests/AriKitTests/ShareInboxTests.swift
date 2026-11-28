import AriKit
import Foundation
import Testing

/// The share sheet's way to the share inbox (protocol 0.20): photos first, then the share under the
/// one id it keeps, then Kumo's answer, followed for as long as the sheet waits. Each runs the real
/// client against the scripted server.
@Suite("Sharing to the share inbox")
struct ShareInboxTests {
    private let photo = PendingAttachment(
        id: "00000000-0000-4000-8000-0000000000b1", name: "screenshot.jpg",
        mediaType: "image/jpeg", bytes: Data(count: 2048))
    private let share = SendShare(
        id: "0f9b4c2e-6a71-4d3b-8e25-9c1a7d4e3b60",
        url: "https://fernway.example/trail-3", note: "Are these the ones Leo meant? I'm a 10.")

    private func outbox() -> (ShareOutbox, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AriKitTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        return (ShareOutbox(directory: directory), directory)
    }

    private func client(_ server: ScriptedServer) throws -> ItoClient {
        ItoClient(
            address: try ServerAddress("https://studio.example"),
            token: Token("ito_example_not_a_real_token_00000000000000000000"), transport: server)
    }

    private func request(from server: ScriptedServer) async throws -> HTTPRequest {
        for _ in 0..<500 {
            if let request = await server.takeRequest() { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TranscriptError("no request within 5 seconds")
    }

    private static func status(_ state: String, thread: String? = nil) -> String {
        let thread = thread.map { #","thread":"\#($0)""# } ?? ""
        return
            #"{"share":{"id":"0f9b4c2e-6a71-4d3b-8e25-9c1a7d4e3b60","state":"\#(state)","at":"2026-11-27T18:05:00.000Z"\#(thread)}}"#
    }

    @Test("a share sends only what it has: the link in url, the thought in note")
    func body() throws {
        #expect(
            try JSONValue(encoding: share)
                == JSONValue(
                    json: #"""
                        { "id": "0f9b4c2e-6a71-4d3b-8e25-9c1a7d4e3b60",
                          "url": "https://fernway.example/trail-3",
                          "note": "Are these the ones Leo meant? I'm a 10." }
                        """#))
        // Blank words aren't words: the server refuses them.
        let blank = SendShare(id: "s", text: "  \n", note: "")
        #expect(blank.isEmpty)
        #expect(try JSONValue(encoding: blank) == JSONValue(json: #"{ "id": "s" }"#))
    }

    @Test("photos go first, then the share, which leaves nothing behind")
    func delivers() async throws {
        let (outbox, directory) = outbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        let withPhoto = SendShare(id: share.id, note: "This one", attachments: [photo.id])
        try outbox.add(photo)
        try outbox.add(withPhoto)
        let server = ScriptedServer()
        let delivering = Task { [client = try client(server)] in
            await ShareDelivery.deliver(outbox, with: client)
        }

        let upload = try await request(from: server)
        #expect(upload.method == .put)
        #expect(upload.path == "/v0/attachments/\(photo.id)?name=screenshot.jpg")
        try await server.answer(
            201,
            json:
                #"{"attachment":{"id":"\#(photo.id)","kind":"image","name":"screenshot.jpg","media_type":"image/jpeg","size":2048}}"#
        )
        let post = try await request(from: server)
        #expect(post.method == .post && post.path == "/v0/shares")
        #expect(
            try JSONValue(data: #require(post.body))
                == JSONValue(
                    json:
                        #"{"id":"\#(share.id)","note":"This one","attachments":["\#(photo.id)"]}"#))
        try await server.answer(201, json: Self.status("sorting"))

        let report = await delivering.value
        #expect(report.accepted[share.id]?.state == .sorting)
        #expect(report.waiting == nil && report.refused.isEmpty)
        #expect(outbox.isEmpty)
    }

    @Test("a share that can't go now keeps its id, and goes again unchanged")
    func retries() async throws {
        let (outbox, directory) = outbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        try outbox.add(share)
        let server = ScriptedServer()
        await server.setOnline(false)
        let offline = await ShareDelivery.deliver(outbox, with: try client(server))
        #expect(offline.waiting == .network(.notConnectedToInternet))
        #expect(outbox.load() == [share])

        await server.setOnline(true)
        let delivering = Task { [client = try client(server)] in
            await ShareDelivery.deliver(outbox, with: client)
        }
        let post = try await request(from: server)
        #expect(try JSONValue(data: #require(post.body)) == JSONValue(encoding: share))
        // Already accepted on an attempt whose answer was lost: where it stands, and nothing new.
        try await server.answer(200, json: Self.status("placed", thread: "h_1"))
        #expect(await delivering.value.accepted[share.id]?.thread == "h_1")
        #expect(outbox.isEmpty)
    }

    @Test("a share the server refuses outright is dropped, so it can't block the ones behind it")
    func refused() async throws {
        let (outbox, directory) = outbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        let next = SendShare(id: "1d2c3b4a-0000-4000-8000-000000000002", note: "A quick thought")
        try outbox.add(share)
        try outbox.add(next)
        let server = ScriptedServer()
        let delivering = Task { [client = try client(server)] in
            await ShareDelivery.deliver(outbox, with: client)
        }
        _ = try await request(from: server)
        try await server.answer(
            409,
            json:
                #"{"error":{"code":"id_conflict","message":"That id belongs to a different share."}}"#
        )
        let second = try await request(from: server)
        #expect(try JSONValue(data: #require(second.body)) == JSONValue(encoding: next))
        try await server.answer(201, json: Self.status("sorting"))

        let report = await delivering.value
        #expect(report.refused[share.id]?.status == 409)
        #expect(report.accepted.keys.contains(next.id))
        #expect(outbox.isEmpty)
    }

    @Test("a box too old for the share inbox keeps the share waiting, not lost")
    func oldBox() async throws {
        let (outbox, directory) = outbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        try outbox.add(share)
        let server = ScriptedServer()
        let delivering = Task { [client = try client(server)] in
            await ShareDelivery.deliver(outbox, with: client)
        }
        _ = try await request(from: server)
        try await server.answer(404)
        #expect(await delivering.value.waiting?.status == 404)
        #expect(outbox.load() == [share])
    }

    @Test("the sheet follows the share to its thread, then to Kumo's finished reply")
    func followsTheReply() async throws {
        let server = ScriptedServer()
        let client = try client(server)
        let accepted = try JSONDecoder().decode(
            ShareStatusBox.self, from: Data(Self.status("sorting").utf8)
        ).share
        let following = Task { [share] in
            await ShareReply.follow(share, accepted: accepted, with: client, sleep: { _ in })
        }

        // Still sorting, then placed.
        let first = try await request(from: server)
        #expect(first.method == .post && first.path == "/v0/shares")
        #expect(try JSONValue(data: #require(first.body)) == JSONValue(encoding: share))
        try await server.answer(200, json: Self.status("sorting"))
        _ = try await request(from: server)
        try await server.answer(200, json: Self.status("placed", thread: "h_shoes"))

        // In the thread, Kumo is still writing; then it has finished.
        let open = try await request(from: server)
        #expect(open.method == .get && open.path == "/v0/threads/h_shoes")
        try await server.answer(200, json: Self.page(reply: "Yes, the same", ended: false))
        _ = try await request(from: server)
        try await server.answer(
            200,
            json: Self.page(
                reply:
                    "Yes, the same ones. They're **£23 less** than when Leo looked.\\n\\nI've noted your size.",
                ended: true))

        let reply = await following.value
        #expect(reply?.thread == "h_shoes" && reply?.title == "Shoes")
        #expect(reply?.text == "Yes, the same ones. They're **£23 less** than when Leo looked.")
    }

    @Test("a reply slower than the sheet waits leaves the thread alone, for the notification")
    func handsOff() async throws {
        let server = ScriptedServer()
        let client = try client(server)
        let accepted = try JSONDecoder().decode(
            ShareStatusBox.self, from: Data(Self.status("placed", thread: "h_shoes").utf8)
        ).share
        let following = Task { [share] in
            await ShareReply.follow(
                share, accepted: accepted, with: client, looks: 2, sleep: { _ in })
        }
        for _ in 0..<2 {
            let open = try await request(from: server)
            #expect(open.path == "/v0/threads/h_shoes")
            try await server.answer(200, json: Self.page(reply: nil, ended: false))
        }
        let reply = await following.value
        #expect(reply == ShareReply(thread: "h_shoes", title: "Shoes", text: nil))
    }

    @Test("a shared message carries its link and text, and its line says what was shared")
    func sharedMessage() throws {
        let message = try JSONDecoder().decode(
            Message.self,
            from: Data(
                #"""
                { "id": "0f9b4c2e-6a71-4d3b-8e25-9c1a7d4e3b60", "role": "user", "text": "",
                  "at": "2026-11-27T18:05:01.000Z", "position": 12, "thread": "h_shoes",
                  "share": { "link": { "url": "https://www.fernway.example/trail-3",
                    "title": "Trail 3 · Running shoe", "site": "Fernway" },
                    "text": "Light, grippy, and true to size." } }
                """#.utf8))
        #expect(message.share?.link?.title == "Trail 3 · Running shoe")
        #expect(message.share?.link?.host == "fernway.example")
        #expect(message.share?.text == "Light, grippy, and true to size.")
        #expect(Conversation.Entry(message).share == message.share)
        #expect(Conversation.Entry(message).line == "Trail 3 · Running shoe")

        // A photo shared with nothing else: an empty share, marked as shared.
        let photoOnly = try JSONDecoder().decode(
            Message.self,
            from: Data(
                #"{ "id": "m", "role": "user", "text": "", "at": "2026-11-27T18:05:01.000Z", "share": {} }"#
                    .utf8))
        #expect(photoOnly.share == Shared())
    }

    @Test("Open the thread links to ito://thread/<id>, and only that opens a thread")
    func threadLink() throws {
        let url = try #require(ThreadLink.url(for: "h_shoes"))
        #expect(url.absoluteString == "ito://thread/h_shoes")
        #expect(ThreadLink.thread(from: url) == "h_shoes")
        #expect(ThreadLink.thread(from: try #require(URL(string: "ito://pair?code=x"))) == nil)
        #expect(ThreadLink.thread(from: try #require(URL(string: "ito://thread/"))) == nil)
    }

    /// A thread page: the shared message, then Kumo's reply once it has begun.
    private static func page(reply: String?, ended: Bool) -> String {
        let user =
            #"{"id":"0f9b4c2e-6a71-4d3b-8e25-9c1a7d4e3b60","role":"user","text":"Are these the ones Leo meant? I'm a 10.","at":"2026-11-27T18:05:01.000Z","position":12,"thread":"h_shoes","share":{"link":{"url":"https://fernway.example/trail-3"}}}"#
        let ending = ended ? #","outcome":"completed","ended_at":"2026-11-27T18:05:09.000Z""# : ""
        let answer = reply.map {
            #",{"id":"m_2","role":"agent","kind":"reply","turn":"t_1","text":"\#($0)","at":"2026-11-27T18:05:04.000Z","position":14,"thread":"h_shoes"\#(ending)}"#
        }
        return
            #"{"thread":{"id":"h_shoes","title":"Shoes","by":"kumo","state":"open","started_at":"2026-11-27T18:05:01.000Z","position":11,"replies":2,"last_at":"2026-11-27T18:05:04.000Z"},"messages":[\#(user)\#(answer ?? "")],"steps":[],"asks":[],"turn":null,"next":[],"has_more":false}"#
    }
}

/// `ShareResult` is the client's own; the tests read the same answer.
private struct ShareStatusBox: Decodable {
    let share: ShareStatus
}
