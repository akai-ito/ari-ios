import Foundation

/// The first connection, step by step, so every problem can be named: is the address usable, is
/// it an Ito server, does it speak Ari's protocol, and is the token right.
public struct Connector: Sendable {
    let transport: any Transport

    public init(transport: any Transport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Checks the address and what the server speaks. Ari can then ask for the token, or check a
    /// new token against the same server without asking again.
    public func discover(_ address: String) async throws(ConnectError) -> ServerAddress {
        let server: ServerAddress
        do {
            server = try ServerAddress(address)
        } catch {
            throw .address(error)
        }
        let discovery: Discovery
        do {
            discovery = try await ItoClient(address: server, token: nil, transport: transport)
                .discover()
        } catch {
            throw ConnectError(error)
        }
        guard discovery.product == "ito" else { throw .notIto }
        guard discovery.versions.contains(.supported) else {
            throw .protocolMismatch(ProtocolMismatch(server: discovery.versions))
        }
        return server
    }

    /// Checks `token` with the server at `address`, which ``discover(_:)`` approved.
    public func check(_ token: Token, at address: ServerAddress) async throws(ConnectError)
        -> Connection
    {
        do {
            let client = ItoClient(address: address, token: token, transport: transport)
            return Connection(address: address, token: token, server: try await client.server())
        } catch {
            throw ConnectError(error)
        }
    }

    /// Both steps.
    public func connect(to address: String, token: Token) async throws(ConnectError) -> Connection {
        try await check(token, at: try await discover(address))
    }

    /// Pairs with the server at `address` using the code `ito pair` showed (from its QR code, or
    /// typed), which the server exchanges for a token of this device's own.
    public func pair(address: String, code: String, deviceName: String) async throws(ConnectError)
        -> Connection
    {
        try await pair(code: code, deviceName: deviceName, at: try await discover(address))
    }

    /// Pairs with a server already found with ``discover(_:)``.
    public func pair(code: String, deviceName: String, at server: ServerAddress)
        async throws(ConnectError) -> Connection
    {
        let result: PairResult
        do {
            result = try await ItoClient(address: server, token: nil, transport: transport)
                .pair(PairDevice(code: code, deviceName: deviceName))
        } catch {
            if case .refused(401, let error, _) = error { throw .pairingCodeRejected(error) }
            throw ConnectError(error)
        }
        return try await check(Token(result.token), at: server)
    }

    /// A pairing link from `ito pair`'s QR code: `ito://pair?address=…&code=…`.
    public static func pairing(from link: URL) -> (address: String, code: String)? {
        guard link.scheme == "ito", link.host() == "pair",
            let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
            let address = items.first(where: { $0.name == "address" })?.value,
            let code = items.first(where: { $0.name == "code" })?.value
        else { return nil }
        return (address, code)
    }

    /// Whether what you typed in place of a token is a pairing code: 8 letters and digits, with
    /// or without a dash in the middle.
    public static func isPairingCode(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(
            of: "-", with: "")
        return compact.count == 8
            && compact.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

/// A server Ari has reached with a token it accepted.
public struct Connection: Sendable, Equatable {
    public let address: ServerAddress
    public let token: Token
    public let server: ServerInfo

    public init(address: ServerAddress, token: Token, server: ServerInfo) {
        self.address = address
        self.token = token
        self.server = server
    }
}

/// Why a first connection failed, specifically enough to say so.
public enum ConnectError: Error, Equatable, Sendable {
    case address(ServerAddress.Problem)
    /// Nothing answered: the server is off, the address is wrong, or this device is offline.
    case unreachable(URLError.Code)
    /// Something answered, but not an Ito server.
    case notIto
    case protocolMismatch(ProtocolMismatch)
    /// The server didn't accept the token. Its message says so in plain words.
    case tokenRejected(ServerError?)
    /// The pairing code had expired or was already used.
    case pairingCodeRejected(ServerError?)
    /// The server refused for another reason.
    case refused(status: Int, error: ServerError?)

    init(_ error: RequestError) {
        switch error {
        case .network(let code): self = .unreachable(code)
        case .refused(401, let error, _): self = .tokenRejected(error)
        case .refused(404, _, _): self = .notIto
        case .refused(let status, let error, _): self = .refused(status: status, error: error)
        case .protocolMismatch(let version):
            self = .protocolMismatch(ProtocolMismatch(server: [version]))
        case .unreadable: self = .notIto
        }
    }
}

/// Ari and the server speak different protocol versions, and which of them should be updated.
public struct ProtocolMismatch: Equatable, Sendable {
    /// What the server speaks.
    public let server: [ProtocolVersion]

    public enum Side: Sendable { case ari, server }

    /// The older side: "Update Ari" when the server is ahead, "Update Ito on your server" when Ari
    /// is.
    public var update: Side {
        (server.max() ?? .supported) > .supported ? .ari : .server
    }
}
