import XCTest

/// Settings › Capabilities against a real 0.5 server, as you would on the phone. Opt in: run
/// ito-core's demo server with its test capabilities (`ITO_CAPABILITIES=test/support/capabilities
/// ito serve --engine demo`), connect Ari to it in the Simulator once, then run the AriUITests
/// scheme. A screenshot of each step is attached to the results.
@MainActor
final class CapabilitiesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "io.github.akai-ito.ari")
        app.launchEnvironment["ARI_SETTINGS"] = "1"
        app.launch()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(labelled prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Reports from off to on: switching on asks for its token, a wrong one is caught by Test
    /// connection, and the right one turns it on. The token never shows again.
    func testSettingUpReports() {
        let capabilities = button(labelled: "Capabilities")
        XCTAssertTrue(capabilities.waitForExistence(timeout: 15), "no Capabilities in Settings")
        snapshot("1-settings")
        capabilities.tap()

        let reports = button(labelled: "Reports")
        XCTAssertTrue(reports.waitForExistence(timeout: 10), "Reports isn't listed")
        XCTAssertTrue(app.staticTexts["Kumo's hands"].exists)
        snapshot("2-capabilities")
        reports.tap()

        let on = app.switches["On"]
        XCTAssertTrue(on.waitForExistence(timeout: 10))
        if (on.value as? String) == "1" {
            on.switches.firstMatch.tap()
            XCTAssertTrue(waitUntil { (on.value as? String) == "0" }, "Reports didn't switch off")
        }
        snapshot("3-reports-off")
        on.switches.firstMatch.tap()

        // On, but without a token: the sheet asks for it.
        let token = app.secureTextFields.firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 10), "switching on didn't ask for the token")
        token.tap()
        token.typeText("github_pat_wrong")
        app.buttons["Test connection"].tap()
        XCTAssertTrue(
            app.staticTexts["GitHub rejected that token."].waitForExistence(timeout: 10),
            "Test connection didn't catch the wrong token")
        snapshot("4-wrong-token")

        token.tap()
        token.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        token.typeText("github_pat_example")
        app.buttons["Test connection"].tap()
        XCTAssertTrue(app.staticTexts["It works"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["GitHub rejected that token."].exists)
        snapshot("5-token-works")
        app.buttons["Save"].tap()

        // Back on its page: on, with the token saved but never shown.
        // A labelled row reads as one element ("GitHub token, Saved"), not a text of its own.
        let saved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Saved' OR value CONTAINS 'Saved'"))
            .firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "the token isn't saved")
        XCTAssertEqual(on.value as? String, "1")
        snapshot("6-reports-on")
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        return false
    }
}
