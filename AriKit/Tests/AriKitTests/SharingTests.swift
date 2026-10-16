import AriKit
import Foundation
import Testing

@Suite("Sharing to Ari")
struct SharingTests {
    private let photo = PendingAttachment(
        id: "00000000-0000-4000-8000-0000000000a1", name: "photo.jpg", mediaType: "image/jpeg",
        bytes: Data(count: 1454))
    private let message = SendMessage(
        id: "00000000-0000-4000-8000-000000000001", text: "https://example.com/route",
        attachments: ["00000000-0000-4000-8000-0000000000a1"])

    private func shares() -> (OutboxStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AriKitTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        return (OutboxStore(directory: directory), directory)
    }

    private func client(_ server: ScriptedServer) throws -> ItoClient {
        ItoClient(
            address: try ServerAddress("https://studio.example"),
            token: Token("ito_example_not_a_real_token_00000000000000000000"), transport: server)
    }

    @Test("a share goes photo first, then its message, and leaves nothing behind")
    func delivers() async throws {
        let (shares, directory) = shares()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shares.add(photo)
        try shares.add(message)
        let server = ScriptedServer()
        let delivering = Task { [client = try client(server)] in
            await ShareDelivery.deliver(shares, with: client)
        }

        let upload = try await request(from: server)
        #expect(upload.path == "/v0/attachments/\(photo.id)?name=photo.jpg")
        try await server.answer(
            201,
            json:
                #"{"attachment":{"id":"\#(photo.id)","kind":"image","name":"photo.jpg","media_type":"image/jpeg","size":1454}}"#
        )
        let send = try await request(from: server)
        #expect(send.path == "/v0/messages")
        try await server.answer(
            201,
            json:
                #"{"message":{"id":"\#(message.id)","role":"user","text":"\#(message.text)","at":"2026-10-12T08:41:02.055Z"}}"#
        )
        #expect(await delivering.value)
        #expect(shares.attachments().isEmpty)
        #expect(try shares.load().isEmpty)
    }

    @Test("a share that can't go yet stays, for Ari to send when it opens")
    func waits() async throws {
        let (shares, directory) = shares()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shares.add(photo)
        try shares.add(message)
        let server = ScriptedServer()
        await server.setOnline(false)
        #expect(await !ShareDelivery.deliver(shares, with: try client(server)))
        #expect(shares.attachments().map(\.id) == [photo.id])
        #expect(try shares.load().map(\.id) == [message.id])
    }

    @Test("the group is named after the app, from the app or its extensions")
    func group() {
        #expect(AppGroup.forThisApp().identifier.hasPrefix("group."))
    }

    private func request(from server: ScriptedServer) async throws -> HTTPRequest {
        // Real time, not yields: the delivery runs on its own task, under a busy parallel suite.
        for _ in 0..<500 {
            if let request = await server.takeRequest() { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TranscriptError("no request within 5 seconds")
    }
}
