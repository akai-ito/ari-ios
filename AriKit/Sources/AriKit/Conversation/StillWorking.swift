import Foundation

/// A turn that has run a while with nothing new to show. No timer ends a turn: Kumo can be quiet
/// for minutes, such as while it writes a long document in one go, and you decide when it has gone
/// on too long. So once it's quiet, Ari says it's still working, and for how long, next to Stop.
public enum StillWorking {
    /// Nothing new for this long reads as quiet.
    public static let quietAfter: TimeInterval = 30
    /// A turn younger than this needs no clock.
    public static let after: TimeInterval = 60

    /// How long the turn has been going, such as "3 min" or "1 hr 5 min", once it's a minute old
    /// and nothing new has come for half a minute; `nil` before then.
    public static func elapsed(since started: Date, lastHeard: Date, at now: Date) -> String? {
        let running = now.timeIntervalSince(started)
        guard running >= after, now.timeIntervalSince(lastHeard) >= quietAfter else { return nil }
        return words(running)
    }

    /// "1 min", "59 min", "1 hr", "1 hr 5 min": whole minutes, as a glance needs.
    public static func words(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int(duration / 60))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}
