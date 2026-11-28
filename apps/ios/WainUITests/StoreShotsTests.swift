import UIKit
import XCTest

/// The App Store screenshots, against the server `scripts/store_seed.py` seeds, on an
/// iPhone 17 Pro Max (1320 × 2868) and a 13-inch iPad (2064 × 2752), the two sizes the store asks
/// for. Paper's Store page frames them. Export the shots with `xcrun xcresulttool export attachments`.
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_TOKEN=… \
///   xcodebuild test -only-testing:WainUITests/StoreShotsTests …
final class StoreShotsTests: XCTestCase {
    func testStoreShots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL and TEST_RUNNER_WAIN_TOKEN")
        }
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            guard alert.buttons["Don’t Allow"].exists else { return false }
            alert.buttons["Don’t Allow"].tap()
            return true
        }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""]
        app.launch()
        // The link a pairing QR carries: typing a 64-character token drops keys in the simulator.
        var link = URLComponents(string: "wain://connect")!
        link.queryItems = [.init(name: "url", value: url), .init(name: "token", value: token), .init(name: "name", value: "MacBook Pro")]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 10), "the link opened no add sheet")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["machines"].waitForExistence(timeout: 15))
        sleep(3)
        app.tap()  // lets the interruption monitor answer
        // Both cards come from live turns, so wait for the question to land.
        XCTAssertTrue(text(app, "Should the dark mode toggle").waitForExistence(timeout: 60), "no question card")
        let iPad = UIDevice.current.userInterfaceIdiom == .pad
        // The sidebar beside each screen, rather than the tab bar over it.
        let toggle = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'sidebar' OR label CONTAINS[c] 'sidebar'")).firstMatch
        if iPad {
            // The tab bar's own sidebar glyph, at its left end, where no query reaches it.
            if toggle.exists { toggle.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.309, dy: 0.039)).tap() }
        }
        sleep(2)
        snap(app, "store-1-home")

        let any = app.descendants(matching: .any)
        if iPad {
            any["Wain"].firstMatch.tap()
            sleep(3)
            snap(app, "store-2-bot")
            any["Tasks"].firstMatch.tap()
            sleep(2)
            text(app, "Raise the retry limit to 5").tap()
            sleep(3)
            snap(app, "store-3-task")
            any["Home"].firstMatch.tap()  // where New task lives
            sleep(2)
        } else {
            app.tabBars.buttons["Bots"].tap()
            app.buttons["bot.Wain"].tap()
            XCTAssertTrue(any["composer"].waitForExistence(timeout: 15))
            sleep(2)
            snap(app, "store-2-bot")
            app.navigationBars.buttons.element(boundBy: 0).tap()

            app.tabBars.buttons["Tasks"].tap()
            sleep(2)
            text(app, "Raise the retry limit to 5").tap()
            XCTAssertTrue(any["composer"].waitForExistence(timeout: 15))
            sleep(2)
            snap(app, "store-3-task")
            app.navigationBars.buttons.element(boundBy: 0).tap()

            app.tabBars.buttons["Routines"].tap()
            sleep(2)
            snap(app, "store-5-routines")
            app.tabBars.buttons["Home"].tap()
        }

        app.buttons["newTask"].firstMatch.tap()
        XCTAssertTrue(app.buttons["row.Machine"].waitForExistence(timeout: 30))
        let field = any["composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no prompt field")
        field.tap()
        app.typeText("Keep the checkout button visible on small screens")
        sleep(1)
        if app.keyboards.firstMatch.exists { app.swipeDown() }  // the sheet's own fields, not the keyboard
        sleep(1)
        snap(app, "store-4-new-task")
    }

    /// A text on screen by its start, since a row's label can carry more after it.
    private func text(_ app: XCUIApplication, _ start: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", start)).firstMatch
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
