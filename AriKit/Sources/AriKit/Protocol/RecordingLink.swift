import Foundation

/// A moment in a recording, as Kumo quotes it in a reply: a Markdown link such as
/// `[18:42](recording:<attachment>?t=18:42)`, which opens the transcript there.
public enum RecordingLink {
    public static let scheme = "recording"

    /// The recording and the moment a link points at; `nil` if it isn't a recording's link.
    public static func read(_ url: URL) -> (recording: AttachmentID, seconds: Double?)? {
        guard url.scheme == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = components?.path ?? ""
        guard !id.isEmpty else { return nil }
        let time = components?.queryItems?.first { $0.name == "t" }?.value
        return (AttachmentID(id), time.flatMap(seconds))
    }

    /// The recording a reply quotes first, if it quotes one.
    public static func first(in text: String) -> AttachmentID? {
        guard let start = text.range(of: "](\(scheme):") else { return nil }
        let id = text[start.upperBound...].prefix { !"?)# \n".contains($0) }
        return id.isEmpty ? nil : AttachmentID(String(id))
    }

    /// Seconds from `m:ss`, `h:mm:ss` or plain seconds.
    public static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else {
            return nil
        }
        return parts.compactMap(\.self).reduce(0) { $0 * 60 + $1 }
    }

    /// A moment as a clock: `6:02`, or `1:02:03` past an hour.
    public static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }
}
