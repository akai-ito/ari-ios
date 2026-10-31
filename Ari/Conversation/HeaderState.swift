import AriKit
import Observation
import SwiftUI

/// What the header shows, paced for reading: the status line and the character's pose. Each change
/// waits its turn, so a status can be read and a prop seen, however fast the turn moves; a newer one
/// replaces any still waiting. Nothing to say, stopping, going offline and coming to rest show at
/// once, and a connection blip shorter than two seconds never shows.
@MainActor @Observable
final class HeaderState {
    private(set) var poses = PoseHistory()
    private(set) var status: StatusText?
    /// The connection has been down for two seconds or more.
    private(set) var linkDown = false
    /// A turn was just stopped: "Stopped" shows for a moment.
    private(set) var stopped = false
    /// The subject and the day of what's at the top of the screen, for the title.
    private(set) var whereabouts: Whereabouts?

    @ObservationIgnored private var statusSince = Date.distantPast
    @ObservationIgnored private var poseSince = Date.distantPast

    /// How long each status stays, at least.
    static let statusHold = 1.0
    /// How long each pose stays, at least, so its prop can be seen.
    static let poseHold = 1.1

    /// Shows `next` once the current status has had its second. Then `latest` is asked again, so a
    /// status replaced in the meantime is skipped.
    func show(status next: StatusText?, latest: @escaping () -> StatusText?) {
        let wait = Self.statusHold - Date.now.timeIntervalSince(statusSince)
        guard wait > 0, status != nil, next != nil else {
            status = next
            statusSince = .now
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(wait))
            let now = latest()
            if now != status {
                status = now
                statusSince = .now
            }
        }
    }

    /// Shows `next` once the current pose has had its time, as for a status.
    func show(pose next: Pose, latest: @escaping () -> Pose) {
        let wait = Self.poseHold - Date.now.timeIntervalSince(poseSince)
        guard wait > 0, ![.stopping, .offline, .resting].contains(next) else {
            if next != poses.current { poseSince = .now }
            poses.set(next)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(wait))
            let now = latest()
            if now != poses.current {
                poses.set(now)
                poseSince = .now
            }
        }
    }

    /// You scrolled to somewhere under another subject or day.
    func show(whereabouts next: Whereabouts?) {
        guard let next, next != whereabouts else { return }
        whereabouts = next
    }

    /// You tapped Ari while it rests: it wakes, looks at you with a wiggle, and settles back into
    /// whatever `latest` says it should be doing.
    func nudge(then latest: @escaping () -> Pose) {
        guard poses.current == .resting else { return }
        poses.set(.noticed)
        poseSince = .now
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard poses.current == .noticed else { return }
            poses.set(latest())
            poseSince = .now
        }
    }

    /// The connection changed: down shows only if it's still down two seconds later.
    func notice(link: Session.Link, current: @escaping () -> Session.Link) {
        func isDown(_ link: Session.Link) -> Bool { link == .reconnecting || link == .offline }
        guard isDown(link) else {
            linkDown = false
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if isDown(current()) { linkDown = true }
        }
    }

    /// A turn was stopped: "Stopped" shows for a moment.
    func noticeStopped() {
        stopped = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            stopped = false
        }
    }
}
