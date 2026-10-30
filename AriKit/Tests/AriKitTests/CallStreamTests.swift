import AriKit
import Clocks
import Foundation
import Synchronization
import Testing

/// A call's stream: the frames as the contract writes them, and a connection that's kept for 20
/// seconds, then given up.
@MainActor
@Suite("A call's stream")
struct CallStreamTests {
    @Test("text frames read as the contract writes them; one Ari doesn't know is kept apart")
    func frames() {
        func event(_ json: String) -> CallStreamEvent { CallStreamEvent(json: Data(json.utf8)) }
        #expect(event(#"{"type":"state","state":"hearing"}"#) == .state(.hearing))
        #expect(event(#"{"type":"state","state":"turn_ended"}"#) == .state(.turnEnded))
        #expect(
            event(#"{"type":"heard","text":"What did Bora","final":false}"#)
                == .heard(text: "What did Bora", final: false, message: nil))
        #expect(
            event(#"{"type":"heard","text":"What did Bora say?","final":true,"message":"m1"}"#)
                == .heard(text: "What did Bora say?", final: true, message: "m1"))
        #expect(
            event(#"{"type":"saying","id":"s1","text":"She wants one more round."}"#)
                == .saying(id: "s1", text: "She wants one more round."))
        #expect(event(#"{"type":"stop_playback"}"#) == .stopPlayback)
        #expect(event(#"{"type":"said","id":"s3"}"#) == .said(id: "s3"))
        #expect(
            event(#"{"type":"problem","reason":"The connection dropped."}"#)
                == .problem(reason: "The connection dropped."))
        #expect(event(#"{"type":"confetti"}"#) == .unknown)
        #expect(event("not json") == .unknown)
    }

    @Test("Ari's frames encode as the contract reads them")
    func commands() throws {
        func object(_ command: CallStreamCommand) throws -> JSONValue {
            try JSONValue(data: command.json)
        }
        #expect(try object(.mute) == JSONValue(json: #"{"type":"mute"}"#))
        #expect(try object(.unmute) == JSONValue(json: #"{"type":"unmute"}"#))
        #expect(try object(.end) == JSONValue(json: #"{"type":"end"}"#))
        #expect(
            try object(.played(id: "s1")) == JSONValue(json: #"{"type":"played","id":"s1"}"#))
    }

    @Test("events arrive in order, your voice and commands go up, and a problem ends the call")
    func flow() async throws {
        let socket = FakeSocket()
        socket.script([
            .message(.text(Data(#"{"type":"state","state":"listening"}"#.utf8))),
            .message(.binary(Data([1, 2, 3, 4]))),
            .message(
                .text(
                    Data(#"{"type":"problem","reason":"Ari's voice stopped on your server."}"#.utf8)
                )),
        ])
        let stream = CallStream(connect: { socket })
        stream.start()
        var events: [CallStreamEvent] = []
        for await event in stream.events {
            events.append(event)
            if events.count == 1 {
                stream.send(audio: Data([9, 9]))
                stream.send(.mute)
            }
        }
        #expect(
            events == [
                .state(.listening), .audio(Data([1, 2, 3, 4])),
                .problem(reason: "Ari's voice stopped on your server."),
            ])
        #expect(stream.endReason == "Ari's voice stopped on your server.")
        try await Task.sleep(for: .milliseconds(50))
        #expect(socket.sent.contains(.binary(Data([9, 9]))))
        #expect(socket.sent.contains(.text(CallStreamCommand.mute.json)))
    }

    @Test("your voice goes up in the order it was spoken, however long each frame takes to send")
    func inOrder() async throws {
        let frames = (0..<40).map { Data([UInt8($0)]) }
        let socket = FakeSocket(slowSends: true)
        socket.script([
            .message(.text(Data(#"{"type":"state","state":"listening"}"#.utf8))),
            .awaitSent(frames.count),
        ])
        let stream = CallStream(connect: { socket })
        stream.start()
        for await event in stream.events where event == .state(.listening) {
            for frame in frames { stream.send(audio: frame) }
        }
        #expect(socket.sent == frames.map(WebSocketMessage.binary))
    }

    @Test("a dropped connection is tried again, and the call carries on")
    func reconnects() async throws {
        let first = FakeSocket()
        first.script([.closed(1006)])
        let second = FakeSocket()
        second.script([
            .message(.text(Data(#"{"type":"state","state":"working"}"#.utf8))), .closed(1000),
        ])
        let sockets = Mutex([first, second])
        let stream = CallStream(
            connect: { sockets.withLock { $0.removeFirst() } }, clock: ImmediateClock())
        stream.start()
        var events: [CallStreamEvent] = []
        for await event in stream.events { events.append(event) }
        #expect(events == [.state(.working)])
        #expect(stream.endReason == nil, "a normal close ends the call quietly")
    }

    @Test("past 20 seconds down, the call ends: the connection dropped")
    func givesUp() async throws {
        // The retries' waits pass at once; together they come to the 20 seconds.
        let stream = CallStream(
            connect: {
                let socket = FakeSocket()
                socket.script([.closed(1006)])
                return socket
            }, clock: ImmediateClock())
        stream.start()
        for await _ in stream.events {}
        #expect(stream.endReason == "The connection dropped.")
    }

    @Test("a refused stream says why, without retrying; another device taking over ends it here")
    func refused() async throws {
        let notReady = FakeSocket()
        notReady.script([.refused(503)])
        let stream = CallStream(connect: { notReady })
        stream.start()
        for await _ in stream.events {}
        #expect(stream.endReason == "Ari's voice isn't ready on your server.")

        let replaced = FakeSocket()
        replaced.script([.closed(4000)])
        let other = CallStream(connect: { replaced })
        other.start()
        for await _ in other.events {}
        #expect(other.endReason == "The call carried on on another device.")
    }
}

/// A socket that plays a script: messages, then how it closes.
final class FakeSocket: WebSocketChannel, @unchecked Sendable {
    enum Step {
        case message(WebSocketMessage)
        case closed(Int)
        case refused(Int)
        /// Stays open until Ari has sent this many frames.
        case awaitSent(Int)
    }

    private let steps = Mutex<[Step]>([])
    private let outbox = Mutex<[WebSocketMessage]>([])
    /// Each send takes its own while, as a real socket's may.
    private let slowSends: Bool

    init(slowSends: Bool = false) {
        self.slowSends = slowSends
    }

    var sent: [WebSocketMessage] { outbox.withLock { $0 } }

    func script(_ steps: [Step]) {
        self.steps.withLock { $0 = steps }
    }

    func send(_ message: WebSocketMessage) async throws {
        if slowSends { try await Task.sleep(for: .microseconds(Int.random(in: 0...3_000))) }
        outbox.withLock { $0.append(message) }
    }

    func receive() async throws -> WebSocketMessage {
        // A beat between frames, so what the stream sends in between can go.
        try await Task.sleep(for: .milliseconds(5))
        let step = steps.withLock { $0.isEmpty ? Step.closed(1000) : $0.removeFirst() }
        switch step {
        case .message(let message): return message
        case .closed(let code): throw WebSocketClosed(code: code)
        case .refused(let status): throw WebSocketRefused(status: status)
        case .awaitSent(let count):
            while sent.count < count { try await Task.sleep(for: .milliseconds(5)) }
            return try await receive()
        }
    }

    func close(code: Int) {}
}

/// Every frame on every call's stream in the transcripts, read and written as Ari does.
@Suite("A call's stream, in the transcripts")
struct CallStreamTranscriptTests {
    @Test(
        "the server's frames read as events Ari knows, and the app's are frames Ari sends",
        arguments: try Fixtures.transcripts().filter { transcript in
            transcript.steps.contains { if case .socket = $0 { true } else { false } }
        })
    func frames(_ transcript: Transcript) throws {
        for case .socket(let socket) in transcript.steps {
            guard let frame = socket.frame else { continue }
            let place = "\(transcript.name).jsonl line \(socket.line)"
            let json = try JSONEncoder().encode(frame)
            if socket.fromApp {
                let command = try #require(
                    Self.command(frame), "\(place): a frame Ari doesn't send")
                #expect(try JSONValue(data: command.json) == frame, "\(place)")
            } else {
                #expect(
                    CallStreamEvent(json: json) != .unknown, "\(place): a frame Ari doesn't read")
            }
        }
    }

    /// The command a transcript's app frame stands for.
    private static func command(_ frame: JSONValue) -> CallStreamCommand? {
        switch frame["type"]?.string {
        case "mute": .mute
        case "unmute": .unmute
        case "end": .end
        case "played":
            frame["id"]?.string.map { .played(id: $0) }
        default: nil
        }
    }
}
