import AriKit
import SwiftUI

#if DEBUG
    /// For trying Ari against a server without typing, in debug builds only: `ARI_SERVER` and
    /// `ARI_TOKEN` fill in and submit the connect screen, `ARI_SAY` sends a message once the stream
    /// is live, `ARI_STOP_AFTER` taps Stop that many seconds later, `ARI_DRAFT` fills in the
    /// composer (`\n` for a new line), `ARI_OPEN_TRAIL` opens every run and step on the trail,
    /// `ARI_PLACE` opens a tab (`chat`, `goals` or `library`), `ARI_SETTINGS` opens Settings (or, with
    /// `capabilities`, `capability:<id>`, `setup:<id>` or `model`, goes on to that place), `ARI_IN_MIND`
    /// opens In mind, `ARI_PAGE` opens a page of memory in the Library (`memory:people/alex`), and
    /// `ARI_NOTIFICATION_KEY` (base64) makes the notification key one a test can seal pushes with,
    /// `ARI_ATTACH` attaches files (paths, separated by commas) to the message `ARI_SAY` sends, and
    /// `ARI_OPEN_URL` opens Ari with a link, as the Camera does with a pairing code.
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
        static let opensInMind = environment["ARI_IN_MIND"] != nil
        static let page = environment["ARI_PAGE"].map(PageAddress.init(rawValue:))

        /// Where `ARI_SETTINGS` goes past the top of Settings.
        static var settingsPath: [SettingsRoute] {
            let value = environment["ARI_SETTINGS"] ?? ""
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts.first {
            case "capabilities": return [.capabilities]
            case "model": return [.model]
            case "capability" where parts.count == 2:
                return [.capabilities, .capability(CapabilityID(parts[1]))]
            case "setup" where parts.count == 2:
                return [.capabilities, .capability(CapabilityID(parts[1]), setup: true)]
            default: return []
            }
        }

        /// Adopts the test's notification key, so `xcrun simctl push` can send a sealed push.
        static func adoptNotificationKey(into store: NotificationStore) {
            guard
                let key = environment["ARI_NOTIFICATION_KEY"].flatMap(NotificationKey.init(base64:))
            else { return }
            store.adopt(key)
            _ = store.deviceID
        }
        static let place = environment["ARI_PLACE"]
        static let openURL = environment["ARI_OPEN_URL"].flatMap(URL.init(string:))

        static var attachments: [URL] {
            (environment["ARI_ATTACH"] ?? "").split(separator: ",").map {
                URL(filePath: String($0))
            }
        }

        static var draft: String? {
            environment["ARI_DRAFT"]?.replacingOccurrences(of: "\\n", with: "\n")
        }

        @MainActor
        static func run(
            in session: Session, send: @escaping (String) -> Void, stop: @escaping () -> Void
        ) async {
            guard let message = environment["ARI_SAY"] else { return }
            while session.link != .live {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(1))
            send(message)
            guard let delay = environment["ARI_STOP_AFTER"].flatMap(Double.init) else { return }
            try? await Task.sleep(for: .seconds(delay))
            stop()
        }
    }
#endif
