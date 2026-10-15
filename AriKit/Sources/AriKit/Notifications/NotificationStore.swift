import Foundation
import Security

/// What Ari and its notification service extension share through their app group: this install's
/// device id, and the notification keys, kept in the Keychain where the extension can read them
/// while the phone is locked.
///
/// Keys rotate every 30 days. The previous key is kept, so a notification already on its way when
/// the key changed still decrypts.
public struct NotificationStore: Sendable {
    /// The app group's identifier, such as `group.io.github.akai-ito.ari`.
    public let group: String
    private let storage: any KeyStorage
    private let now: @Sendable () -> Date

    public static let rotation: TimeInterval = 30 * 24 * 3600

    public init(
        group: String, storage: (any KeyStorage)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.group = group
        self.storage = storage ?? KeychainKeyStorage(group: group)
        self.now = now
    }

    /// The store for this app, or for one of its extensions: the group named after the app's
    /// bundle identifier.
    public static func forThisApp(_ bundle: Bundle = .main) -> NotificationStore {
        NotificationStore(group: AppGroup.forThisApp(bundle).identifier)
    }

    /// This install's id, made once. The server keeps one registration per device, and seals each
    /// notification with this id as additional data.
    public var deviceID: String {
        let defaults = UserDefaults(suiteName: group) ?? .standard
        if let id = defaults.string(forKey: "device") { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: "device")
        return id
    }

    /// The keys a notification may have been sealed with, newest first.
    public func keys() -> [NotificationKey] {
        stored().map(\.key)
    }

    /// The key to register with: the newest, or a new one if there's none or it's 30 days old.
    /// Returns whether it's new, so the device registers again.
    public func currentKey() -> (key: NotificationKey, isNew: Bool) {
        let kept = stored()
        if let newest = kept.first, now().timeIntervalSince(newest.made) < Self.rotation {
            return (newest.key, false)
        }
        let made = Stored(key: NotificationKey(), made: now())
        save([made] + kept.prefix(1))
        return (made.key, true)
    }

    /// Uses `key` from now on, keeping the one before: for trying notifications in the Simulator,
    /// where a test sends a push sealed with a key it knows.
    public func adopt(_ key: NotificationKey) {
        save([Stored(key: key, made: now())] + stored().prefix(1))
    }

    /// Forgets every key, as when notifications are turned off.
    public func forgetKeys() {
        save([])
    }

    private struct Stored: Codable {
        let key: NotificationKey
        let made: Date
    }

    private func stored() -> [Stored] {
        guard let data = storage.read() else { return [] }
        return (try? JSONDecoder().decode([Stored].self, from: data)) ?? []
    }

    private func save(_ kept: [Stored]) {
        if kept.isEmpty {
            storage.write(nil)
        } else if let data = try? JSONEncoder().encode(kept) {
            storage.write(data)
        }
    }
}

extension NotificationKey: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = NotificationKey(base64: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a 256-bit key"))
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base64)
    }
}

/// Where the keys are kept: the Keychain in the app, memory in tests.
public protocol KeyStorage: Sendable {
    func read() -> Data?
    /// `nil` deletes.
    func write(_ data: Data?)
}

/// One Keychain item shared through the app group, readable after the phone's first unlock, so the
/// notification extension can decrypt while the phone is locked. Without the group's entitlement
/// (an unsigned Simulator build), it falls back to Ari's own Keychain.
struct KeychainKeyStorage: KeyStorage {
    let group: String

    private func query(shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "notifications",
            kSecAttrAccount as String: "keys",
        ]
        if shared { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    func read() -> Data? {
        for shared in [true, false] {
            var query = query(shared: shared)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
                return result as? Data
            }
        }
        return nil
    }

    func write(_ data: Data?) {
        for shared in [true, false] { SecItemDelete(query(shared: shared) as CFDictionary) }
        guard let data else { return }
        for shared in [true, false] {
            var item = query(shared: shared)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
        }
    }
}
