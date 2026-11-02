// What's wrong on the server that needs you: notifications it can't send, a mail or calendar
// account that keeps failing, a capability that needs setting up, memory not reaching its backup. Each shows until it's fixed, when
// it clears on its own; a blip that sorts itself out never shows.

/// One thing wrong on the server, with how to fix it.
public struct ServerProblem: Sendable, Equatable, Decodable, Identifiable {
    /// Stable while it lasts, such as `push` or `mail:outlook`.
    public let id: String
    public let area: ProblemArea
    /// One plain line, such as "Notifications can't be sent".
    public let title: String
    /// What's wrong and what it means for you.
    public let detail: String
    /// How to fix it, in plain steps.
    public let fix: String

    public init(id: String, area: ProblemArea, title: String, detail: String, fix: String) {
        self.id = id
        self.area = area
        self.title = title
        self.detail = detail
        self.fix = fix
    }
}

/// What a problem is about. An area Ari doesn't know shows plainly.
public struct ProblemArea: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let notifications = ProblemArea(rawValue: "notifications")
    public static let mail = ProblemArea(rawValue: "mail")
    public static let calendar = ProblemArea(rawValue: "calendar")
    /// Contacts can't be read or kept current.
    public static let contacts = ProblemArea(rawValue: "contacts")
    public static let capabilities = ProblemArea(rawValue: "capabilities")
    /// Memory isn't reaching its backup.
    public static let memory = ProblemArea(rawValue: "memory")
    public static let known = [notifications, mail, calendar, contacts, capabilities, memory]
}

/// What's wrong on the server changed: all of it, empty once nothing is.
public struct ProblemsChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let problems: [ServerProblem]
}

/// The answer to `GET /v0/problems`.
public struct ProblemList: Sendable, Equatable, Decodable {
    public let problems: [ServerProblem]
}
