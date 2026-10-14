import AriKit
import SwiftUI

#if DEBUG
    /// For trying Ari against a server without typing, in debug builds only: `ARI_SERVER` and
    /// `ARI_TOKEN` fill in and submit the connect screen, `ARI_SAY` sends a message once the stream
    /// is live, and `ARI_STOP_AFTER` taps Stop that many seconds later.
    enum DebugScript {
        static let environment = ProcessInfo.processInfo.environment

        static var connection: (address: String, token: String)? {
            guard let address = environment["ARI_SERVER"], let token = environment["ARI_TOKEN"]
            else {
                return nil
            }
            return (address, token)
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
