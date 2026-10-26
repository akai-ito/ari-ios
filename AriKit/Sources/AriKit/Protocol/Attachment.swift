import Foundation

/// A photo or file you attached to a message. Its bytes never change, so they're fetched once
/// and kept.
public struct Attachment: Hashable, Sendable, Codable, Identifiable {
    public var id: AttachmentID
    public var kind: AttachmentKind
    /// The file's name, as uploaded.
    public var name: String
    public var mediaType: String
    /// In bytes.
    public var size: Int
    /// Images only, when the server could read them.
    public var width: Int?
    public var height: Int?

    public init(
        id: AttachmentID, kind: AttachmentKind, name: String, mediaType: String, size: Int,
        width: Int? = nil, height: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mediaType = mediaType
        self.size = size
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, size, width, height
        case mediaType = "media_type"
    }
}

/// The answer to `PUT /v0/attachments/{attachment}`.
public struct AttachmentResult: Sendable, Equatable, Decodable {
    public let attachment: Attachment
}

/// The body of `POST /v0/pair`.
public struct PairDevice: Sendable, Equatable, Codable {
    /// The code `ito pair` showed, with or without its dash.
    public let code: String
    public let deviceName: String

    public init(code: String, deviceName: String) {
        self.code = code
        self.deviceName = deviceName
    }

    enum CodingKeys: String, CodingKey {
        case code
        case deviceName = "device_name"
    }
}

/// The answer to `POST /v0/pair`: a token of this device's own.
public struct PairResult: Sendable, Equatable, Decodable {
    public let token: String
}

/// A photo or file you've attached that the server doesn't have yet.
public struct PendingAttachment: Sendable, Equatable, Identifiable {
    public let id: AttachmentID
    public let name: String
    public let mediaType: String
    public let bytes: Data

    public init(
        id: AttachmentID = AttachmentID(UUID().uuidString.lowercased()), name: String,
        mediaType: String, bytes: Data
    ) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.bytes = bytes
    }

    /// What it'll be once uploaded: an image if it's a photo the agent can see, audio if it's a
    /// recording.
    public var attachment: Attachment {
        let images = ["image/jpeg", "image/png", "image/gif", "image/webp"]
        let kind: AttachmentKind =
            images.contains(mediaType) ? .image : mediaType.hasPrefix("audio/") ? .audio : .file
        return Attachment(
            id: id, kind: kind, name: name, mediaType: mediaType, size: bytes.count)
    }

    struct About: Codable {
        let name: String
        let mediaType: String
    }
}
