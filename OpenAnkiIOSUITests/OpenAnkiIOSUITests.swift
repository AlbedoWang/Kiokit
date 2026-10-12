import XCTest

@MainActor
final class OpenAnkiIOSUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data"]
        app.launch()
        XCTAssertTrue(app.buttons["startStudy"].waitForExistence(timeout: 10))
        return app
    }

    func testReviewUndoAndPersistence() {
        let app = launch()
        app.buttons["startStudy"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["questionContent"].exists)
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.buttons["rating3"].exists)
        app.buttons["rating3"].tap()
        XCTAssertTrue(app.buttons["undoReview"].isEnabled)
        app.buttons["undoReview"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].exists)
        app.buttons["showAnswer"].tap()
        app.buttons["rating4"].tap()
        app.buttons["finishStudy"].tap()
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["今日评分"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "statistics-after-review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["startStudy"].tap()
        XCTAssertTrue(app.staticTexts["questionContent"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["questionContent"].label, "serendipity")
    }

    func testCreateDeckAndCardAndSearch() {
        let app = launch()
        app.buttons["addDeck"].tap()
        let name = app.textFields["deckName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UI Test Deck")
        app.buttons["保存"].tap()
        app.tabBars.buttons["卡片"].tap()
        app.buttons["addCard"].tap()
        let front = app.textViews["cardFront"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.tap()
        front.typeText("Unique review question")
        let back = app.textViews["cardBack"]
        back.tap()
        back.typeText("Persistent answer")
        app.buttons["保存"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Unique review")
        XCTAssertTrue(app.staticTexts["Unique review question"].waitForExistence(timeout: 5))
    }

    func testImportModernPackageAndDisplayHTML() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "modern", withExtension: "apkg"))
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = url.path
        app.launch()
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 20))
        app.alerts.buttons["好"].tap()
        app.buttons["startStudy"].tap()
        // First review the bundled examples, then reach the imported cards.
        for _ in 0..<13 {
            XCTAssertTrue(app.buttons["showAnswer"].waitForExistence(timeout: 5))
            app.buttons["showAnswer"].tap()
            app.buttons["rating4"].tap()
        }
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'capital of France'")).firstMatch.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "imported-html-card"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Paris"].waitForExistence(timeout: 10))
    }

    func testRestoreBackupRequiresConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "restore", withExtension: "openanki"))
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = url.path
        app.launch()
        XCTAssertTrue(app.alerts["恢复完整备份？"].waitForExistence(timeout: 10))
        app.alerts.buttons["恢复备份"].tap()
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 10))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["Restored Deck"].exists)
        XCTAssertFalse(app.staticTexts["日常英语"].exists)
        app.tabBars.buttons["卡片"].tap()
        XCTAssertTrue(app.staticTexts["Restored question"].waitForExistence(timeout: 5))
    }
}
