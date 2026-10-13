import AriKit
import Foundation
import Testing

/// Level 3: the client against a running server, `ito serve --engine demo` from an ito-core
/// clone. Skipped unless `ITO_SERVER` (such as `http://127.0.0.1:8787`) and `ITO_TOKEN` are set,
/// so CI runs only the deterministic levels. The demo engine answers any message; one containing
/// "long" gives a long reply to stop, and one containing "fail" fails. They share the server's one
/// conversation, so they run one at a time.
@MainActor
@Suite("Against a running server", .enabled(if: LiveServer.isConfigured), .serialized)
struct LiveServerTests {
    @Test("connects, sends, and the reply streams to its end")
    func sendAndReply() async throws {
        let live = try await LiveServer()
        defer { live.close() }
        let id = try #require(live.session.send("Hello from Ari's tests"))
        let reply = try await live.until("a reply ends") { conversation in
            LiveServer.reply(to: id, in: conversation).flatMap { $0.outcome == nil ? nil : $0 }
        }
        #expect(live.session.conversation[id]?.delivery == .delivered)
        #expect(reply.outcome == .completed)
        #expect(!reply.text.isEmpty)
    }

    @Test("Stop cuts a long reply where it was on screen")
    func stop() async throws {
        let live = try await LiveServer()
        defer { live.close() }
        let id = try #require(live.session.send("Write something long, please"))
        let writing = try await live.until("a long reply is under way") { conversation in
            LiveServer.reply(to: id, in: conversation).flatMap { $0.length >= 40 ? $0 : nil }
        }
        live.session.stop(cut: Cut(message: writing.id, offset: 40))
        let stopped = try await live.until("the reply stops") { conversation in
            conversation[writing.id].flatMap { $0.outcome == nil ? nil : $0 }
        }
        #expect(stopped.outcome == .stopped)
        #expect(stopped.length == 40)
    }

    @Test("a failed turn can be tried again")
    func tryAgain() async throws {
        let live = try await LiveServer()
        defer { live.close() }
        live.session.send("Please fail")
        let failed = try await live.until("the turn fails") { conversation in
            conversation.lastEndedTurn.flatMap { $0.outcome == .failed ? $0 : nil }
        }
        live.session.tryAgain(failed.id)
        // The demo engine fails the new attempt too, at once, so look for any trace of it.
        let attempt = try await live.until("a new attempt") { conversation in
            conversation.turn?.retryOf == failed.id
                ? conversation.turn?.id
                : conversation.lastEndedTurn.flatMap { $0.id == failed.id ? nil : $0.id }
        }
        #expect(attempt != failed.id)
        #expect(live.session.conversation.retriedTurns.contains(failed.id))
    }
}

@MainActor
final class LiveServer {
    nonisolated static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["ITO_SERVER"] != nil
            && ProcessInfo.processInfo.environment["ITO_TOKEN"] != nil
    }

    let session: Session
    private let outbox: URL

    init() async throws {
        let environment = ProcessInfo.processInfo.environment
        let connection = try await Connector().connect(
            to: environment["ITO_SERVER"] ?? "", token: Token(environment["ITO_TOKEN"] ?? ""))
        outbox = FileManager.default.temporaryDirectory
            .appending(path: "AriKitLiveTests/\(UUID().uuidString)")
        session = Session(connection: connection, outbox: OutboxStore(directory: outbox))
        session.start()
        // A turn left running by an earlier test would take this test's message in as Read
        // rather than answer it: wait until the server is idle.
        _ = try await until("the stream to open") { _ in session.link == .live ? true : nil }
        try await Task.sleep(for: .milliseconds(500))
        _ = try await until("the server to be idle") { $0.turn == nil ? true : nil }
    }

    /// The agent's reply to your message `id`: the first reply after it.
    static func reply(to id: MessageID, in conversation: Conversation) -> Conversation.Entry? {
        guard let index = conversation.entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return conversation.entries[(index + 1)...].first { $0.role == .agent && $0.kind == .reply }
    }

    /// Waits up to 30 seconds for `found` to find something in the conversation.
    func until<Found>(
        _ what: String, _ found: (Conversation) -> Found?
    ) async throws -> Found {
        for _ in 0..<600 {
            if let result = found(session.conversation) { return result }
            try await Task.sleep(for: .milliseconds(50))
        }
        let recent = session.conversation.entries.suffix(4).map { entry in
            "\(entry.role) \(entry.kind.map(\.rawValue) ?? "-") \(entry.outcome.map(\.rawValue) ?? "open")"
                + " \(entry.length) \(entry.id)"
        }
        throw TranscriptError(
            "waited 30 seconds for \(what); link \(session.link), turn \(String(describing: session.conversation.turn?.id)), last entries: \(recent)"
        )
    }

    func close() {
        session.close()
        try? FileManager.default.removeItem(at: outbox)
    }
}
