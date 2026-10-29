import Foundation

/// A capability's permanent id, such as `reports` or `time`.
public struct CapabilityID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Something you can switch on: a domain of your life, such as Time, or one of Ari's hands, such
/// as Reports. The server describes each one fully, so Settings can draw any capability, including
/// ones this version of Ari has never heard of.
public struct Capability: Sendable, Equatable, Identifiable, Codable {
    public let id: CapabilityID
    /// A domain or a hand. Ari lists one it doesn't know with the hands.
    public let kind: CapabilityKind
    public let title: String
    /// One line on what it does, shown under its title and when Ari offers it.
    public let summary: String
    /// An SF Symbol name for its row, if the server suggests one.
    public let symbol: String?
    public let version: String?
    public let state: CapabilityState
    /// Why it needs you, in the server's words, such as "iCloud rejected the password".
    public let detail: String?
    /// What setting it up asks for, with the values saved so far. Passwords never come back, only
    /// whether one is set.
    public let fields: [SetupField]
    /// The hosts it reaches, such as `caldav.icloud.com`, shown before you switch it on.
    public let hosts: [String]
    /// The folders on the server it uses.
    public let folders: [String]

    public init(
        id: CapabilityID, kind: CapabilityKind, title: String, summary: String,
        symbol: String? = nil, version: String? = nil, state: CapabilityState,
        detail: String? = nil, fields: [SetupField] = [], hosts: [String] = [],
        folders: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.version = version
        self.state = state
        self.detail = detail
        self.fields = fields
        self.hosts = hosts
        self.folders = folders
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CapabilityID.self, forKey: .id)
        kind = try container.decodeIfPresent(CapabilityKind.self, forKey: .kind) ?? .hand
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        state = try container.decode(CapabilityState.self, forKey: .state)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        fields = try container.decodeIfPresent([SetupField].self, forKey: .fields) ?? []
        let uses = try container.decodeIfPresent(Uses.self, forKey: .uses)
        hosts = uses?.hosts ?? []
        folders = uses?.folders ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(fields, forKey: .fields)
        try container.encode(Uses(hosts: hosts, folders: folders), forKey: .uses)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, symbol, version, state, detail, fields, uses
    }

    /// What it reaches: `uses: { hosts, folders }`.
    struct Uses: Codable {
        var hosts: [String]?
        var folders: [String]?
    }

    /// Whether everything setup requires has a value.
    public var isSetUp: Bool { fields.allSatisfy { !$0.required || $0.hasValue } }
}

/// Whether a capability is a domain of your life or one of Ari's hands.
public struct CapabilityKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A topic of your life, such as Time or Messages, fed by one or more sources.
    public static let domain = CapabilityKind(rawValue: "domain")
    /// A way Ari acts, such as the Browser or Reports.
    public static let hand = CapabilityKind(rawValue: "hand")
    public static let known = [domain, hand]
}

/// Where a capability stands. Ari shows a state it doesn't know as off.
public struct CapabilityState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let off = CapabilityState(rawValue: "off")
    /// Switched on, but setup is missing something it needs.
    public static let setup = CapabilityState(rawValue: "setup")
    public static let on = CapabilityState(rawValue: "on")
    /// It stopped working and needs you, with the reason in `detail`.
    public static let needsYou = CapabilityState(rawValue: "needs_you")
    public static let known = [off, setup, on, needsYou]
}

/// One thing setting up a capability asks for.
public struct SetupField: Sendable, Equatable, Identifiable, Codable {
    /// The key its value is saved under.
    public let name: String
    public let label: String
    public let kind: SetupFieldKind
    /// A line of help under the field, such as where to make an app-specific password.
    public let help: String?
    public let required: Bool
    /// For a choice, what you can pick from.
    public let options: [Option]
    /// The value saved so far. Never a password.
    public let value: SetupValue?
    /// For a password, whether one is saved.
    public let set: Bool
    /// How to fill it without typing it in: through the provider, or from the page that makes one.
    public let connect: Connect?

    public var id: String { name }

    /// A way to fill a field without typing it: GitHub's device flow, say, or a link to the page
    /// where the provider makes a key.
    public struct Connect: Sendable, Equatable, Codable {
        public let kind: ConnectKind
        /// What the button says, such as "Connect GitHub".
        public let title: String
        /// `link` only: the page that makes one, filled in where the provider allows it.
        public let url: URL?

        public init(kind: ConnectKind, title: String, url: URL? = nil) {
            self.kind = kind
            self.title = title
            self.url = url
        }
    }

    public struct Option: Sendable, Equatable, Codable {
        public let value: String
        public let label: String

        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }

        public init(from decoder: any Decoder) throws {
            // An option is either `{ "value", "label" }` or just its text.
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.init(value: text, label: text)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let value = try container.decode(String.self, forKey: .value)
            self.init(
                value: value,
                label: try container.decodeIfPresent(String.self, forKey: .label) ?? value)
        }
    }

    public init(
        name: String, label: String, kind: SetupFieldKind, help: String? = nil,
        required: Bool = true, options: [Option] = [], value: SetupValue? = nil, set: Bool = false,
        connect: Connect? = nil
    ) {
        self.name = name
        self.label = label
        self.kind = kind
        self.help = help
        self.required = required
        self.options = options
        self.value = value
        self.set = set
        self.connect = connect
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? name
        kind = try container.decode(SetupFieldKind.self, forKey: .kind)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        required = !(try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false)
        options = try container.decodeIfPresent([Option].self, forKey: .options) ?? []
        value = try container.decodeIfPresent(SetupValue.self, forKey: .value)
        set = try container.decodeIfPresent(Bool.self, forKey: .set) ?? (value != nil)
        connect = try container.decodeIfPresent(Connect.self, forKey: .connect)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(help, forKey: .help)
        if !required { try container.encode(true, forKey: .optional) }
        if !options.isEmpty { try container.encode(options, forKey: .options) }
        if kind == .secret {
            try container.encode(set, forKey: .set)
        } else {
            try container.encodeIfPresent(value, forKey: .value)
        }
        try container.encodeIfPresent(connect, forKey: .connect)
    }

    enum CodingKeys: String, CodingKey {
        case name, kind, optional, options, value, set, connect
        case label = "title"
        case help = "description"
    }

    /// Whether something is saved for it.
    public var hasValue: Bool {
        if kind == .secret { return set }
        switch value {
        case .text(let text): return !text.isEmpty
        case .toggle: return true
        case nil: return kind == .toggle
        }
    }
}

/// How a field connects. Ari shows a kind it doesn't know as the field alone.
public struct ConnectKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Through the provider: a code you approve on its page, where you're already signed in. The
    /// value goes to the server, never through the phone.
    public static let oauthDevice = ConnectKind(rawValue: "oauth_device")
    /// The page where the provider makes one, to paste here.
    public static let link = ConnectKind(rawValue: "link")
    public static let known = [oauthDevice, link]
}

/// The answer to `POST /v0/capabilities/{id}/connect`: the code to approve, and where.
public struct CapabilityConnection: Sendable, Equatable, Decodable {
    /// Shown as it is, such as "WDJB-MJHT".
    public let code: String
    /// The provider's page to approve it on.
    public let url: URL
    public let expiresAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case code, url
        case expiresAt = "expires_at"
    }
}

/// How a setup field is drawn. Ari draws a kind it doesn't know as text.
public struct SetupFieldKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let text = SetupFieldKind(rawValue: "text")
    /// A password or token: typed once, sent once, never shown again.
    public static let secret = SetupFieldKind(rawValue: "secret")
    public static let toggle = SetupFieldKind(rawValue: "toggle")
    public static let choice = SetupFieldKind(rawValue: "choice")
    public static let known = [text, secret, toggle, choice]
}

/// A setup field's value: text (also a choice's value or a password) or a toggle.
public enum SetupValue: Sendable, Equatable, Codable {
    case text(String)
    case toggle(Bool)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let on = try? container.decode(Bool.self) {
            self = .toggle(on)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .toggle(let on): try container.encode(on)
        }
    }
}

/// `GET /v0/capabilities`.
public struct CapabilityList: Sendable, Equatable, Codable {
    public let capabilities: [Capability]
}

/// The body of `PUT /v0/capabilities/{id}`.
public struct SwitchCapability: Sendable, Equatable, Codable {
    public let on: Bool

    public init(on: Bool) { self.on = on }
}

/// The body of `PUT /v0/capabilities/{id}/setup` and `POST /v0/capabilities/{id}/check`. Setup
/// merges: a password left out keeps the one saved.
public struct CapabilitySetup: Sendable, Equatable, Codable {
    public let values: [String: SetupValue]

    public init(values: [String: SetupValue]) { self.values = values }
}

/// What *Test connection* found: nothing when the values work, or the problem.
public struct CheckResult: Sendable, Equatable, Codable {
    /// What's wrong, in the server's words, such as "iCloud rejected the password".
    public let problem: String?

    public init(problem: String? = nil) {
        self.problem = problem
    }

    public var ok: Bool { problem == nil }
}
