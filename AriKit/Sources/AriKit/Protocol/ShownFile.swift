import Foundation

/// A file Kumo showed you, which keeps its id across versions.
public struct FileID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A file Kumo made or changed for you to look at, such as a PDF, with every version it showed.
/// Each version is an attachment whose bytes never change.
public struct ShownFile: Sendable, Equatable, Decodable, Identifiable {
    public let id: FileID
    /// The latest version's name.
    public let name: String
    /// Oldest first; the last is the latest.
    public let versions: [Version]

    public struct Version: Sendable, Equatable, Decodable {
        public let version: Int
        public let attachment: Attachment
        /// What changed since the version before, in Kumo's words.
        public let note: String?
        public let madeAt: Timestamp

        enum CodingKeys: String, CodingKey {
            case version, attachment, note
            case madeAt = "made_at"
        }
    }

    public var latest: Int { versions.last?.version ?? 1 }

    public func version(_ number: Int) -> Version? {
        versions.first { $0.version == number }
    }

    /// Where Kumo keeps that version for a mail draft, in its workspace: what an `ari:attach`
    /// points at.
    public func mailPath(_ number: Int) -> String? {
        version(number).map { "shown/\(id.rawValue)/v\($0.version)/\($0.attachment.name)" }
    }
}

public struct FileResult: Sendable, Equatable, Decodable {
    public let file: ShownFile
}

/// Every file Kumo showed you, newest change first.
public struct FileList: Sendable, Equatable, Decodable {
    public let files: [ShownFile]
}
