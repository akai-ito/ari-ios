import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A file too big for one request, such as a recorded conversation from Voice Memos: checked against
/// what the server takes before anything is sent, and made into a ``BigUpload``.
public enum BigAttachment {
    /// Why a file can't go, in a sentence for the person.
    public struct Refusal: Error, Equatable {
        public let words: String

        public init(words: String) {
            self.words = words
        }
    }

    /// Whether a file goes in chunks: anything the simple upload doesn't take.
    public static func isBig(size: Int, limits: UploadLimits?) -> Bool {
        size > (limits?.simpleBytes ?? AttachmentMaker.largest)
    }

    /// The upload for `url`, sized and named, with a recording's length when the phone can tell; or
    /// why the server won't take it. Reads the file's size and length, never its bytes. Without the
    /// limits, as offline, the server says when it starts.
    public static func upload(
        for url: URL, limits: UploadLimits?,
        id: AttachmentID = AttachmentID(UUID().uuidString.lowercased())
    ) async -> Result<BigUpload, Refusal> {
        let name = url.lastPathComponent
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            return .failure(Refusal(words: "Couldn't read \(name)."))
        }
        let mediaType = mediaType(of: url)
        if let refusal = limits?.refusal(name: name, mediaType: mediaType, size: size) {
            return .failure(Refusal(words: refusal))
        }
        var duration: Double?
        if mediaType.hasPrefix("audio/"),
            let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite
        {
            duration = seconds
        }
        return .success(
            BigUpload(
                id: id, name: name, mediaType: mediaType, size: size,
                chunkLimit: limits?.chunkBytes ?? 16 * 1024 * 1024,
                durationSeconds: duration))
    }

    /// A file's media type from its name, as the server names the common recordings.
    public static func mediaType(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let audio: [String: String] = [
            "m4a": "audio/mp4", "mp3": "audio/mpeg", "wav": "audio/wav", "aac": "audio/aac",
            "caf": "audio/x-caf", "aif": "audio/aiff", "aiff": "audio/aiff", "flac": "audio/flac",
            "ogg": "audio/ogg", "opus": "audio/ogg", "amr": "audio/amr", "webm": "audio/webm",
        ]
        return audio[ext] ?? UTType(filenameExtension: ext)?.preferredMIMEType
            ?? "application/octet-stream"
    }
}
