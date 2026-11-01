import Foundation

// Where memory is backed up off the server: through Ito Memory, Ito's GitHub app, to a private
// repository, or to a remote set on the server with `ito memory remote`.

/// The answer to `GET`, `POST` and `DELETE /v0/memory/backup`.
public struct MemoryBackup: Sendable, Equatable, Decodable {
    public let state: BackupState
    /// `connecting`: the code to enter, shown as it is, such as "WDJB-MJHT".
    public let code: String?
    /// `connecting`: GitHub's page to enter it on.
    public let url: URL?
    /// `connecting`: when the code stops working.
    public let expiresAt: Timestamp?
    /// The repository memory goes to, as `owner/name`, such as `octo-person/ito-thread`.
    public let repository: String?
    public let repositoryURL: URL?
    /// The server made the repository, private, when it found none.
    public let created: Bool
    /// `installing`: where to install Ito Memory, or to add the repository to it.
    public let installURL: URL?
    /// `installing`: GitHub's page opens with the repository already chosen.
    public let repositoryChosen: Bool
    /// `installing`: there may be no ito-thread yet, and the server can't make one until the app is
    /// installed: make it here first.
    public let newRepositoryURL: URL?
    /// Where `ito memory remote` points, when that's how memory is backed up.
    public let remote: String?
    /// When memory last reached the backup.
    public let pushedAt: Timestamp?
    /// `stopped`: what's wrong. `off`: why connecting didn't finish.
    public let problem: String?

    /// Backed up through the GitHub app, rather than a remote set on the server.
    public var isThroughApp: Bool { repository != nil }

    enum CodingKeys: String, CodingKey {
        case state, code, url, repository, created, remote, problem
        case expiresAt = "expires_at"
        case repositoryURL = "repository_url"
        case installURL = "install_url"
        case repositoryChosen = "repository_chosen"
        case newRepositoryURL = "new_repository_url"
        case pushedAt = "pushed_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(BackupState.self, forKey: .state)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        expiresAt = try container.decodeIfPresent(Timestamp.self, forKey: .expiresAt)
        repository = try container.decodeIfPresent(String.self, forKey: .repository)
        repositoryURL = try container.decodeIfPresent(URL.self, forKey: .repositoryURL)
        created = try container.decodeIfPresent(Bool.self, forKey: .created) ?? false
        installURL = try container.decodeIfPresent(URL.self, forKey: .installURL)
        repositoryChosen =
            try container.decodeIfPresent(Bool.self, forKey: .repositoryChosen) ?? false
        newRepositoryURL = try container.decodeIfPresent(URL.self, forKey: .newRepositoryURL)
        remote = try container.decodeIfPresent(String.self, forKey: .remote)
        pushedAt = try container.decodeIfPresent(Timestamp.self, forKey: .pushedAt)
        problem = try container.decodeIfPresent(String.self, forKey: .problem)
    }
}

/// How memory's backup is going. Ari shows a state it doesn't know as off.
public struct BackupState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Memory is only on the server.
    public static let off = BackupState(rawValue: "off")
    /// Waiting for you to enter the code on GitHub.
    public static let connecting = BackupState(rawValue: "connecting")
    /// Waiting for Ito Memory to be installed on the repository.
    public static let installing = BackupState(rawValue: "installing")
    /// Memory is pushed after each change.
    public static let on = BackupState(rawValue: "on")
    /// Backing up needs you; `problem` says why.
    public static let stopped = BackupState(rawValue: "stopped")
    public static let known = [off, connecting, installing, on, stopped]

    /// Part way through backing up to GitHub, so worth following.
    public var isUnderway: Bool { self == .connecting || self == .installing }
}
