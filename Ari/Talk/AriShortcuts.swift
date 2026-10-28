#if os(iOS)
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
        }
    }
#endif
