#if os(iOS)
    import AppIntents
    import Observation

    /// "Hey Siri, talk to Ari": opens Ari and starts a call, so a walk can begin without touching
    /// the phone.
    struct CallAriIntent: AppIntent {
        static let title: LocalizedStringResource = "Call Ari"
        static let description = IntentDescription("Start a call with Ari, to talk hands-free.")
        static let supportedModes: IntentModes = .foreground

        @MainActor
        func perform() async throws -> some IntentResult {
            TalkRequests.shared.call()
            return .result()
        }
    }

    struct AriShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            // "Call Ari" alone could reach a contact of that name, so the others say it plainly.
            AppShortcut(
                intent: CallAriIntent(),
                phrases: [
                    "Talk to \(.applicationName)",
                    "Start a call with \(.applicationName)",
                    "Call \(.applicationName)",
                ],
                shortTitle: "Call Ari", systemImageName: "phone")
        }
    }

    /// Calls asked for from outside the chat, such as by Siri, for the chat to start once it's
    /// on screen.
    @Observable
    final class TalkRequests {
        static let shared = TalkRequests()
        /// Goes up with each request.
        private(set) var count = 0

        func call() { count += 1 }
    }
#endif
