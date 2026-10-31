import Foundation

// Settings for Kumo itself: its name, and when the morning card may come. Both are read with
// `server()`, as `lead` and `briefing`.

extension ItoClient {
    /// `PUT /v0/lead`: renames the lead, from its next message. The answer is the lead as saved.
    public func renameLead(to name: String) async throws(RequestError) -> Lead {
        try await exchange(HTTPRequest(.put, "/v0/lead", body: try Self.encoded(Lead(name: name))))
    }

    /// `PUT /v0/briefing`: the earliest the morning card may come. The answer is the time as saved.
    public func setBriefing(_ time: BriefingTime) async throws(RequestError) -> BriefingTime {
        try await exchange(HTTPRequest(.put, "/v0/briefing", body: try Self.encoded(time)))
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
