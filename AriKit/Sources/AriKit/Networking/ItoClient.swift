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

    // MARK: - The agent's model

    /// `GET /v0/models`: the models the engine offers, and the current choice.
    public func models() async throws(RequestError) -> ModelList {
        try await call(HTTPRequest(.get, "/v0/models"))
    }

    /// `PUT /v0/agent`: choose the model and how hard it thinks, for the whole server, from the next
    /// message.
    public func choose(_ choice: ModelChoice) async throws(RequestError) -> ModelChoice {
        try await call(HTTPRequest(.put, "/v0/agent", body: try Self.json(choice)))
    }

    // MARK: - Memory, read-only

    /// `GET /v0/memory/in-mind`: Portrait, Now and How to help you, in full.
    public func inMind() async throws(RequestError) -> MemoryPages {
        try await call(HTTPRequest(.get, "/v0/memory/in-mind"))
    }

    /// `GET /v0/memory/shelves`: each shelf and how many pages it holds.
    public func shelves() async throws(RequestError) -> ShelfList {
        try await call(HTTPRequest(.get, "/v0/memory/shelves"))
    }

    /// `GET /v0/memory/recent`: what Ari changed lately, newest first, with its notes.
    public func recentChanges() async throws(RequestError) -> RecentChanges {
        try await call(HTTPRequest(.get, "/v0/memory/recent"))
    }

    /// `GET /v0/memory/pages?shelf=…`: the pages on a shelf.
    public func pages(on shelf: String) async throws(RequestError) -> PageList {
        try await call(HTTPRequest(.get, Self.path("/v0/memory/pages", ["shelf": shelf])))
    }

    /// `GET /v0/memory/page?address=…`: one page, its Markdown without front matter. A day of the
    /// journal is a page too, such as `memory:journal/2026-10-25`.
    public func page(_ address: PageAddress) async throws(RequestError) -> MemoryPage {
        try await call(
            HTTPRequest(.get, Self.path("/v0/memory/page", ["address": address.rawValue])))
    }

    /// `GET /v0/memory/changes/{change}`: what one update did to a page.
    public func change(_ change: String) async throws(RequestError) -> PageChange {
        try await call(HTTPRequest(.get, "/v0/memory/changes/\(Self.segment(change))"))
    }

    // MARK: - In motion

    /// `GET /v0/motion`: everything going on, then what's done, each newest first.
    public func motions() async throws(RequestError) -> MotionList {
        try await call(HTTPRequest(.get, "/v0/motion"))
    }

    /// `GET /v0/motion/{id}`: one thing, with its content, your ticks and what changed.
    public func motion(_ id: MotionID) async throws(RequestError) -> MotionDetail {
        try await call(HTTPRequest(.get, "/v0/motion/\(Self.segment(id.rawValue))"))
    }

    /// `PATCH /v0/motion/{id}/state`: ticks or unticks an item in one of a thing's lists. Every
    /// device hears it as `motion.state`, and a few seconds later Ari keeps the thing up with it, as
    /// an ordinary `motion.changed`. The answer is all of the thing's ticks.
    public func tick(_ motion: MotionID, list: String, item: String, done: Bool)
        async throws(RequestError) -> MotionState
    {
        let patch: MotionState = [list: [item: MotionTick(done: done)]]
        let answer: MotionStateBody = try await call(
            HTTPRequest(
                .patch, "/v0/motion/\(Self.segment(motion.rawValue))/state",
                body: try Self.json(patch)))
        return answer.state
    }

    // MARK: - Talk

    /// `PUT /v0/calls/{call}`: start a call under the id Ari chose, so starting it again is safe.
    /// Starting one ends any call left on.
    public func startCall(_ call: CallID) async throws(RequestError) -> CallResult {
        try await self.call(HTTPRequest(.put, "/v0/calls/\(Self.segment(call.rawValue))"))
    }

    /// `POST /v0/calls/{call}/end`, with its length. Ending it again changes nothing.
    public func endCall(_ call: CallID) async throws(RequestError) -> CallResult {
        try await self.call(HTTPRequest(.post, "/v0/calls/\(Self.segment(call.rawValue))/end"))
    }

    /// `DELETE /v0/calls/{call}/audio`: the recordings of the call's spoken messages go; their
    /// words stay.
    public func deleteAudio(of call: CallID) async throws(RequestError) -> CallResult {
        try await self.call(
            HTTPRequest(.delete, "/v0/calls/\(Self.segment(call.rawValue))/audio"))
    }

    /// `GET /v0/voices`: Ari's voices, the one chosen, and whether the server can talk.
    public func voices() async throws(RequestError) -> VoiceList {
        try await call(HTTPRequest(.get, "/v0/voices"))
    }

    /// `PUT /v0/messages/{message}/parts/{part}/items/{item}`: ticks or unticks an item in a reply's
    /// plan. Every device hears it as `plan.ticked`; the answer is the reply's ticks.
    public func tick(_ message: MessageID, part: Int, item: String, done: Bool)
        async throws(RequestError) -> TickList
    {
        let path =
            "/v0/messages/\(Self.segment(message.rawValue))/parts/\(part)/items/\(Self.segment(item))"
        return try await call(HTTPRequest(.put, path, body: try Self.json(TickItem(done: done))))
    }

    /// `DELETE /v0/voice/voiceprint`: forgets your voice, so the server learns it again from your
    /// next calls. The answer is the voice list, now `learning`.
    public func forgetVoiceprint() async throws(RequestError) -> VoiceList {
        try await call(HTTPRequest(.delete, "/v0/voice/voiceprint"))
    }

    /// `PUT /v0/voice`: Ari's voice for the whole server, from the next sentence.
    public func choose(voice: VoiceChoice) async throws(RequestError) -> VoiceChoice {
        try await call(HTTPRequest(.put, "/v0/voice", body: try Self.json(voice)))
    }

    /// `POST /v0/speech`: a line in Ari's voice, as a WAV (24 kHz, mono, 16-bit PCM).
    public func speak(_ request: SpeechRequest) async throws(RequestError) -> Data {
        try await raw(HTTPRequest(.post, "/v0/speech", body: try Self.json(request)))
    }

    /// `POST /v0/vocabulary/corrections`: what the recogniser heard and what you meant. The answer
    /// says which page each mishearing joined.
    public func teach(_ corrections: VocabularyCorrections) async throws(RequestError)
        -> VocabularyCorrections
    {
        try await call(
            HTTPRequest(.post, "/v0/vocabulary/corrections", body: try Self.json(corrections)))
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

    /// A path with a query, its values percent-encoded (a `+` too, which servers read as a space).
    private static func path(_ path: String, _ query: [String: String]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = query.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return path + (encoded.map { "?" + $0 } ?? "")
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
