import Foundation

/// How AriKit reaches a server: one request at a time, or one long-lived response read as it
/// arrives. The app uses ``URLSessionTransport``; tests play a transcript's server through a fake,
/// so everything above this seam runs exactly as it does against a real server.
public protocol Transport: Sendable {
    /// Sends `request` to the server at `base` and returns the whole response. Throws a `URLError`
    /// when the request or its answer is lost on the way.
    func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse

    /// Sends `request` and returns as soon as the response's head arrives; its body follows as it
    /// comes. Cancelling the body's iteration closes the connection.
    func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream
}

/// A request to an Ito server, relative to its address.
public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }

    public var method: Method
    /// The path and query, such as `/v0/messages?before=…&limit=50`.
    public var path: String
    public var headers: [String: String]
    public var body: Data?

    public init(
        _ method: Method, _ path: String, headers: [String: String] = [:], body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// The request as a `URLRequest` to the server at `base`.
    public func urlRequest(to base: URL) -> URLRequest {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        var request = URLRequest(url: URL(string: root + path) ?? base)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}

/// A whole response.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    /// Header names in lower case.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $1 })
        self.body = body
    }
}

/// A long-lived response: its head, then its body in pieces as they arrive.
public struct HTTPStream: Sendable {
    public var status: Int
    /// Header names in lower case.
    public var headers: [String: String]
    public var body: AsyncThrowingStream<Data, any Error>

    public init(
        status: Int, headers: [String: String] = [:], body: AsyncThrowingStream<Data, any Error>
    ) {
        self.status = status
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $1 })
        self.body = body
    }
}

/// The transport the app uses: an ephemeral `URLSession`, with no cache, cookies or credential
/// storage, so nothing about the server or the token is kept outside the Keychain.
public final class URLSessionTransport: Transport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        // The event stream sends a ping at least every 15 seconds and Ari reconnects after 45 of
        // silence, so a minute without data means the connection is gone.
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    @concurrent
    public func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request.urlRequest(to: base))
        let http = try Self.http(response)
        return HTTPResponse(status: http.statusCode, headers: Self.headers(http), body: data)
    }

    @concurrent
    public func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
        let (bytes, response) = try await session.bytes(for: request.urlRequest(to: base))
        let http = try Self.http(response)
        // Hand the body on a line at a time: the event stream is line-based, and a byte at a time
        // would cost a hop per byte.
        let body = AsyncThrowingStream<Data, any Error> { continuation in
            let reader = Task {
                var line = Data()
                do {
                    for try await byte in bytes {
                        line.append(byte)
                        if byte == 0x0A || byte == 0x0D || line.count >= 4096 {
                            continuation.yield(line)
                            line.removeAll(keepingCapacity: true)
                        }
                    }
                    if !line.isEmpty { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return HTTPStream(status: http.statusCode, headers: Self.headers(http), body: body)
    }

    private static func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return http
    }

    private static func headers(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for case (let name as String, let value as String) in response.allHeaderFields {
            headers[name] = value
        }
        return headers
    }
}
