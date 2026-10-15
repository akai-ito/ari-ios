import CryptoKit
import Foundation

/// Why the server pushed. A kind Ari doesn't know still shows its text.
public struct NotificationKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A reply finished.
    public static let reply = NotificationKind(rawValue: "reply")
    /// A turn failed.
    public static let failed = NotificationKind(rawValue: "failed")
    /// The agent asked you something.
    public static let ask = NotificationKind(rawValue: "ask")
    /// An ask still waiting after three hours; sent once.
    public static let reminder = NotificationKind(rawValue: "reminder")
    public static let known = [reply, failed, ask, reminder]
}

/// What a notification shows, once the notification service extension has decrypted it.
public struct PushNotification: Sendable, Equatable, Decodable {
    public var kind: NotificationKind
    /// Plain words: a reply's first line, "Couldn't finish: …", or the question.
    public var text: String
    public var turn: TurnID?
    /// A reply's message, so a tap opens the conversation there.
    public var message: MessageID?
    /// What's needed to answer an ask from the notification.
    public var ask: AskSummary?

    public struct AskSummary: Sendable, Equatable, Decodable {
        public var id: AskID
        /// The options' labels, in order.
        public var options: [String]
        public var allowsText: Bool
        /// A secret can't be typed into a notification safely: offer to open Ari instead.
        public var secret: Bool

        public init(id: AskID, options: [String], allowsText: Bool, secret: Bool) {
            self.id = id
            self.options = options
            self.allowsText = allowsText
            self.secret = secret
        }

        enum CodingKeys: String, CodingKey {
            case id, options, secret
            case allowsText = "allows_text"
        }
    }
}

/// The encrypted part of a push: the `ito` object beside `aps`.
public struct SealedNotification: Sendable, Equatable, Decodable {
    /// The scheme; 1 is AES-256-GCM with the device's id as additional data.
    public var v: Int
    /// The key that sealed it: the first 8 hex characters of the key's SHA-256.
    public var k: String
    /// The 12-byte nonce, base64.
    public var n: String
    /// The notification as UTF-8 JSON, encrypted, followed by the 16-byte tag, base64.
    public var c: String

    /// Reads it from a push's payload, as `UNNotificationContent.userInfo` gives it.
    public init?(payload: [AnyHashable: Any]) {
        guard let ito = payload["ito"], JSONSerialization.isValidJSONObject(ito),
            let data = try? JSONSerialization.data(withJSONObject: ito),
            let sealed = try? JSONDecoder().decode(SealedNotification.self, from: data)
        else { return nil }
        self = sealed
    }
}

/// A device's notification key: 256 random bits made on the phone, given to the server when the
/// device registers, and kept in the Keychain where the notification service extension can read it.
public struct NotificationKey: Sendable, Equatable {
    public let data: Data

    /// A new random key.
    public init() {
        data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public init?(data: Data) {
        guard data.count == 32 else { return nil }
        self.data = data
    }

    public init?(base64: String) {
        guard let data = Data(base64Encoded: base64) else { return nil }
        self.init(data: data)
    }

    public var base64: String { data.base64EncodedString() }

    /// Names the key in each notification: the first 8 hex characters of its SHA-256.
    public var id: String {
        SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

/// Why a sealed notification couldn't be read; the device then shows the push's plain words.
public enum NotificationError: Error, Equatable {
    case unknownScheme
    /// None of the device's keys sealed it, such as after the keys were replaced.
    case unknownKey
    /// It doesn't decrypt, or isn't a notification.
    case unreadable
}

extension SealedNotification {
    /// Decrypts it with whichever of `keys` sealed it.
    ///
    /// - Parameter device: This device's id, the additional data it was sealed with.
    public func open(with keys: [NotificationKey], device: String) throws(NotificationError)
        -> PushNotification
    {
        guard v == 1 else { throw .unknownScheme }
        guard let key = keys.first(where: { $0.id == k }) else { throw .unknownKey }
        guard let nonceData = Data(base64Encoded: n), let combined = Data(base64Encoded: c),
            combined.count >= 16, let nonce = try? AES.GCM.Nonce(data: nonceData),
            let box = try? AES.GCM.SealedBox(
                nonce: nonce, ciphertext: combined.dropLast(16), tag: combined.suffix(16)),
            let json = try? AES.GCM.open(
                box, using: SymmetricKey(data: key.data), authenticating: Data(device.utf8)),
            let notification = try? JSONDecoder().decode(PushNotification.self, from: json)
        else { throw .unreadable }
        return notification
    }
}
