import XCTest

/// The conversation's basic interactions, driven as you would on the phone, against ito-core's
/// demo engine. Opt in: start `ito serve --engine demo`, connect Ari to it in the Simulator once,
/// then run the AriUITests scheme. Each test sends a message the demo engine answers in a known way
/// ("ask", "fail", "long", "busy").
@MainActor
final class InteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "io.github.akai-ito.ari")
        app.launch()
        XCTAssertTrue(composer.waitForExistence(timeout: 15), "the composer never appeared")
        // Let any turn left from an earlier test finish, so this one starts clean.
        _ = sendButton.waitForExistence(timeout: 30)
    }

    private var composer: XCUIElement {
        app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }
    private var sendButton: XCUIElement { app.buttons["Send"] }
    private var stopButton: XCUIElement { app.buttons["Stop"] }

    private func say(_ text: String) {
        composer.tap()
        composer.typeText(text)
        sendButton.tap()
    }

    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        return false
    }

    func testSendingClearsTheComposerAndShowsTheReply() {
        say("Hello from the interaction tests")
        XCTAssertTrue(
            app.staticTexts["Hello from the interaction tests"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            (composer.value as? String) ?? "", "Message Ari", "the composer kept the draft")
        XCTAssertFalse(app.staticTexts["Couldn't send"].exists)
        XCTAssertTrue(
            waitUntil {
                self.app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'demo engine'"))
                    .count > 0
            })
    }

    func testStopCutsAReplyAndSaysSo() {
        say("Write something long please")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        sleep(3)
        stopButton.tap()
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 15), "no Stopped tag")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10), "Stop never gave way to Send")
    }

    func testAFailureCanBeTriedAgainOnce() {
        say("Please fail")
        let retries = app.buttons.matching(identifier: "Try again")
        let before = retries.count
        XCTAssertTrue(
            waitUntil(20) { retries.count > before }, "no Try again for the new failure")
        // The newest failure is the last one; earlier ones may still offer theirs.
        retries.element(boundBy: retries.count - 1).tap()
        // The attempt fails again in the demo: its own failure offers Try again, the first doesn't.
        XCTAssertTrue(sendButton.waitForExistence(timeout: 20))
        XCTAssertLessThanOrEqual(retries.count, before + 1, "a failure offered Try again twice")
    }

    func testTappingAnOptionAnswersTheAskOnce() {
        say("Book a table and ask me which one")
        let clapham = app.buttons["Clapham"]
        XCTAssertTrue(clapham.waitForExistence(timeout: 20), "the ask's options never showed")
        XCTAssertEqual(stopButton.exists, true, "Stop should cancel the waiting ask")
        clapham.tap()
        XCTAssertTrue(waitUntil(5) { !self.app.buttons["Clapham"].exists }, "the options stayed")
        XCTAssertTrue(
            app.staticTexts["Clapham"].waitForExistence(timeout: 5), "your answer didn't show")
    }

    func testALinkInYourMessageOpensInPlace() {
        say("Have a look at https://example.com please")
        let link = app.links.firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "your message's address isn't a link")
        link.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "the page didn't open in place")
        close.tap()
    }

    func testAReplyCanBeCopiedAndSelected() {
        say("A short one please")
        let reply = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'demo engine'"))
            .element(boundBy: 0)
        XCTAssertTrue(reply.waitForExistence(timeout: 20))
        sleep(2)
        reply.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5), "no long-press menu")
        app.buttons["Select Text"].tap()
        XCTAssertTrue(app.textViews.count >= 1, "Select Text showed nothing to select")
        app.swipeDown(velocity: .fast)
    }

    func testTheTrailOpensAStep() {
        say("Please be busy for a moment")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 40), "the busy turn never ended")
        let step = app.buttons.containing(
            NSPredicate(
                format:
                    "label BEGINSWITH 'Read' OR label BEGINSWITH 'Ran' OR label BEGINSWITH 'Searched'"
            )
        ).element(boundBy: 0)
        XCTAssertTrue(step.waitForExistence(timeout: 5), "no step to open")
        step.tap()
        sleep(1)
        XCTAssertTrue(step.exists, "opening a step lost it")
    }

    func testSettingsOpensFromTheChatAndCloses() {
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "Settings didn't open")
        app.buttons["Done"].tap()
        XCTAssertTrue(waitUntil(5) { !self.app.buttons["Done"].exists }, "Settings didn't close")
    }
}
