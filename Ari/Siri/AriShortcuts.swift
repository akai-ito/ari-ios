import AppIntents

struct AriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Never a calling word before Ari's name: Siri takes "Call Ari" or "Talk to Ari" to be
        // a contact, and phones them.
        AppShortcut(
            intent: CallAriIntent(),
            phrases: [
                "Talk mode in \(.applicationName)",
                "Walk with \(.applicationName)",
            ],
            shortTitle: "Talk to Ari", systemImageName: "waveform")
        // Not "Tell Ari": Siri takes that as a text to the contact named Ari.
        AppShortcut(
            intent: AskAriIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Note for \(.applicationName)",
            ],
            shortTitle: "Ask Ari", systemImageName: "bubble.left")
    }
}
