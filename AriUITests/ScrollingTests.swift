import XCTest

/// The conversation's scrolling, against the demo engine: text stays at its margin, scrolling up
/// stops following and coming back to the end resumes it, and the keyboard leaves no blank space.
@MainActor
final class ScrollingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "io.github.akai-ito.ari")
        // Ito opens on the Desk; these drive the chat.
        app.launchEnvironment["ARI_PLACE"] = "chat"
        app.launch()
        // Send, or Talk where the server has a voice: either means the composer is ready.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label IN %@", ["Send", "Talk"])).firstMatch
                .waitForExistence(timeout: 30))
    }

    private var composer: XCUIElement {
        app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    func testFollowingStopsWhenYouScrollUpAndResumesAtTheEnd() {
        composer.tap()
        composer.typeText("Write something long please")
        app.buttons["Send"].tap()
        sleep(6)
        let pill = app.staticTexts["Kumo is writing"]
        XCTAssertFalse(pill.exists, "not following from the start")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        sleep(2)
        XCTAssertTrue(pill.exists, "scrolling up didn't stop the following")
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        sleep(2)
        XCTAssertFalse(pill.exists, "coming back to the end didn't resume the following")
        sleep(3)
        XCTAssertFalse(pill.exists, "the following stopped as the reply grew")
    }

    func testTextStaysAtItsMarginWithTheKeyboard() {
        composer.tap()
        composer.typeText("A draft long enough to wrap onto a second line and then a third one too")
        sleep(2)
        let margins = Set(
            app.staticTexts.allElementsBoundByIndex.suffix(40)
                .filter { $0.frame.minY > 120 && $0.frame.width > 200 }
                .map { Int($0.frame.minX) })
        // Messages sit at their 20-point margin and the trail 24 points further in, beside its rail;
        // drifting sideways showed as 0 and 24.
        XCTAssertFalse(margins.isEmpty)
        XCTAssertTrue(
            margins.isSubset(of: [20, 44]), "the conversation moved sideways: \(margins)")
        let top = composer.frame.minY
        let lowest =
            app.staticTexts.allElementsBoundByIndex.suffix(40)
            .filter { $0.frame.maxY < top && $0.frame.minY > 100 }
            .map(\.frame.maxY).max() ?? 0
        // A reply ends about 60 points above the composer, a failure's buttons about 140; the blank
        // space this guards against was most of the screen.
        XCTAssertLessThan(top - lowest, 220, "blank space above the composer")
        composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
    }
}
