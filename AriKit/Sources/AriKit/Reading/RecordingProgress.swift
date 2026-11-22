import Foundation

/// Where your newest recording in a conversation stands while it's on its way, for the top of its
/// thread: going up, then waiting its turn and being transcribed. Once it's transcribed, failed or
/// refused, there's nothing to say there: its card on your message says the rest.
public enum RecordingProgress: Equatable, Sendable {
    /// Going up: how far, from 0 to 1, when it goes in chunks.
    case uploading(Double?)
    /// Up, and waiting its turn to be transcribed.
    case waiting
    /// Being transcribed: how far, from 0 to 1, when its length is known.
    case transcribing(Double?)

    /// The line, such as "Uploading your recording · 42%".
    public var line: String {
        switch self {
        case .uploading(let fraction):
            "Uploading your recording" + (fraction.map { " · \(Self.percent($0))" } ?? "")
        case .waiting:
            "Waiting to transcribe your recording"
        case .transcribing(let fraction):
            "Transcribing your recording" + (fraction.map { " · \(Self.percent($0))" } ?? "")
        }
    }

    /// The newest of your recordings in `conversation` still on its way, if any.
    ///
    /// - Parameters:
    ///   - uploads: The big uploads this phone has, by id.
    ///   - sent: How much of an upload has gone, with the chunk going now; what the server has
    ///     confirmed unless said.
    ///   - recordings: Each recording as the server last said.
    public init?(
        in conversation: Conversation, uploads: [AttachmentID: BigUpload],
        sent: (BigUpload) -> Int = { $0.received }, recordings: [AttachmentID: Recording]
    ) {
        for entry in conversation.entries.reversed() where entry.role == .user {
            // A call's turns carry their audio too, but aren't recordings you sent.
            guard entry.spoken == nil else { continue }
            for attachment in entry.attachments.reversed() where attachment.kind == .audio {
                let upload = uploads[attachment.id]
                if let progress = Self.progress(
                    upload: upload, sent: upload.map(sent),
                    recording: recordings[attachment.id],
                    isSending: entry.delivery == .sending)
                {
                    self = progress
                    return
                }
            }
        }
        return nil
    }

    private static func progress(
        upload: BigUpload?, sent: Int?, recording: Recording?, isSending: Bool
    ) -> RecordingProgress? {
        if let upload {
            switch upload.state {
            case .sending:
                guard upload.size > 0 else { return .uploading(nil) }
                return .uploading(Double(sent ?? upload.received) / Double(upload.size))
            case .refused:
                return nil
            case .finished:
                break
            }
        }
        guard let recording else {
            // Just sent from here: the server says how it stands once it has the message.
            guard isSending else { return nil }
            return upload == nil ? .uploading(nil) : .waiting
        }
        switch recording.state {
        case .queued: return .waiting
        case .transcribing: return .transcribing(recording.progress?.fraction)
        default: return nil
        }
    }

    /// Whole percent, rounded down, and never 100 while it's still going.
    private static func percent(_ fraction: Double) -> String {
        "\(min(99, max(0, Int((fraction * 100).rounded(.down)))))%"
    }
}
