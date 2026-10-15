import AriKit
import Foundation
import Observation

#if os(iOS)
    import UIKit
    import UserNotifications
#endif

/// The server Ari is connected to, if any, and its session. The address and who answered are kept
/// in the defaults; the token only ever in the Keychain.
@Observable
final class AppModel {
    private(set) var session: Session?
    /// The address to suggest on the connect screen, such as after the token stopped working.
    private(set) var lastAddress: String = ""
    /// Who answered at the address: the server's name, version and protocol, for Settings.
    private(set) var server: ServerInfo?
    /// Whether Ari tells you when it's done or needs you: you allowed it, and haven't turned it off.
    private(set) var notificationsOn = false
    /// Whether Ari may still offer notifications: never asked, never answered.
    private(set) var offersNotifications = false
    /// A reply to open the conversation at, from a tapped notification.
    var opening: MessageID?
    /// Whether the conversation is on screen here.
    private(set) var isLooking = false
    /// A pairing link from `ito pair`'s QR code, opened from the Camera or another app, for the
    /// connect screen to use.
    var pairing: PairingLink?

    @ObservationIgnored let notifications = NotificationStore.forThisApp()
    @ObservationIgnored private var pushToken: String?

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
        pairing = nil
        try? tokens.save(connection.token, for: connection.address)
        Saved(address: connection.address, server: connection.server).save(to: defaults)
        address = connection.address
        lastAddress = connection.address.description
        server = connection.server
        session?.close()
        session = Self.session(for: connection)
        session?.start()
        registerDevice()
    }

    /// A link Ari was opened with: only pairing links, for now.
    func open(_ url: URL) {
        guard let link = Connector.pairing(from: url) else { return }
        pairing = PairingLink(address: link.address, code: link.code)
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

    // MARK: - Notifications

    /// At launch: if you turned notifications on and still allow them, register again, so a new
    /// push token or a 30-day-old key reaches the server.
    func restoreNotifications() {
        #if os(iOS)
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                let allowed = settings.authorizationStatus == .authorized
                notificationsOn = allowed && defaults.bool(forKey: "notifications")
                offersNotifications =
                    settings.authorizationStatus == .notDetermined
                    && !defaults.bool(forKey: "notificationsOffered")
                if notificationsOn { UIApplication.shared.registerForRemoteNotifications() }
            }
        #endif
    }

    /// You said yes to notifications: ask iOS, then register with the push service. Returns
    /// whether iOS allows them.
    @discardableResult
    func turnOnNotifications() async -> Bool {
        #if os(iOS)
            defaults.set(true, forKey: "notificationsOffered")
            offersNotifications = false
            let center = UNUserNotificationCenter.current()
            let allowed =
                (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            defaults.set(allowed, forKey: "notifications")
            notificationsOn = allowed
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            return allowed
        #else
            return false
        #endif
    }

    /// Not now: Ari doesn't offer again; Settings can still turn them on.
    func declineNotifications() {
        defaults.set(true, forKey: "notificationsOffered")
        offersNotifications = false
    }

    /// You turned notifications off: the server forgets this device and its key goes.
    func turnOffNotifications() {
        defaults.set(false, forKey: "notifications")
        notificationsOn = false
        session?.unregister(device: notifications.deviceID)
        notifications.forgetKeys()
        #if os(iOS)
            UIApplication.shared.unregisterForRemoteNotifications()
        #endif
    }

    /// The push service gave this device its token.
    func didRegister(token: Data) {
        pushToken = token.map { String(format: "%02x", $0) }.joined()
        registerDevice()
    }

    /// The conversation came on screen here, or left it. The server forgets this when it restarts,
    /// so it's said again whenever the connection comes back.
    func setLooking(_ looking: Bool) {
        isLooking = looking
        guard notificationsOn else { return }
        session?.setLooking(looking, device: notifications.deviceID)
    }

    /// The event stream is live again.
    func reconnected() {
        if isLooking { setLooking(true) }
    }

    /// An answer given from a notification: it goes at once, even with Ari in the background.
    func answer(fromNotification text: String, ask: AskID?) async {
        guard let session else { return }
        await session.sendFromNotification(text, answers: ask)
    }

    private func registerDevice() {
        guard notificationsOn, let pushToken, let session else { return }
        let registration = RegisterDevice(
            apnsToken: pushToken, environment: Self.pushEnvironment,
            notificationKey: notifications.currentKey().key)
        session.register(device: notifications.deviceID, registration)
    }

    /// Builds from Xcode talk to Apple's sandbox push service, and say so in their provisioning
    /// profile; TestFlight and App Store builds have none, and use production.
    private static let pushEnvironment: PushEnvironment = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .isoLatin1),
            let key = text.range(of: "<key>aps-environment</key>")
        else { return .production }
        return text[key.upperBound...].prefix(80).contains("development") ? .sandbox : .production
    }()

    private static func session(for connection: Connection) -> Session {
        let outbox =
            (try? OutboxStore.applicationSupport(for: connection.address))
            ?? OutboxStore(
                directory: FileManager.default.temporaryDirectory.appending(path: "Outbox"))
        return Session(connection: connection, outbox: outbox, cache: .forThisApp())
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
