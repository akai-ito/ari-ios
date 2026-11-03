import AriKit
import Foundation
import Observation
import UIKit
import UserNotifications

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
    /// Why iOS wouldn't register for notifications, such as a build without the push entitlement.
    private(set) var notificationProblem: String?
    /// Whether Ari may still offer notifications: never asked, never answered.
    private(set) var offersNotifications = false
    /// A reply to open the conversation at, from a tapped notification.
    var opening: MessageID?
    /// Where in the chat to go, from a thing in motion's "What changed".
    var openingPosition: Int?
    /// Whether you're reading the chat here: Ari in front, on the Chat tab. Its notifications then
    /// show no banner.
    private(set) var isLooking = false
    /// A pairing link from `ito pair`'s QR code, opened from the Camera or another app, for the
    /// connect screen to use.
    var pairing: PairingLink?

    @ObservationIgnored let notifications = NotificationStore.forThisApp()
    @ObservationIgnored private var pushToken: String?

    @ObservationIgnored private let tokens: any TokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var address: ServerAddress?

    /// Shared with the extensions: on the iPhone, the share extension reads the address and token.
    @ObservationIgnored private let group = AppGroup.forThisApp()

    init(tokens: (any TokenStore)? = nil, defaults: UserDefaults = .standard) {
        self.tokens = tokens ?? group.tokens
        self.defaults = defaults
        guard let saved = Saved.load(from: defaults) else { return }
        group.address = saved.address
        address = saved.address
        lastAddress = saved.address.description
        server = saved.server
        if let server = saved.server { LeadName.remember(server.lead.name) }
        if let token = try? self.tokens.token(for: saved.address) {
            session = Self.session(at: saved.address, token: token)
        }
    }

    /// The connect screen reached a server that accepted the token.
    func connected(_ connection: Connection) {
        pairing = nil
        try? tokens.save(connection.token, for: connection.address)
        Saved(address: connection.address, server: connection.server).save(to: defaults)
        group.address = connection.address
        address = connection.address
        lastAddress = connection.address.description
        server = connection.server
        LeadName.remember(connection.server.lead.name)
        if let previous = session, previous.address != connection.address {
            forgetDevice(at: previous.address)
        }
        session?.close()
        session = Self.session(at: connection.address, token: connection.token)
        session?.start()
        registerDevice()
    }

    /// A link Ari was opened with: only pairing links, for now.
    func open(_ url: URL) {
        guard let link = Connector.pairing(from: url) else { return }
        pairing = PairingLink(address: link.address, code: link.code)
    }

    /// Shares the share extension couldn't send, as when the phone was offline: they go now, in
    /// the order you shared them.
    func collectShares() {
        guard let session, let shares = group.shares() else { return }
        for attachment in shares.attachments() {
            session.attach(attachment)
            shares.removeAttachment(attachment.id)
        }
        for message in (try? shares.load()) ?? [] {
            session.send(message.text, id: message.id, attachments: message.attachments ?? [])
            try? shares.remove(message.id)
        }
    }

    /// A client for the server Ari is connected to, for calls outside the conversation, such as
    /// Settings' capabilities.
    func client() -> ItoClient? {
        guard let address, let token = try? tokens.token(for: address) else { return nil }
        return ItoClient(address: address, token: token, transport: URLSessionTransport())
    }

    /// Asks the server who it is again, so Settings shows what it runs now rather than what it ran
    /// when you first connected.
    func refreshServer() {
        guard let address, let client = client() else { return }
        Task {
            guard let info = try? await client.server(), info != server else { return }
            server = info
            LeadName.remember(info.lead.name)
            Saved(address: address, server: info).save(to: defaults)
        }
    }

    /// Back to the connect screen, forgetting the token, as when the server stopped accepting it.
    func connectAgain() {
        if let address {
            forgetDevice(at: address)
            try? tokens.delete(for: address)
        }
        group.address = nil
        session?.close()
        session = nil
    }

    // MARK: - Notifications

    /// At launch: if you turned notifications on and still allow them, register again, so a new
    /// push token or a 30-day-old key reaches the server.
    func restoreNotifications() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let allowed = settings.authorizationStatus == .authorized
            notificationsOn = allowed && defaults.bool(forKey: "notifications")
            offersNotifications =
                settings.authorizationStatus == .notDetermined
                && !defaults.bool(forKey: "notificationsOffered")
            if notificationsOn { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// You said yes to notifications: ask iOS, then register with the push service. Returns
    /// whether iOS allows them.
    @discardableResult
    func turnOnNotifications() async -> Bool {
        defaults.set(true, forKey: "notificationsOffered")
        offersNotifications = false
        let center = UNUserNotificationCenter.current()
        let allowed =
            (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        defaults.set(allowed, forKey: "notifications")
        notificationsOn = allowed
        if allowed { UIApplication.shared.registerForRemoteNotifications() }
        return allowed
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
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    /// You left the server at `address`: it forgets this device, so it stops sending notifications
    /// here. Straight to the server rather than through the session, which closes at once.
    private func forgetDevice(at address: ServerAddress) {
        guard notificationsOn, let token = try? tokens.token(for: address) else { return }
        let client = ItoClient(address: address, token: token, transport: URLSessionTransport())
        let device = notifications.deviceID
        Task { try? await client.removeDevice(device) }
    }

    /// The push service gave this device its token.
    func didRegister(token: Data) {
        notificationProblem = nil
        pushToken = token.map { String(format: "%02x", $0) }.joined()
        registerDevice()
    }

    /// iOS wouldn't register for notifications. Settings says why, rather than nothing arriving.
    func failedToRegister(_ error: any Error) {
        notificationProblem = error.localizedDescription
    }

    /// You started or stopped reading the chat here. The server notifies every message whatever
    /// you're doing; this only decides whether one shows as a banner while Ari is in front.
    func setLooking(_ looking: Bool) {
        isLooking = looking
    }

    /// An answer given from a notification: it goes at once, even with Ari in the background.
    func answer(fromNotification text: String) async {
        guard let session else { return }
        await session.sendFromNotification(text)
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

    private static func session(at address: ServerAddress, token: Token) -> Session {
        let outbox =
            (try? OutboxStore.applicationSupport(for: address))
            ?? OutboxStore(
                directory: FileManager.default.temporaryDirectory.appending(path: "Outbox"))
        return Session(address: address, token: token, outbox: outbox, cache: .forThisApp())
    }

    private struct Saved: Codable {
        let address: ServerAddress
        /// `nil` when an older Ari saved it in a shape this one can't read, such as before a field
        /// was renamed: the address and token still connect, and coming on screen asks again.
        let server: ServerInfo?

        init(address: ServerAddress, server: ServerInfo) {
            self.address = address
            self.server = server
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = try container.decode(ServerAddress.self, forKey: .address)
            server = try? container.decode(ServerInfo.self, forKey: .server)
        }

        enum CodingKeys: String, CodingKey {
            case address, server
        }

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
