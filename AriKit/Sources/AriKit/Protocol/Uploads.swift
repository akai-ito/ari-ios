import Foundation

/// The answer to `GET /v0/uploads`: what the server takes, said before anything is sent, and the big
/// uploads that haven't finished.
public struct UploadList: Sendable, Equatable, Codable {
    public var limits: UploadLimits
    public var transcription: Transcription
    public var uploads: [UploadStatus]
}

public struct UploadLimits: Sendable, Equatable, Codable {
    /// The largest file `PUT /v0/attachments/{attachment}` takes in one go.
    public var simpleBytes: Int
    /// The most one chunk of a big upload may hold.
    public var chunkBytes: Int
    public var kinds: [Kind]

    public struct Kind: Sendable, Equatable, Codable {
        public var kind: AttachmentKind
        public var maxBytes: Int
        public var mediaTypes: [String]

        public init(kind: AttachmentKind, maxBytes: Int, mediaTypes: [String]) {
            self.kind = kind
            self.maxBytes = maxBytes
            self.mediaTypes = mediaTypes
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case maxBytes = "max_bytes"
            case mediaTypes = "media_types"
        }
    }

    public init(simpleBytes: Int, chunkBytes: Int, kinds: [Kind]) {
        self.simpleBytes = simpleBytes
        self.chunkBytes = chunkBytes
        self.kinds = kinds
    }

    public func kind(_ kind: AttachmentKind) -> Kind? {
        kinds.first { $0.kind == kind }
    }

    /// Why the server won't take a file this big or of this type, in a sentence; `nil` if it will.
    public func refusal(name: String, mediaType: String, size: Int) -> String? {
        if size <= simpleBytes { return nil }
        let kind = Self.kind(of: mediaType)
        guard let limit = self.kind(kind), limit.mediaTypes.contains(mediaType) else {
            return "\(name) is \(Self.sizeWords(size)): your server takes a file of this type "
                + "up to \(Self.sizeWords(simpleBytes))."
        }
        guard size <= limit.maxBytes else {
            return "\(name) is \(Self.sizeWords(size)): your server takes \(Self.plural(kind)) "
                + "up to \(Self.sizeWords(limit.maxBytes))."
        }
        return nil
    }

    /// What kind of attachment a media type makes, as the server sorts them.
    public static func kind(of mediaType: String) -> AttachmentKind {
        if mediaType.hasPrefix("audio/") { return .audio }
        if mediaType.hasPrefix("image/") { return .image }
        return .file
    }

    static func plural(_ kind: AttachmentKind) -> String {
        switch kind {
        case .audio: "recordings"
        case .image: "photos"
        default: "documents"
        }
    }

    /// A size as people say it: "74 MB", "1 GB".
    public static func sizeWords(_ bytes: Int) -> String {
        bytes.formatted(.byteCount(style: .memory, allowedUnits: [.kb, .mb, .gb]))
    }

    enum CodingKeys: String, CodingKey {
        case kinds
        case simpleBytes = "simple_bytes"
        case chunkBytes = "chunk_bytes"
    }
}

/// Whether the server can transcribe a recording now, and the line to show before one is sent.
public struct Transcription: Sendable, Equatable, Codable {
    /// `ready`, `loading` or `unavailable`.
    public var state: String
    public var reason: String?
    public var languages: [String]
    /// About the other people in a recording.
    public var consent: String

    public var isReady: Bool { state == "ready" }
}

/// A big upload as the server has it.
public struct UploadStatus: Sendable, Equatable, Codable {
    public var id: AttachmentID
    public var name: String
    public var mediaType: String
    public var kind: AttachmentKind
    public var size: Int
    /// How many bytes from the start the server has; the next chunk starts here.
    public var received: Int
    /// `receiving`, or `finished` once it's an attachment.
    public var state: String
    public var attachment: Attachment?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, size, received, state, attachment
        case mediaType = "media_type"
    }
}

/// The body of `POST /v0/uploads`.
public struct CreateUpload: Sendable, Equatable, Codable {
    public var id: AttachmentID
    public var name: String
    public var mediaType: String
    public var size: Int

    public init(id: AttachmentID, name: String, mediaType: String, size: Int) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.size = size
    }

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case mediaType = "media_type"
    }
}

/// The answer to every big-upload route but finishing.
public struct UploadResult: Sendable, Equatable, Codable {
    public var upload: UploadStatus
}
