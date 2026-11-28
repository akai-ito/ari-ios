import Foundation

extension ItoClient {
    // MARK: - Places

    /// The request for `POST /v0/location/batches`, without its body, for a background upload from
    /// a sealed batch's file.
    public func trailRequest(body: Data? = nil) -> HTTPRequest {
        authorize(
            HTTPRequest(
                .post, "/v0/location/batches", headers: ["Content-Type": "application/json"],
                body: body))
    }

    /// `POST /v0/location/batches`: a sealed batch of the trail, as its file holds it. Sending it
    /// again is always safe.
    public func sendTrail(_ body: Data) async throws(RequestError) {
        let response: HTTPResponse
        do {
            response = try await transport.send(trailRequest(body: body), to: address.url)
        } catch {
            throw RequestError(error)
        }
        if case .failure(let error) = Self.trailAnswer(
            status: response.status, headers: response.headers, body: response.body)
        {
            throw error
        }
    }

    /// Reads a batch's answer, as a background upload hears it: kept, or why not.
    public static func trailAnswer(status: Int, headers: [String: String], body: Data)
        -> Result<Void, RequestError>
    {
        let response = HTTPResponse(status: status, headers: headers, body: body)
        do throws(RequestError) {
            try checkVersion(response.headers)
        } catch {
            return .failure(error)
        }
        return TrailUploads.kept(status) ? .success(()) : .failure(refusal(response))
    }

    /// `POST /v0/location/photos`: where and when photos were taken, to seed the past. Sending a
    /// batch again is always safe.
    public func seedPhotos(_ seeds: PhotoSeeds) async throws(RequestError) {
        _ = try await raw(
            HTTPRequest(.post, "/v0/location/photos", body: try Self.json(seeds)))
    }

    /// `GET /v0/location`: how much the box keeps, and from when to when.
    public func location() async throws(RequestError) -> LocationHeld {
        try await call(HTTPRequest(.get, "/v0/location"))
    }

    /// `POST /v0/location/forget`: deletes a day, a range of days or everything from the box.
    public func forgetLocation(_ forget: ForgetLocation) async throws(RequestError) {
        _ = try await raw(
            HTTPRequest(.post, "/v0/location/forget", body: try Self.json(forget)))
    }
}
