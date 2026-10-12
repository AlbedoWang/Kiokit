import XCTest

@MainActor
final class OpenAnkiIOSUITests: XCTestCase {
    private func launch(language: String = "zh-Hans") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["startStudy"].waitForExistence(timeout: 10))
        return app
    }

    func testReviewUndoAndPersistence() {
        let app = launch()
        app.buttons["startStudy"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["questionContent"].exists)
        let firstQuestion = app.staticTexts["questionContent"].label
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.buttons["rating3"].exists)
        app.buttons["rating3"].tap()
        XCTAssertTrue(app.buttons["undoReview"].isEnabled)
        app.buttons["undoReview"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].exists)
        app.buttons["showAnswer"].tap()
        app.buttons["rating4"].tap()
        app.buttons["finishStudy"].tap()
        app.buttons["tabStatistics"].tap()
        XCTAssertTrue(app.staticTexts["今日评分"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "statistics-after-review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        app.buttons["startStudy"].tap()
        XCTAssertTrue(app.staticTexts["questionContent"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["questionContent"].label, firstQuestion)
    }

    func testCreateDeckAndCardAndSearch() {
        let app = launch()
        app.buttons["addDeck"].tap()
        let name = app.textFields["deckName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UI Test Deck")
        app.buttons["保存"].tap()
        app.buttons["tabCards"].tap()
        app.buttons["addCard"].tap()
        let front = app.textViews["cardFront"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.tap()
        front.typeText("Unique review question")
        let back = app.textViews["cardBack"]
        back.tap()
        back.typeText("Persistent answer")
        app.buttons["保存"].tap()
        let search = app.textFields["cardSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Unique review")
        XCTAssertTrue(app.staticTexts["Unique review question"].waitForExistence(timeout: 5))
    }

    func testImportModernPackageAndDisplayHTML() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(zh-Hans)"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "modern", withExtension: "apkg"))
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = url.path
        app.launch()
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 20))
        app.alerts.buttons["好"].tap()
        app.buttons["startStudy"].tap()
        // First review the four guide cards, then reach the imported cards.
        for _ in 0..<4 {
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
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(zh-Hans)"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "restore", withExtension: "openanki"))
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = url.path
        app.launch()
        XCTAssertTrue(app.alerts["恢复完整备份？"].waitForExistence(timeout: 10))
        app.alerts.buttons["恢复备份"].tap()
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 10))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["Restored Deck"].exists)
        XCTAssertFalse(app.staticTexts["开始使用 Anki"].exists)
        app.buttons["tabCards"].tap()
        XCTAssertTrue(app.staticTexts["Restored question"].waitForExistence(timeout: 5))
    }
    func testN4JapaneseWordRecordingExamplesAndOriginalMeanings() throws {
        guard let path = ProcessInfo.processInfo.environment["OPENANKI_TEST_APKG"],
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Set OPENANKI_TEST_APKG to a local N4.apkg.") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(en)"]
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = path
        app.launch()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 120))
        app.alerts.buttons["OK"].tap()
        let deck = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "日本语红宝书::N4")).firstMatch
        for _ in 0..<4 where !deck.isHittable || deck.frame.midY > app.frame.maxY - 160 { app.swipeUp() }
        XCTAssertTrue(deck.isHittable)
        deck.tap()
        XCTAssertTrue(app.buttons["deckStartStudy"].waitForExistence(timeout: 10))
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.buttons["readWord"].waitForExistence(timeout: 10))
        // The first N4 word (あ) has no recording; Japanese speech fills in.
        app.buttons["readWord"].tap()
        XCTAssertTrue(app.staticTexts["playbackSource"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["playbackSource"].label, "Japanese voice")
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.buttons["readExamples"].waitForExistence(timeout: 10))
        app.buttons["readExamples"].tap()
        XCTAssertTrue(app.staticTexts["playbackSource"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["playbackSource"].label, "Japanese voice")
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS '啊'")).firstMatch.waitForExistence(timeout: 10))
        var playedRecording = false
        for _ in 0..<8 {
            app.buttons["rating3"].tap()
            app.buttons["readWord"].tap()
            if app.staticTexts["playbackSource"].waitForExistence(timeout: 10), app.staticTexts["playbackSource"].label == "Deck recording" {
                playedRecording = true
                app.buttons["showAnswer"].tap()
                break
            }
            app.buttons["showAnswer"].tap()
        }
        XCTAssertTrue(playedRecording)
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS '那样，那么'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'ああ言えばこう言う'")).firstMatch.exists)
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS '强词夺理'")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "N4-original-language-and-native-audio"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testUnsupportedSystemLanguageDefaultsToEnglish() {
        let app = launch(language: "ja-JP")
        XCTAssertEqual(app.buttons["startStudy"].label, "Start studying")
        XCTAssertTrue(app.staticTexts["Getting started with Anki"].exists)
        XCTAssertFalse(app.staticTexts["日常英语"].exists)
        XCTAssertFalse(app.staticTexts["Swift 随手记"].exists)
        app.buttons["tabSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testLanguageSwitchLocalizesGuidePersistsAndLeavesImportedContentUnchanged() throws {
        continueAfterFailure = false
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tsv")
        try "あいさつ\t寒暄；打招呼。\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = file.path
        app.launch()
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 15))
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["开始使用 Anki"].exists)
        XCTAssertFalse(app.staticTexts["日常英语"].exists)
        XCTAssertFalse(app.staticTexts["Swift 随手记"].exists)
        app.buttons["tabSettings"].tap()
        let picker = app.buttons["interfaceLanguage"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["简体中文"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["English"].tap()
        app.buttons["tabDecks"].tap()
        XCTAssertTrue(app.staticTexts["Getting started with Anki"].exists)
        app.buttons["startStudy"].tap()
        XCTAssertEqual(app.buttons["showAnswer"].label, "Show answer")
        XCTAssertEqual(app.staticTexts["questionContent"].label, "How do I start studying?")
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.staticTexts["answerContent"].label.contains("Recall the answer first"))
        app.buttons["finishStudy"].tap()
        app.buttons["tabCards"].tap()
        let search = app.textFields["cardSearch"]
        search.tap()
        search.typeText("あいさつ")
        XCTAssertTrue(app.staticTexts["あいさつ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["寒暄；打招呼。"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "OPENANKI_IMPORT_FILE")
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["startStudy"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["startStudy"].label, "Start studying")
        XCTAssertTrue(app.staticTexts["Getting started with Anki"].exists)
    }

}
