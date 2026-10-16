import Foundation
import Security

/// Where Ari keeps the token for each server.
public protocol TokenStore: Sendable {
    func token(for address: ServerAddress) throws -> Token?
    func save(_ token: Token, for address: ServerAddress) throws
    func delete(for address: ServerAddress) throws
}

/// The token in the Keychain, readable once the device has been unlocked after a restart, never
/// synced and never moved to another device in a backup.
public struct KeychainTokenStore: TokenStore {
    let service: String
    /// The app group whose extensions may read the token too, such as the share extension; `nil`
    /// keeps it to the app.
    let accessGroup: String?

    public init(service: String = "io.github.akai-ito.ari.token", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func token(for address: ServerAddress) throws -> Token? {
        if let token = try read(item(for: address)) { return token }
        guard accessGroup != nil else { return nil }
        // A token saved before it was shared moves into the group, where the extensions find it.
        var unshared = item(for: address)
        unshared[kSecAttrAccessGroup as String] = nil
        guard let token = try read(unshared) else { return nil }
        SecItemDelete(unshared as CFDictionary)
        do {
            try save(token, for: address)
        } catch {
            try KeychainTokenStore(service: service).save(token, for: address)
        }
        return token
    }

    private func read(_ item: [String: Any]) throws -> Token? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
            let secret = String(data: data, encoding: .utf8)
        else { throw KeychainError(status: status) }
        return Token(secret)
    }

    public func save(_ token: Token, for address: ServerAddress) throws {
        let data = Data(token.secret.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(item(for: address) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = item(for: address)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public func delete(for address: ServerAddress) throws {
        let status = SecItemDelete(item(for: address) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func item(for address: ServerAddress) -> [String: Any] {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address.description,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup { item[kSecAttrAccessGroup as String] = accessGroup }
        return item
    }
}

/// A Keychain call failed, with its `OSStatus`.
public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
}
