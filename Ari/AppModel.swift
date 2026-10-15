import AriKit
import Foundation
import Observation

/// The server Ari is connected to, if any, and its session. The address and who answered are kept
/// in the defaults; the token only ever in the Keychain.
@Observable
final class AppModel {
    private(set) var session: Session?
    /// The address to suggest on the connect screen, such as after the token stopped working.
    private(set) var lastAddress: String = ""
    /// Who answered at the address: the server's name, version and protocol, for Settings.
    private(set) var server: ServerInfo?

    @ObservationIgnored private let tokens: any TokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var address: ServerAddress?

    init(tokens: any TokenStore = KeychainTokenStore(), defaults: UserDefaults = .standard) {
        self.tokens = tokens
        self.defaults = defaults
        guard let saved = Saved.load(from: defaults) else { return }
        address = saved.address
        lastAddress = saved.address.description
        server = saved.server
        if let token = try? tokens.token(for: saved.address) {
            session = Self.session(
                for: Connection(address: saved.address, token: token, server: saved.server))
        }
    }

    /// The connect screen reached a server that accepted the token.
    func connected(_ connection: Connection) {
        try? tokens.save(connection.token, for: connection.address)
        Saved(address: connection.address, server: connection.server).save(to: defaults)
        address = connection.address
        lastAddress = connection.address.description
        server = connection.server
        session?.close()
        session = Self.session(for: connection)
        session?.start()
    }

    /// Asks the server who it is again, so Settings shows what it runs now rather than what it ran
    /// when you first connected.
    func refreshServer() {
        guard let address, let token = try? tokens.token(for: address) else { return }
        let client = ItoClient(address: address, token: token, transport: URLSessionTransport())
        Task {
            guard let info = try? await client.server(), info != server else { return }
            server = info
            Saved(address: address, server: info).save(to: defaults)
        }
    }

    /// Back to the connect screen, forgetting the token, as when the server stopped accepting it.
    func connectAgain() {
        if let address { try? tokens.delete(for: address) }
        session?.close()
        session = nil
    }

    private static func session(for connection: Connection) -> Session {
        let outbox =
            (try? OutboxStore.applicationSupport(for: connection.address))
            ?? OutboxStore(
                directory: FileManager.default.temporaryDirectory.appending(path: "Outbox"))
        return Session(connection: connection, outbox: outbox)
    }

    private struct Saved: Codable {
        let address: ServerAddress
        let server: ServerInfo

        static func load(from defaults: UserDefaults) -> Saved? {
            defaults.data(forKey: "server").flatMap {
                try? JSONDecoder().decode(Saved.self, from: $0)
            }
        }

        func save(to defaults: UserDefaults) {
            defaults.set(try? JSONEncoder().encode(self), forKey: "server")
        }
    }
}
