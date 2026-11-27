import Foundation

// Settings for Kumo itself: its name, read with `server()` as `lead`.

extension ItoClient {
    /// `PUT /v0/lead`: renames the lead, from its next message. The answer is the lead as saved.
    public func renameLead(to name: String) async throws(RequestError) -> Lead {
        try await exchange(HTTPRequest(.put, "/v0/lead", body: try Self.encoded(Lead(name: name))))
    }

    // MARK: - Plumbing

    // A copy of ItoClient's own, which is private to its file: authorized, JSON in and out, the
    // protocol version checked, and a refusal read for the server's reason.

    private func exchange<Answer: Decodable>(_ request: HTTPRequest) async throws(RequestError)
        -> Answer
    {
        var request = request
        if let token { request.headers["Authorization"] = "Bearer \(token.secret)" }
        if request.body != nil { request.headers["Content-Type"] = "application/json" }
        let response: HTTPResponse
        do {
            response = try await transport.send(request, to: address.url)
        } catch {
            throw RequestError(error)
        }
        if let header = response.headers["ito-protocol"], let version = ProtocolVersion(header),
            version != .supported
        {
            throw .protocolMismatch(server: version)
        }
        guard (200..<300).contains(response.status) else {
            let error = try? JSONDecoder().decode(ErrorResult.self, from: response.body).error
            let retryAfter = response.headers["retry-after"].flatMap(Double.init).map {
                Duration.milliseconds(Int(($0 * 1000).rounded()))
            }
            throw .refused(status: response.status, error: error, retryAfter: retryAfter)
        }
        do {
            return try JSONDecoder().decode(Answer.self, from: response.body)
        } catch {
            throw .unreadable(String(describing: error))
        }
    }

    private static func encoded(_ value: some Encodable) throws(RequestError) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw .unreadable(String(describing: error))
        }
    }
}

// MARK: - Full access and the dream's time

extension ItoClient {
    /// `GET /v0/access`: how Kumo runs on the server, in its sandbox or with full access.
    public func access() async throws(RequestError) -> Access {
        try await call(HTTPRequest(.get, "/v0/access"))
    }

    /// `POST /v0/access/full`: Kumo runs without its sandbox from its next turn. Send it only once
    /// the phone has checked it's you: the body says it's meant. The answer is the new state.
    public func giveFullAccess() async throws(RequestError) -> Access {
        try await call(
            HTTPRequest(.post, "/v0/access/full", body: try Self.json(FullAccessConsent())))
    }

    /// `DELETE /v0/access/full`: Kumo is back in its sandbox from its next turn. Safe to repeat.
    public func endFullAccess() async throws(RequestError) -> Access {
        try await call(HTTPRequest(.delete, "/v0/access/full"))
    }

    /// `GET /v0/dream`: when Kumo dreams, and when it last did.
    public func dreamSchedule() async throws(RequestError) -> DreamSchedule {
        try await call(HTTPRequest(.get, "/v0/dream"))
    }

    /// `PUT /v0/dream/time`: Kumo dreams at this time each night from now on, on your local clock.
    public func changeDreamTime(to time: DreamSchedule.Time) async throws(RequestError)
        -> DreamSchedule
    {
        try await call(
            HTTPRequest(
                .put, "/v0/dream/time", body: try Self.json(DreamScheduleChange(time: time))))
    }
}
