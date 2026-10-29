import AppIntents
import Observation

/// Opens Ari and starts a call, so a walk can begin without touching the phone: from Siri, the
/// Action button, Control Centre or the Lock Screen. Ari's controls build it too, to name it;
/// it runs in the app.
struct CallAriIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Ari"
    static let description = IntentDescription("Start a call with Ari, to talk hands-free.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        TalkRequests.shared.call()
        return .result()
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
