import AriKit
import Foundation

/// A transcript's server behind the transport seam. It records every request Ari makes and holds
/// it until the test answers; it writes events into the open stream; and it can drop off the
/// network or become unreachable, as the transcript's world markers say.
actor ScriptedServer: Transport {
    private var made: [HTTPRequest] = []
    private var unanswered: [(request: HTTPRequest, reply: CheckedContinuation<Reply, any Error>)] =
        []
    private var stream: AsyncThrowingStream<Data, any Error>.Continuation?
    private var online = true
    private var reachable = true
    /// Requests that failed because the server was unreachable, such as while it restarted.
    private(set) var refused: [HTTPRequest] = []

    enum Reply: Sendable {
        case response(HTTPResponse)
        case stream(HTTPStream)
    }

    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        guard case .response(let response) = try await arrive(request) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
        guard case .stream(let stream) = try await arrive(request) else {
            throw URLError(.badServerResponse)
        }
        return stream
    }

    private func arrive(_ request: HTTPRequest) async throws -> Reply {
        guard online else { throw URLError(.notConnectedToInternet) }
        guard reachable else {
            refused.append(request)
            throw URLError(.cannotConnectToHost)
        }
        made.append(request)
        return try await withCheckedThrowingContinuation { unanswered.append((request, $0)) }
    }

    // MARK: - The test's side

    /// The oldest request Ari made that the test hasn't looked at yet.
    func takeRequest() -> HTTPRequest? {
        made.isEmpty ? nil : made.removeFirst()
    }

    /// Whether the event stream is open.
    var isStreaming: Bool { stream != nil }

    /// Answers the oldest unanswered request, as the transcript's `server` line says.
    func answer(_ response: Transcript.Response) throws {
        guard !unanswered.isEmpty else {
            throw TranscriptError("nothing to answer with \(response.status)")
        }
        let (request, reply) = unanswered.removeFirst()
        if response.lost {
            reply.resume(throwing: URLError(.networkConnectionLost))
            return
        }
        // An attachment's bytes come with only their length: any bytes of that length do.
        let bytes = response.headers["Content-Length"].flatMap { Int($0) }.map { Data(count: $0) }
        let body = try response.body.map { try JSONEncoder().encode($0) } ?? bytes ?? Data()
        guard request.path.hasPrefix("/v0/events") else {
            reply.resume(
                returning: .response(
                    HTTPResponse(status: response.status, headers: response.headers, body: body)))
            return
        }
        let (events, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        if response.status == 200 {
            stream?.finish()
            stream = continuation
        } else {
            continuation.yield(body)
            continuation.finish()
        }
        reply.resume(
            returning: .stream(
                HTTPStream(status: response.status, headers: response.headers, body: events)))
    }

    /// Answers the oldest unanswered request with `status` and a JSON body.
    func answer(_ status: Int, headers: [String: String] = [:], json: String? = nil) throws {
        try answer(
            Transcript.Response(
                line: 0, at: 0, status: status, headers: headers,
                body: try json.map { try JSONValue(json: $0) }, lost: false))
    }

    /// Writes an event, given as JSON, into the open stream.
    func push(json: String) throws {
        let value = try JSONValue(json: json)
        try push(Transcript.LoggedEvent(line: 0, json: value, event: try value.decode(Event.self)))
    }

    /// Writes an event into the open stream, as the server's Server-Sent Events.
    func push(_ logged: Transcript.LoggedEvent) throws {
        guard let stream else {
            throw TranscriptError("no open stream for \(logged.event.type)")
        }
        let json = String(decoding: try JSONEncoder().encode(logged.json), as: UTF8.self)
        let id = logged.event.id?.rawValue ?? ""
        stream.yield(Data("id: \(id)\nevent: \(logged.event.type)\ndata: \(json)\n\n".utf8))
    }

    /// Sends the keep-alive comment the server sends at least every 15 seconds.
    func ping() {
        stream?.yield(Data(": ping\n\n".utf8))
    }

    /// The network drops (`false`) or returns. A drop breaks the stream and fails every request.
    func setOnline(_ online: Bool) {
        self.online = online
        if !online { breakStream(.notConnectedToInternet) }
    }

    /// The server stops answering (`false`), as while it restarts, or answers again.
    func setReachable(_ reachable: Bool) {
        self.reachable = reachable
        if !reachable { breakStream(.networkConnectionLost) }
    }

    /// The open stream breaks, though the server can still be reached.
    func dropStream() {
        breakStream(.networkConnectionLost)
    }

    /// Ari closed its end, as when it leaves the screen.
    func closeStream() {
        stream?.finish()
        stream = nil
    }

    private func breakStream(_ code: URLError.Code) {
        stream?.finish(throwing: URLError(code))
        stream = nil
    }
}
