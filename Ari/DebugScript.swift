import AriKit
import SwiftUI

#if DEBUG
    /// For trying Ari against a server without typing, in debug builds only: `ARI_SERVER` and
    /// `ARI_TOKEN` fill in and submit the connect screen, `ARI_SAY` sends a message once the stream
    /// is live, `ARI_STOP_AFTER` taps Stop that many seconds later, `ARI_DRAFT` fills in the
    /// composer (`\n` for a new line), `ARI_OPEN_TRAIL` opens every run and step on the trail,
    /// `ARI_PLACE` opens a tab (`chat`, `goals` or `library`), `ARI_SETTINGS` opens Settings, and
    /// `ARI_NOTIFICATION_KEY` (base64) makes the notification key one a test can seal pushes with.
    enum DebugScript {
        static let environment = ProcessInfo.processInfo.environment

        static var connection: (address: String, token: String)? {
            guard let address = environment["ARI_SERVER"], let token = environment["ARI_TOKEN"]
            else {
                return nil
            }
            return (address, token)
        }

        static let opensTrail = environment["ARI_OPEN_TRAIL"] != nil
        static let opensSettings = !(environment["ARI_SETTINGS"] ?? "").isEmpty

        /// Adopts the test's notification key, so `xcrun simctl push` can send a sealed push.
        static func adoptNotificationKey(into store: NotificationStore) {
            guard
                let key = environment["ARI_NOTIFICATION_KEY"].flatMap(NotificationKey.init(base64:))
            else { return }
            store.adopt(key)
            _ = store.deviceID
        }
        static let place = environment["ARI_PLACE"]

        static var draft: String? {
            environment["ARI_DRAFT"]?.replacingOccurrences(of: "\\n", with: "\n")
        }

        @MainActor
        static func run(in session: Session, stop: @escaping () -> Void) async {
            guard let message = environment["ARI_SAY"] else { return }
            while session.link != .live {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(1))
            session.send(message)
            guard let delay = environment["ARI_STOP_AFTER"].flatMap(Double.init) else { return }
            try? await Task.sleep(for: .seconds(delay))
            stop()
        }
    }
#endif
