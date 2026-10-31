import AriKit
import Foundation
import Testing

/// Setup drawn from the manifest: a field's help read as steps, and which field guides it.
@Suite("Setup guides")
struct SetupGuideTests {
    @Test("help with numbered lines reads as an introduction, steps and notes")
    func readsSteps() {
        let guide = SetupGuide(
            help: """
                Mail and Calendar from your iCloud account. Apple doesn't let other apps sign in,
                so it takes an app password: about a minute.
                1. Open your Apple Account
                2. Sign-In and Security › App-Specific Passwords
                3) Create one called “Ito”,
                   then copy it
                4. Paste it here

                It works for Mail and Calendar both.
                """)
        #expect(
            guide.intro == [
                "Mail and Calendar from your iCloud account. Apple doesn't let other apps sign in, "
                    + "so it takes an app password: about a minute."
            ])
        #expect(
            guide.steps == [
                "Open your Apple Account", "Sign-In and Security › App-Specific Passwords",
                "Create one called “Ito”, then copy it", "Paste it here",
            ])
        #expect(guide.notes == ["It works for Mail and Calendar both."])
    }

    @Test("help without numbered lines is all introduction")
    func plainHelp() {
        let guide = SetupGuide(
            help: "Connect GitHub, so Reports files issues as you.\n\nVersion 1.2 or later.")
        #expect(
            guide.intro == [
                "Connect GitHub, so Reports files issues as you.", "Version 1.2 or later.",
            ])
        #expect(guide.steps.isEmpty && guide.notes.isEmpty)
        #expect(SetupGuide(help: nil) == SetupGuide())
    }

    @Test("a capability's guide comes from the field with steps, or with the link")
    func picksTheField() throws {
        let capability = try JSONDecoder().decode(
            Capability.self,
            from: Data(
                """
                { "id": "icloud", "kind": "hand", "title": "iCloud", "summary": "Mail and Calendar",
                  "state": "setup",
                  "fields": [
                    { "name": "apple_id", "title": "Apple Account", "kind": "text",
                      "description": "The address you sign in to Apple with." },
                    { "name": "app_password", "title": "App password", "kind": "secret",
                      "description": "It takes an app password.\\n1. Open your Apple Account\\n2. Paste it here",
                      "connect": { "kind": "link", "title": "Open Apple Account",
                                   "url": "https://account.apple.com/account/manage" } } ] }
                """.utf8))
        #expect(capability.deviceField == nil)
        #expect(capability.typedFields.map(\.name) == ["apple_id", "app_password"])
        #expect(capability.link?.title == "Open Apple Account")
        #expect(capability.guideField?.name == "app_password")
        #expect(capability.setupGuide.intro == ["It takes an app password."])
        #expect(capability.setupGuide.steps == ["Open your Apple Account", "Paste it here"])

        let outlook = try JSONDecoder().decode(
            Capability.self,
            from: Data(
                """
                { "id": "outlook", "kind": "hand", "title": "Outlook", "summary": "Mail", "state": "off",
                  "fields": [ { "name": "token", "title": "Microsoft account", "kind": "secret",
                    "description": "Ito asks to read and organise your mail.",
                    "connect": { "kind": "oauth_device", "title": "Open Microsoft" } } ] }
                """.utf8))
        #expect(outlook.deviceField?.name == "token")
        #expect(outlook.typedFields.isEmpty)
        #expect(outlook.link == nil && outlook.guideField == nil)
    }

    @Test("Test connection can say what it reached")
    func checkSummary() throws {
        let result = try JSONDecoder().decode(
            CheckResult.self,
            from: Data(#"{ "summary": "Connected: 2 addresses, 4 calendars." }"#.utf8))
        #expect(result.ok)
        #expect(result.summary == "Connected: 2 addresses, 4 calendars.")
    }
}
