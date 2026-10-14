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

    @ObservationIgnored private let tokens: any TokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var address: ServerAddress?

    init(tokens: any TokenStore = KeychainTokenStore(), defaults: UserDefaults = .standard) {
        self.tokens = tokens
        self.defaults = defaults
        guard let saved = Saved.load(from: defaults) else { return }
        address = saved.address
        lastAddress = saved.address.description
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
        session?.close()
        session = Self.session(for: connection)
        session?.start()
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
