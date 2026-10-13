import AriKit
import Foundation
import Testing

/// Level 3: the client against a running server, `ito serve --engine demo` from an ito-core
/// clone. Skipped unless `ITO_SERVER` (such as `http://127.0.0.1:8787`) and `ITO_TOKEN` are set,
/// so CI runs only the deterministic levels. The demo engine answers any message; one containing
/// "long" gives a long reply to stop, and one containing "fail" fails.
@MainActor
@Suite("Against a running server", .enabled(if: LiveServer.isConfigured))
struct LiveServerTests {
    @Test("connects, sends, and the reply streams to its end")
    func sendAndReply() async throws {
        let live = try await LiveServer()
        defer { live.close() }
        let id = try #require(live.session.send("Hello from Ari's tests"))
        let reply = try await live.until("a reply ends") { conversation in
            conversation.entries.last {
                $0.role == .agent && $0.kind == .reply && $0.outcome != nil
            }
        }
        #expect(live.session.conversation[id]?.delivery == .delivered)
        #expect(reply.outcome == .completed)
        #expect(!reply.text.isEmpty)
    }

    @Test("Stop cuts a long reply where it was on screen")
    func stop() async throws {
        let live = try await LiveServer()
        defer { live.close() }
        live.session.send("Write something long, please")
        let writing = try await live.until("a long reply is under way") { conversation in
            conversation.entries.last { $0.kind == .reply && $0.outcome == nil && $0.length >= 40 }
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
        let attempt = try await live.until("a new attempt starts") { conversation in
            conversation.turn.flatMap { $0.retryOf == failed.id ? $0 : nil }
        }
        #expect(attempt.id != failed.id)
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
    }

    /// Waits up to 30 seconds for `found` to find something in the conversation.
    func until<Found>(
        _ what: String, _ found: (Conversation) -> Found?
    ) async throws -> Found {
        for _ in 0..<600 {
            if let result = found(session.conversation) { return result }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TranscriptError("waited 30 seconds for \(what)")
    }

    func close() {
        session.close()
        try? FileManager.default.removeItem(at: outbox)
    }
}
