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

    public init(service: String = "io.github.akai-ito.ari.token") {
        self.service = service
    }

    public func token(for address: ServerAddress) throws -> Token? {
        var query = item(for: address)
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
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address.description,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

/// A Keychain call failed, with its `OSStatus`.
public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
}
