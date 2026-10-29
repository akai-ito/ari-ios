// What Ari sends with each command, and what the server answers.

/// `GET /.well-known/ito`, before there is a token: the protocol versions the server speaks.
public struct Discovery: Sendable, Equatable, Decodable {
    /// Always "ito".
    public let product: String
    public let versions: [ProtocolVersion]

    enum CodingKeys: String, CodingKey {
        case product
        case versions = "protocol"
    }
}

/// `GET /v0/server`: the token is accepted, and this is who answered. Ari keeps it, so it can open
/// on the same server next time.
public struct ServerInfo: Sendable, Equatable, Codable {
    /// The server's name, usually its host name.
    public let name: String
    /// The version of Ito it runs.
    public let version: String
    /// The protocol version of this route.
    public let protocolVersion: ProtocolVersion
    public let agent: Agent

    /// What's set up on the server, so Settings can say what isn't yet.
    public let setup: Setup?

    public struct Agent: Sendable, Equatable, Codable {
        /// What the agent is called; Ari until you choose another name.
        public let name: String
        /// The model the agent last ran on, such as `demo` for the demo engine; absent until it has
        /// run once.
        public let model: String?
        /// How hard it thinks, such as `medium`: the chosen effort, or the model's default.
        public let effort: String?
        /// How the engine is signed in, as of its last session.
        public let account: Account?

        public struct Account: Sendable, Equatable, Codable {
            /// `chatgpt`, `api_key` or `other`.
            public let kind: String
            public let plan: String?
            /// Only the domain of the account's email address.
            public let emailDomain: String?

            enum CodingKeys: String, CodingKey {
                case kind, plan
                case emailDomain = "email_domain"
            }
        }
    }

    /// The capabilities that are on, with their versions.
    public let capabilities: [CapabilityVersion]?

    public struct Setup: Sendable, Equatable, Codable {
        /// `ito push setup` has run.
        public let notifications: Bool
        /// Memory is backed up: `ito memory remote` has set where to push it, and the last day's
        /// pushes went through.
        public let memoryBackup: Bool?

        enum CodingKeys: String, CodingKey {
            case notifications
            case memoryBackup = "memory_backup"
        }
    }

    public struct CapabilityVersion: Sendable, Equatable, Codable {
        public let id: CapabilityID
        public let version: String
    }

    enum CodingKeys: String, CodingKey {
        case name, version, agent, setup, capabilities
        case protocolVersion = "protocol"
    }
}

/// The body of `POST /v0/messages`. Sending the same id again is always safe: it returns the same
/// message and changes nothing.
public struct SendMessage: Sendable, Equatable, Codable {
    /// The random UUID Ari made when you tapped Send: the message's id and its retry key.
    public let id: MessageID
    public let text: String
    /// Photos and files already uploaded, in order. The text may then be empty.
    public let attachments: [AttachmentID]?

    public init(id: MessageID, text: String, attachments: [AttachmentID] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments.isEmpty ? nil : attachments
    }
}

/// The answer to `POST /v0/messages`: the message, once it is on the server's disk.
public struct MessageResult: Sendable, Equatable, Decodable {
    public let message: Message
}

/// The answer to `GET /v0/messages?before=…`: older messages, oldest first.
public struct MessagePage: Sendable, Equatable, Decodable {
    public let messages: [Message]
    /// Every step from the first of these messages up to the message the page ends before.
    public let steps: [Step]
    /// Every ask in the same span.
    public let asks: [Ask]
    /// Every call that started in the same span.
    public let calls: [Call]
    /// The topics Ari marked on these messages.
    public let topics: [Topic]
    /// Whether even older messages exist.
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case messages, steps, asks, calls, topics
        case hasMore = "has_more"
    }
}

/// The answer to a Stop: 202 while the turn is stopping, 200 if it had already ended.
public struct StopResult: Sendable, Equatable, Decodable {
    public let turn: TurnID
    public let state: StopState
    /// How the turn ended, when it already had.
    public let outcome: Outcome?
}

/// The answer to `POST /v0/turns/{turn}/retry`: the new attempt. Repeating the request returns the same
/// one.
public struct RetryResult: Sendable, Equatable, Decodable {
    /// The new attempt.
    public let turn: TurnID
    /// The failed turn.
    public let retryOf: TurnID

    enum CodingKeys: String, CodingKey {
        case turn
        case retryOf = "retry_of"
    }
}

/// The body of any refused command.
public struct ErrorResult: Sendable, Equatable, Decodable {
    public let error: ServerError
}

/// Which Apple push service a build talks to: builds from Xcode use the sandbox, TestFlight and
/// the App Store production.
public enum PushEnvironment: String, Sendable, Codable {
    case sandbox, production
}

/// The body of `PUT /v0/devices/{device}`.
public struct RegisterDevice: Sendable, Equatable, Codable {
    /// The device token from Apple's push service, in lowercase hex.
    public let apnsToken: String
    public let environment: PushEnvironment
    /// The device's notification key, base64; the server encrypts each notification with it.
    public let notificationKey: String

    public init(apnsToken: String, environment: PushEnvironment, notificationKey: NotificationKey) {
        self.apnsToken = apnsToken
        self.environment = environment
        self.notificationKey = notificationKey.base64
    }

    enum CodingKeys: String, CodingKey {
        case environment
        case apnsToken = "apns_token"
        case notificationKey = "notification_key"
    }
}

/// The answer to `PUT /v0/devices/{device}`.
public struct DeviceResult: Sendable, Equatable, Decodable {
    public let device: Device

    public struct Device: Sendable, Equatable, Decodable {
        public let id: String
        public let environment: PushEnvironment
        /// Names the key the server now encrypts with: the first 8 hex characters of its SHA-256.
        public let keyID: String
        public let registeredAt: Timestamp

        enum CodingKeys: String, CodingKey {
            case id, environment
            case keyID = "key_id"
            case registeredAt = "registered_at"
        }
    }
}

/// The body of `PUT /v0/devices/{device}/presence`.
public struct Presence: Sendable, Equatable, Codable {
    public let looking: Bool

    public init(looking: Bool) {
        self.looking = looking
    }
}
