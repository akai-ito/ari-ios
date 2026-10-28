import Foundation

/// Where a call is, as the server says on the call's stream.
public struct CallState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Your turn, and you're quiet.
    public static let listening = CallState(rawValue: "listening")
    /// You're speaking: the server hears a voice, before any words come through.
    public static let hearing = CallState(rawValue: "hearing")
    /// Your turn just ended: the chime.
    public static let turnEnded = CallState(rawValue: "turn_ended")
    /// Ari is on it, quietly.
    public static let working = CallState(rawValue: "working")
    public static let speaking = CallState(rawValue: "speaking")
    public static let known = [listening, hearing, turnEnded, working, speaking]
}

/// What arrives on a call's stream.
public enum CallStreamEvent: Sendable, Equatable {
    case state(CallState)
    /// Live captions of your turn; `final` carries the text as sent, and its message.
    case heard(text: String, final: Bool, message: MessageID?)
    /// The sentence Ari is about to speak, just before its audio.
    case saying(id: String, text: String)
    /// Ari's voice: 16-bit PCM, mono, 24 kHz, little-endian, to play in order.
    case audio(Data)
    /// Drop all queued audio now: you started talking.
    case stopPlayback
    /// The call can't go on; the server closes it with this reason.
    case problem(reason: String)
    /// A frame this version of Ari doesn't know.
    case unknown

    /// Reads a text frame.
    public init(json: Data) {
        guard let frame = try? JSONDecoder().decode(Frame.self, from: json) else {
            self = .unknown
            return
        }
        switch frame.type {
        case "state": self = frame.state.map { .state(CallState(rawValue: $0)) } ?? .unknown
        case "heard":
            self = .heard(
                text: frame.text ?? "", final: frame.final ?? false,
                message: frame.message.map(MessageID.init(rawValue:)))
        case "saying": self = .saying(id: frame.id ?? "", text: frame.text ?? "")
        case "stop_playback": self = .stopPlayback
        case "problem": self = .problem(reason: frame.reason ?? "The call ended.")
        default: self = .unknown
        }
    }

    private struct Frame: Decodable {
        let type: String
        let state: String?
        let text: String?
        let final: Bool?
        let message: String?
        let id: String?
        let reason: String?
    }
}

/// What Ari says on a call's stream, besides your voice.
public enum CallStreamCommand: Sendable, Equatable {
    case mute
    case unmute
    case end
    /// A sentence's audio finished playing, or was cut by `stopPlayback`.
    case played(id: String, cut: Bool)

    public var json: Data {
        let frame: [String: Any] =
            switch self {
            case .mute: ["type": "mute"]
            case .unmute: ["type": "unmute"]
            case .end: ["type": "end"]
            case .played(let id, let cut):
                cut ? ["type": "played", "id": id, "cut": true] : ["type": "played", "id": id]
            }
        return (try? JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys]))
            ?? Data()
    }
}

/// A WebSocket, as `CallStream` needs it: a seam so tests can stand in for the server.
public protocol WebSocketChannel: Sendable {
    func send(_ message: WebSocketMessage) async throws
    /// The next message; throws once the socket closes, with how.
    func receive() async throws -> WebSocketMessage
    func close(code: Int)
}

public enum WebSocketMessage: Sendable, Equatable {
    case text(Data)
    case binary(Data)
}

/// How the socket closed, when it did.
public struct WebSocketClosed: Error, Equatable {
    public let code: Int
    public init(code: Int) { self.code = code }

    /// Ended as asked: by `end`, or the server ending the call.
    public static let normal = 1000
    /// Another connection to the same call took over.
    public static let replaced = 4000
}

/// The server refused to open the stream, with its HTTP status.
public struct WebSocketRefused: Error, Equatable {
    public let status: Int
    public init(status: Int) { self.status = status }
}

/// One call's live connection to the server: your voice up, and Ari's voice, captions and the
/// call's state down. A dropped connection is retried for 20 seconds, as the server keeps the call
/// on that long; past that, or when the server says why it can't go on, the stream ends.
@MainActor
public final class CallStream {
    /// What arrives, in order, until the stream ends; then `endReason` says why.
    public let events: AsyncStream<CallStreamEvent>
    /// Why the stream ended: `nil` when you ended it.
    public private(set) var endReason: String?

    private let connect: @Sendable () -> any WebSocketChannel
    private let clock: any Clock<Duration>
    private let continuation: AsyncStream<CallStreamEvent>.Continuation
    private var channel: (any WebSocketChannel)?
    /// What goes up the connection, sent one at a time so it arrives in the order it went.
    private var outgoing: AsyncStream<WebSocketMessage>.Continuation?
    private var running: Task<Void, Never>?
    private var closing = false
    private var finished = false

    /// How long a dropped connection is retried, matching how long the server keeps the call.
    public static let reconnectWindow = Duration.seconds(20)

    /// - Parameter connect: Opens the socket, such as `client.callStream(_:)` does.
    public init(
        connect: @escaping @Sendable () -> any WebSocketChannel,
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.connect = connect
        self.clock = clock
        (events, continuation) = AsyncStream<CallStreamEvent>.makeStream()
    }

    public func start() {
        guard running == nil, !finished else { return }
        running = Task { await run() }
    }

    /// Your voice: 16-bit PCM, mono, 16 kHz, little-endian, in frames of 20–40 ms. Dropped while
    /// the connection is down, as the server would lose it anyway.
    public func send(audio: Data) {
        outgoing?.yield(.binary(audio))
    }

    public func send(_ command: CallStreamCommand) {
        outgoing?.yield(.text(command.json))
    }

    /// You ended the call: the server ends it, and closes the stream.
    public func end() {
        closing = true
        send(.end)
    }

    /// Stops at once, without telling the server.
    public func close() {
        closing = true
        channel?.close(code: WebSocketClosed.normal)
        running?.cancel()
        finish(nil)
    }

    private func run() async {
        /// How long the connection has been down, retrying.
        var down = Duration.zero
        var attempt = 0
        while !Task.isCancelled, !finished {
            let channel = connect()
            self.channel = channel
            // One sender for the connection: a frame goes once the one before it has.
            let (messages, outgoing) = AsyncStream<WebSocketMessage>.makeStream()
            self.outgoing = outgoing
            let sender = Task {
                for await message in messages { try? await channel.send(message) }
            }
            defer {
                outgoing.finish()
                sender.cancel()
            }
            do {
                while true {
                    let message = try await channel.receive()
                    down = .zero
                    attempt = 0
                    switch message {
                    case .binary(let audio): continuation.yield(.audio(audio))
                    case .text(let json):
                        let event = CallStreamEvent(json: json)
                        continuation.yield(event)
                        if case .problem(let reason) = event { return finish(reason) }
                    }
                }
            } catch let refused as WebSocketRefused {
                return finish(Self.reason(refused.status))
            } catch {
                self.channel = nil
                self.outgoing = nil
                let code = (error as? WebSocketClosed)?.code
                if closing || code == WebSocketClosed.normal { return finish(nil) }
                if code == WebSocketClosed.replaced {
                    return finish("The call carried on on another device.")
                }
                // Dropped: try again until the server would have ended the call.
                guard down < Self.reconnectWindow else { return finish("The connection dropped.") }
                attempt += 1
                let wait = Duration.milliseconds(min(250 * attempt, 2_000))
                try? await clock.sleep(for: wait)
                down += wait
            }
        }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 401: "Your server didn't accept Ari's token."
        case 404: "The call has ended."
        case 503: "Ari's voice isn't ready on your server."
        default: "Your server couldn't hold the call."
        }
    }

    private func finish(_ reason: String?) {
        guard !finished else { return }
        finished = true
        endReason = reason
        channel = nil
        outgoing = nil
        continuation.finish()
    }
}

/// The call's stream over `URLSessionWebSocketTask`.
public final class URLSessionWebSocketChannel: WebSocketChannel, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    public init(request: URLRequest, session: URLSession = .shared) {
        task = session.webSocketTask(with: request)
        task.resume()
    }

    public func send(_ message: WebSocketMessage) async throws {
        switch message {
        case .text(let data): try await task.send(.string(String(decoding: data, as: UTF8.self)))
        case .binary(let data): try await task.send(.data(data))
        }
    }

    public func receive() async throws -> WebSocketMessage {
        do {
            switch try await task.receive() {
            case .string(let text): return .text(Data(text.utf8))
            case .data(let data): return .binary(data)
            @unknown default: return .text(Data())
            }
        } catch {
            if let http = task.response as? HTTPURLResponse, http.statusCode != 101 {
                throw WebSocketRefused(status: http.statusCode)
            }
            let code = task.closeCode.rawValue
            throw code == 0 ? error : WebSocketClosed(code: code)
        }
    }

    public func close(code: Int) {
        task.cancel(
            with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
    }
}

extension ItoClient {
    /// `GET /v0/calls/{call}/stream`, upgraded to a WebSocket, with the token as for every route.
    public func callStream(_ call: CallID) -> URLSessionWebSocketChannel {
        var components = URLComponents(url: address.url, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/v0/calls/\(call.rawValue)/stream"
        var request = URLRequest(url: components.url!)
        if let token {
            request.setValue("Bearer \(token.secret)", forHTTPHeaderField: "Authorization")
        }
        return URLSessionWebSocketChannel(request: request)
    }
}
