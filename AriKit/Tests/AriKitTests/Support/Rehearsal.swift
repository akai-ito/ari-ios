import AriKit
import Clocks
import Foundation
import Testing

/// Plays a golden transcript through a real ``Session``. The transcript's server sits behind the
/// transport seam, its world markers drive the network and the screen, and a test clock stands in
/// for time. Each `app` line is either something you do (send, Stop, Try again, scrolling back),
/// which the rehearsal does at that moment, or something Ari must do by itself (connect, reconnect,
/// send again), which it waits for. Either way, Ari's request must match the line.
@MainActor
final class Rehearsal {
    let transcript: Transcript
    let clock = TestClock<Duration>()
    let server = ScriptedServer()
    let network = FakeNetwork()
    let session: Session
    let outboxDirectory: URL
    private var elapsed = Duration.zero
    private var sinceLastPing = Duration.zero
    private var sent: Set<MessageID> = []
    private var early: [(at: Int, id: MessageID, text: String)]
    private var restarting = false
    /// Whether Ari is closed, so a message sent now was answered from a notification.
    private var closed = false

    static let token = Token("ito_example_not_a_real_token_00000000000000000000")

    /// - Parameters:
    ///   - sending: Messages you send earlier than their requests, such as while offline: each
    ///     message's id in the transcript, and when you tap Send.
    ///   - outboxDirectory: Another rehearsal's outbox, as after Ari restarts; a new one if `nil`.
    init(
        _ transcript: Transcript, sending: [(id: String, at: Int)] = [],
        outboxDirectory: URL? = nil
    ) throws {
        self.transcript = transcript
        self.outboxDirectory =
            outboxDirectory
            ?? FileManager.default.temporaryDirectory
            .appending(path: "AriKitTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        let texts = Dictionary(
            transcript.steps.compactMap { step -> (String, String)? in
                guard case .app(let request) = step, request.route == .send,
                    let id = request.body?["id"]?.string, let text = request.body?["text"]?.string
                else { return nil }
                return (id, text)
            }, uniquingKeysWith: { first, _ in first })
        early = try sending.map { send in
            guard let text = texts[send.id] else {
                throw TranscriptError("\(transcript.name) never sends \(send.id)")
            }
            return (send.at, MessageID(send.id), text)
        }
        session = Session(
            connection: try Self.connection(), conversation: Replay(transcript).conversation,
            outbox: OutboxStore(directory: self.outboxDirectory),
            cache: AttachmentCache(directory: self.outboxDirectory.appending(path: "cache")),
            transport: server,
            network: network,
            clock: clock)
    }

    static func connection() throws -> Connection {
        let server = try JSONValue(
            json: #"{"name":"studio","version":"0.4.0","protocol":"0.4","agent":{"name":"Ari"}}"#
        ).decode(ServerInfo.self)
        return Connection(
            address: try ServerAddress("https://studio.example"), token: token, server: server)
    }

    /// Plays every step, then lets Ari settle.
    func play() async throws {
        session.start()
        await settle()
        for step in transcript.steps {
            try await sendEarly(upTo: step.at)
            await advance(to: step.at)
            do {
                try await perform(step)
            } catch {
                throw TranscriptError(
                    "\(transcript.name).jsonl line \(step.line) (\(step.summary)): \(error)")
            }
        }
        await settle()
    }

    /// Ends the session and removes its outbox.
    func close() {
        session.close()
        try? FileManager.default.removeItem(at: outboxDirectory)
    }

    private func perform(_ step: Transcript.Step) async throws {
        switch step {
        case .app(let request):
            act(on: request)
            if restarting, request.route == .events {
                restarting = false
                await server.setReachable(true)
            }
            try check(try await nextRequest(), against: request)
        case .server(let response):
            try await server.answer(response)
            await settle()
        case .event(let logged):
            try await server.push(logged)
            await settle()
        case .push:
            // A notification reaches the phone's notification extension, not the session.
            break
        case .world(let world):
            switch world.marker {
            case "offline":
                network.set(false)
                await settle()
                await server.setOnline(false)
            case "online":
                await server.setOnline(true)
                network.set(true)
            case "app_closed":
                session.pause()
                closed = true
                await server.closeStream()
            case "app_opened":
                closed = false
                session.start()
            case "server_restarted", "server_restored":
                restarting = true
                await server.setReachable(false)
            default:
                // Scrolling up, a stall released at once, the engine compacting or stalling:
                // nothing Ari sends changes.
                break
            }
            await settle()
        }
    }

    /// Does what you did, where the line is something you do.
    private func act(on request: Transcript.Request) {
        switch request.route {
        case .send:
            guard let id = request.body?["id"]?.string, let text = request.body?["text"]?.string,
                !sent.contains(MessageID(id))
            else { return }
            sent.insert(MessageID(id))
            let answers = request.body?["answers"]?.string.map(AskID.init(rawValue:))
            if closed {
                // Answered from a notification, with Ari closed.
                let session = session
                Task {
                    await session.sendFromNotification(text, id: MessageID(id), answers: answers)
                }
                return
            }
            let secret = answers.flatMap { session.conversation[ask: $0]?.secret } ?? false
            let attachments = request.body?["attachments"]?.array?.compactMap(\.string)
                .map(AttachmentID.init(rawValue:))
            session.send(
                text, id: MessageID(id), answers: answers, secret: secret,
                attachments: attachments ?? [])
        case .upload(let attachment, let name):
            // Attaching it; uploading it again, after a lost answer, is Ari's own doing.
            guard let bytes = try? request.uploadBytes() else { return }
            session.attach(
                PendingAttachment(
                    id: attachment, name: name, mediaType: request.headers["Content-Type"] ?? "",
                    bytes: bytes))
        case .attachment(let attachment):
            // The photo comes into view.
            let session = session
            Task { _ = await session.bytes(of: attachment) }
        case .cancelAsk(let ask):
            session.cancel(ask)
        case .device:
            let device = String(request.path.split(separator: "/").last ?? "")
            if request.method == "DELETE" {
                session.unregister(device: device)
            } else if let registration = try? request.body?.decode(RegisterDevice.self) {
                session.register(device: device, registration)
            }
        case .presence:
            let device = String(request.path.split(separator: "/").dropLast().last ?? "")
            if let presence = try? request.body?.decode(Presence.self) {
                session.setLooking(presence.looking, device: device)
            }
        case .stop:
            let cut = try? request.body?["cut"]?.decode(Cut.self)
            session.stop(cut: cut)
        case .retry(let turn):
            session.tryAgain(turn)
        case .earlierMessages(_, let limit):
            let session = session
            Task { await session.loadEarlier(limit: limit ?? 50) }
        default:
            break
        }
    }

    private func sendEarly(upTo milliseconds: Int) async throws {
        while let send = early.first, send.at <= milliseconds {
            early.removeFirst()
            await advance(to: send.at)
            sent.insert(send.id)
            session.send(send.text, id: send.id)
            await settle()
        }
    }

    /// The next request Ari makes, letting the clock run (for a backoff, say) for up to a minute.
    func nextRequest() async throws -> HTTPRequest {
        for _ in 0..<600 {
            await settle()
            if let request = await server.takeRequest() { return request }
            await tick(.milliseconds(100))
        }
        throw TranscriptError("Ari made no request within a minute")
    }

    private func check(_ made: HTTPRequest, against expected: Transcript.Request) throws {
        let summary = "\(made.method.rawValue) \(made.path)"
        guard made.method.rawValue == expected.method, made.path == expected.path else {
            throw TranscriptError("Ari sent \(summary), not \(expected.method) \(expected.path)")
        }
        guard made.headers["Last-Event-ID"] == expected.headers["Last-Event-ID"] else {
            throw TranscriptError(
                "\(summary) resumed after \(made.headers["Last-Event-ID"] ?? "nothing"), not "
                    + (expected.headers["Last-Event-ID"] ?? "nothing"))
        }
        guard made.headers["Authorization"] == "Bearer \(Self.token.secret)" else {
            throw TranscriptError("\(summary) didn't carry the token")
        }
        if let bytes = try expected.uploadBytes() {
            guard made.body == bytes,
                made.headers["Content-Type"] == expected.headers["Content-Type"]
            else {
                throw TranscriptError("\(summary) uploaded different bytes, or another type")
            }
            return
        }
        let body = try made.body.map { try JSONValue(data: $0) }
        guard body == expected.body || (body == .object([:]) && expected.body == nil) else {
            throw TranscriptError("\(summary) sent a different body")
        }
    }

    /// Moves the clock to `milliseconds` since the start, sending the server's pings on the way.
    func advance(to milliseconds: Int) async {
        let target = Duration.milliseconds(milliseconds)
        while elapsed < target {
            await tick(min(target - elapsed, .seconds(15)))
        }
    }

    func tick(_ duration: Duration) async {
        await clock.advance(by: duration)
        elapsed += duration
        sinceLastPing += duration
        if sinceLastPing >= .seconds(15) {
            sinceLastPing = .zero
            await server.ping()
        }
        await settle()
    }

    /// Lets every task that can run, run: the session's lanes, and hops to the server's actor.
    func settle() async {
        for _ in 0..<4 {
            for _ in 0..<10 { await Task.yield() }
            _ = await server.isStreaming
        }
    }
}
