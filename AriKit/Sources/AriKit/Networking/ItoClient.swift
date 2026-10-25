import Foundation

/// The Ito API, one call per route. Every answer is checked for the protocol version, and every
/// refusal becomes a ``RequestError`` that says whether trying again is safe.
public struct ItoClient: Sendable, CustomStringConvertible {
    public let address: ServerAddress
    /// `nil` only for discovery, which is open.
    public let token: Token?
    let transport: any Transport

    public init(address: ServerAddress, token: Token?, transport: any Transport) {
        self.address = address
        self.token = token
        self.transport = transport
    }

    public var description: String { "ItoClient(\(address), token \(token?.lastFour ?? "none"))" }

    /// `GET /.well-known/ito`: the protocol versions the server speaks. Open, without a token.
    public func discover() async throws(RequestError) -> Discovery {
        try await call(HTTPRequest(.get, "/.well-known/ito"), authorized: false)
    }

    /// `GET /v0/server`: checks the token and says who answered.
    public func server() async throws(RequestError) -> ServerInfo {
        try await call(HTTPRequest(.get, "/v0/server"))
    }

    /// `POST /v0/messages`. Sending the same id again is always safe.
    public func send(_ message: SendMessage) async throws(RequestError) -> MessageResult {
        try await call(HTTPRequest(.post, "/v0/messages", body: try Self.json(message)))
    }

    /// `POST /v0/turns/{turn}/stop`.
    public func stop(_ turn: TurnID, cut: Cut?) async throws(RequestError) -> StopResult {
        let body = try Self.json(StopTurn(cut: cut))
        return try await call(
            HTTPRequest(.post, "/v0/turns/\(Self.segment(turn.rawValue))/stop", body: body))
    }

    /// `POST /v0/turns/{turn}/retry`: the failed turn's id is the retry key.
    public func retry(_ turn: TurnID) async throws(RequestError) -> RetryResult {
        try await call(HTTPRequest(.post, "/v0/turns/\(Self.segment(turn.rawValue))/retry"))
    }

    /// `POST /v0/asks/{ask}/cancel`: what Stop does while an ask waits. Repeating it is safe.
    public func cancelAsk(_ ask: AskID) async throws(RequestError) -> AskResult {
        try await call(HTTPRequest(.post, "/v0/asks/\(Self.segment(ask.rawValue))/cancel"))
    }

    /// `PUT /v0/attachments/{attachment}`: upload a photo or file's bytes. Repeating it with the
    /// same id and bytes is safe.
    public func upload(
        _ attachment: AttachmentID, name: String, mediaType: String, bytes: Data
    ) async throws(RequestError) -> AttachmentResult {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "name", value: name)]
        // A query's + reads as a space on the server, so it's sent encoded.
        let encoded = query.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let path =
            "/v0/attachments/\(Self.segment(attachment.rawValue))"
            + (encoded.map { "?" + $0 } ?? "")
        return try await call(
            HTTPRequest(.put, path, headers: ["Content-Type": mediaType], body: bytes),
            contentType: mediaType)
    }

    /// `GET /v0/attachments/{attachment}`: an attachment's bytes, which never change.
    public func attachmentBytes(_ attachment: AttachmentID) async throws(RequestError) -> Data {
        try await raw(HTTPRequest(.get, "/v0/attachments/\(Self.segment(attachment.rawValue))"))
    }

    /// `POST /v0/pair`, without a token: exchange the code `ito pair` showed for a token of this
    /// device's own.
    public func pair(_ request: PairDevice) async throws(RequestError) -> PairResult {
        try await call(
            HTTPRequest(.post, "/v0/pair", body: try Self.json(request)), authorized: false)
    }

    /// `PUT /v0/devices/{device}`: register this device for notifications, or register it again
    /// with a new push token or key. Repeating it is safe.
    public func registerDevice(_ device: String, _ registration: RegisterDevice)
        async throws(RequestError) -> DeviceResult
    {
        let body = try Self.json(registration)
        return try await call(
            HTTPRequest(.put, "/v0/devices/\(Self.segment(device))", body: body))
    }

    /// `DELETE /v0/devices/{device}`: stop notifying this device.
    public func removeDevice(_ device: String) async throws(RequestError) {
        try await callWithoutAnswer(HTTPRequest(.delete, "/v0/devices/\(Self.segment(device))"))
    }

    /// `PUT /v0/devices/{device}/presence`: whether the conversation is on screen here, so the
    /// server doesn't push what you're already watching.
    public func setPresence(_ device: String, looking: Bool) async throws(RequestError) {
        let body = try Self.json(Presence(looking: looking))
        try await callWithoutAnswer(
            HTTPRequest(.put, "/v0/devices/\(Self.segment(device))/presence", body: body))
    }

    /// `GET /v0/capabilities`: every capability, with its state and setup.
    public func capabilities() async throws(RequestError) -> CapabilityList {
        try await call(HTTPRequest(.get, "/v0/capabilities"))
    }

    /// `PUT /v0/capabilities/{id}`: switch a capability on or off. Off keeps its data.
    public func switchCapability(_ id: CapabilityID, on: Bool) async throws(RequestError)
        -> Capability
    {
        let body = try Self.json(SwitchCapability(on: on))
        return try await call(
            HTTPRequest(.put, "/v0/capabilities/\(Self.segment(id.rawValue))", body: body))
    }

    /// `PUT /v0/capabilities/{id}/setup`: save what setup asks for. A password left out keeps the
    /// one saved; one sent is never sent back.
    public func setUp(_ id: CapabilityID, values: [String: SetupValue]) async throws(RequestError)
        -> Capability
    {
        let body = try Self.json(CapabilitySetup(values: values))
        return try await call(
            HTTPRequest(.put, "/v0/capabilities/\(Self.segment(id.rawValue))/setup", body: body))
    }

    /// `POST /v0/capabilities/{id}/check`: *Test connection* with values not saved yet.
    public func check(_ id: CapabilityID, values: [String: SetupValue]) async throws(RequestError)
        -> CheckResult
    {
        let body = try Self.json(CapabilitySetup(values: values))
        return try await call(
            HTTPRequest(.post, "/v0/capabilities/\(Self.segment(id.rawValue))/check", body: body))
    }

    /// `GET /v0/messages?before=…&limit=…`: older messages, oldest first.
    public func messages(before oldest: MessageID, limit: Int) async throws(RequestError)
        -> MessagePage
    {
        var components = URLComponents()
        components.path = "/v0/messages"
        components.queryItems = [
            URLQueryItem(name: "before", value: oldest.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await call(HTTPRequest(.get, components.string ?? "/v0/messages"))
    }

    /// `GET /v0/events`, resuming after `cursor` or, without one, from a snapshot.
    public func events(after cursor: EventID?) async throws(RequestError) -> HTTPStream {
        var request = authorize(
            HTTPRequest(.get, "/v0/events", headers: ["Accept": "text/event-stream"]))
        if let cursor { request.headers["Last-Event-ID"] = cursor.rawValue }
        let stream: HTTPStream
        do {
            stream = try await transport.open(request, to: address.url)
        } catch {
            throw RequestError(error)
        }
        try Self.checkVersion(stream.headers)
        guard stream.status == 200 else {
            var body = Data()
            do {
                for try await chunk in stream.body {
                    body.append(chunk)
                    if body.count > 64 * 1024 { break }
                }
            } catch {}
            throw Self.refusal(
                HTTPResponse(status: stream.status, headers: stream.headers, body: body))
        }
        return stream
    }

    // MARK: - Plumbing

    private func call<Answer: Decodable>(
        _ request: HTTPRequest, authorized: Bool = true, contentType: String = "application/json"
    ) async throws(RequestError) -> Answer {
        var request = authorized ? authorize(request) : request
        if request.body != nil { request.headers["Content-Type"] = contentType }
        let response: HTTPResponse
        do {
            response = try await transport.send(request, to: address.url)
        } catch {
            throw RequestError(error)
        }
        try Self.checkVersion(response.headers)
        guard (200..<300).contains(response.status) else { throw Self.refusal(response) }
        do {
            return try JSONDecoder().decode(Answer.self, from: response.body)
        } catch {
            throw .unreadable(String(describing: error))
        }
    }

    /// A request whose answer is bytes, not JSON.
    private func raw(_ request: HTTPRequest) async throws(RequestError) -> Data {
        let request = authorize(request)
        let response: HTTPResponse
        do {
            response = try await transport.send(request, to: address.url)
        } catch {
            throw RequestError(error)
        }
        try Self.checkVersion(response.headers)
        guard (200..<300).contains(response.status) else { throw Self.refusal(response) }
        return response.body
    }

    /// A command whose answer has no body, such as a 204.
    private func callWithoutAnswer(_ request: HTTPRequest) async throws(RequestError) {
        var request = authorize(request)
        if request.body != nil { request.headers["Content-Type"] = "application/json" }
        let response: HTTPResponse
        do {
            response = try await transport.send(request, to: address.url)
        } catch {
            throw RequestError(error)
        }
        try Self.checkVersion(response.headers)
        guard (200..<300).contains(response.status) else { throw Self.refusal(response) }
    }

    private func authorize(_ request: HTTPRequest) -> HTTPRequest {
        var request = request
        if let token { request.headers["Authorization"] = "Bearer \(token.secret)" }
        return request
    }

    /// Every answer carries `Ito-Protocol`. Until 1.0 the minor version must match exactly.
    private static func checkVersion(_ headers: [String: String]) throws(RequestError) {
        guard let header = headers["ito-protocol"], let version = ProtocolVersion(header),
            version != .supported
        else { return }
        throw .protocolMismatch(server: version)
    }

    private static func refusal(_ response: HTTPResponse) -> RequestError {
        let error = try? JSONDecoder().decode(ErrorResult.self, from: response.body).error
        let retryAfter = response.headers["retry-after"].flatMap(Double.init).map {
            Duration.milliseconds(Int(($0 * 1000).rounded()))
        }
        return .refused(status: response.status, error: error, retryAfter: retryAfter)
    }

    private static func json(_ value: some Encodable) throws(RequestError) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw .unreadable(String(describing: error))
        }
    }

    private static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id
    }
}

/// Why a request failed.
public enum RequestError: Error, Equatable, Sendable {
    /// It, or its answer, was lost on the way: the device is offline, the server is unreachable, or
    /// the connection dropped. Trying again is safe.
    case network(URLError.Code)
    /// The server refused it, with its reason when it gave one.
    case refused(status: Int, error: ServerError?, retryAfter: Duration?)
    /// The server speaks a protocol version this Ari doesn't.
    case protocolMismatch(server: ProtocolVersion)
    /// The answer couldn't be read.
    case unreadable(String)

    init(_ error: any Error) {
        if let error = error as? RequestError {
            self = error
        } else if let error = error as? URLError {
            self = .network(error.code)
        } else {
            self = .network(.unknown)
        }
    }

    /// Whether the same request may simply be sent again later: a lost request, a busy server
    /// (`429`) or a server-side failure (`5xx`). Every Ito command is safe to repeat.
    public var isTemporary: Bool {
        switch self {
        case .network: true
        case .refused(let status, _, _): status == 429 || status >= 500
        case .protocolMismatch, .unreadable: false
        }
    }

    /// How long the server asked Ari to wait, if it did.
    public var retryAfter: Duration? {
        if case .refused(_, _, let retryAfter) = self { retryAfter } else { nil }
    }

    /// The server's status code, if it answered.
    public var status: Int? {
        if case .refused(let status, _, _) = self { status } else { nil }
    }

    /// The server's reason, in its own words, if it gave one.
    public var serverError: ServerError? {
        if case .refused(_, let error, _) = self { error } else { nil }
    }
}
