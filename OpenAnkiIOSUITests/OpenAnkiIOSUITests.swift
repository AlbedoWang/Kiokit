import XCTest

@MainActor
final class OpenAnkiIOSUITests: XCTestCase {
    private func launch(language: String = "en", importing: String? = nil, diagnostics: String? = nil, reviewerDiagnostics: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(\(language))"]
        if let importing { app.launchEnvironment["OPENANKI_IMPORT_FILE"] = importing }
        if let diagnostics { app.launchEnvironment["OPENANKI_AUDIO_DIAGNOSTICS_FILE"] = diagnostics }
        if let reviewerDiagnostics { app.launchEnvironment["OPENANKI_REVIEWER_DIAGNOSTICS_FILE"] = reviewerDiagnostics }
        app.launch()
        if importing != nil {
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 45), app.debugDescription)
            XCTAssertFalse(app.alerts.firstMatch.label.contains("unfinished"))
            let button = app.alerts.buttons.firstMatch
            button.tap()
        }
        XCTAssertTrue(app.buttons["startStudy"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func enterNumber(_ number: String, in field: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + number)
        XCTAssertTrue(app.buttons["finishNumberInput"].waitForExistence(timeout: 5))
        app.buttons["finishNumberInput"].tap()
        XCTAssertEqual(field.value as? String, number)
    }

    private func openDeck(_ name: String, app: XCUIApplication) {
        app.buttons["tabDecks"].tap()
        let deck = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        for _ in 0..<5 where !deck.isHittable { app.swipeUp() }
        XCTAssertTrue(deck.waitForExistence(timeout: 5), app.debugDescription)
        deck.tap()
        XCTAssertTrue(app.buttons["deckStudySettings"].waitForExistence(timeout: 5))
    }

    private func question(_ app: XCUIApplication) -> String {
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        let text = web.staticTexts.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        return text.label
    }

    func testReviewUsesNativeHTMLIntervalsUndoAndPersistence() {
        let app = launch()
        app.buttons["startStudy"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].waitForExistence(timeout: 5))
        let first = question(app)
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.buttons["rating3"].exists)
        app.buttons["rating3"].tap()
        XCTAssertTrue(app.buttons["undoReview"].isEnabled)
        app.buttons["undoReview"].tap()
        XCTAssertEqual(question(app), first)
        app.buttons["showAnswer"].tap()
        app.buttons["rating4"].tap()
        app.buttons["finishStudy"].tap()
        app.terminate()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["startStudy"].tap()
        XCTAssertNotEqual(question(app), first)
    }

    func testCreateNativeNoteAndSearchOriginalFields() {
        let app = launch()
        app.buttons["tabCards"].tap()
        app.buttons["addCard"].tap()
        let front = app.textViews["cardFront"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.tap()
        front.typeText("Unique native question")
        let back = app.textViews["cardBack"]
        back.tap()
        back.typeText("Persistent original answer")
        app.buttons["Save"].tap()
        let search = app.textFields["cardSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Unique native")
        XCTAssertTrue(app.staticTexts["Unique native question"].waitForExistence(timeout: 5), app.debugDescription)
        app.staticTexts["Unique native question"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Persistent original answer'")).firstMatch.waitForExistence(timeout: 10))
        let detailBack = app.otherElements["cardDetailBack"]
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(detailBack.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Unique native question'")).firstMatch.exists)
        XCTAssertTrue(app.webViews.staticTexts["Unique native question"].exists)
    }

    func testLicensesAndSourceLinksAreAvailableOffline() {
        let app = launch()
        app.buttons["tabSettings"].tap()
        let licenses = app.buttons["licenses"]
        for _ in 0..<5 where !licenses.isHittable { app.swipeUp() }
        XCTAssertTrue(licenses.exists, app.debugDescription)
        licenses.tap()
        XCTAssertTrue(app.staticTexts["OpenAnkiIOS · AGPL-3.0-or-later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["Project source code"].exists || app.buttons["Project source code"].exists)
        app.buttons["OpenAnkiIOS (AGPL-3.0)"].tap()
        let document = app.textViews.firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (document.value as? String)?.contains("GNU AFFERO GENERAL PUBLIC LICENSE") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
    }

    func testNumericSettingsAndNativeRandomPresetPersist() {
        let app = launch()
        app.buttons["tabSettings"].tap()
        enterNumber("1500", in: app.textFields["dailyReviewGoal"], app: app)
        enterNumber("2500", in: app.textFields["defaultNewCardLimit"], app: app)
        openDeck("Getting started with Anki", app: app)
        app.buttons["deckStudySettings"].tap()
        app.buttons["clonePreset"].tap()
        app.switches["useDefaultNewCardLimit"].switches.firstMatch.tap()
        enterNumber("1234", in: app.textFields["deckNewCardLimit"], app: app)
        app.buttons["deckStudyOrder"].tap()
        app.buttons["Random"].tap()
        app.buttons["finishDeckStudySettings"].tap()
        app.buttons["deckStartStudy"].tap()
        var questions = Set<String>()
        for _ in 0..<3 {
            XCTAssertTrue(questions.insert(question(app)).inserted)
            app.buttons["showAnswer"].tap()
            app.buttons["rating4"].tap()
        }
        app.buttons["finishStudy"].tap()
        app.terminate()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)"]
        app.launch()
        openDeck("Getting started with Anki", app: app)
        app.buttons["deckStudySettings"].tap()
        XCTAssertEqual(app.textFields["deckNewCardLimit"].value as? String, "1234")
        XCTAssertTrue(app.buttons["deckStudyOrder"].label.contains("Random"))
        app.buttons["finishDeckStudySettings"].tap()
        app.buttons["tabSettings"].tap()
        XCTAssertEqual(app.textFields["dailyReviewGoal"].value as? String, "1500")
        XCTAssertEqual(app.textFields["defaultNewCardLimit"].value as? String, "2500")
    }

    func testPerDeckLimitAndUndoUseAnkiCounts() {
        let app = launch()
        openDeck("Getting started with Anki", app: app)
        app.buttons["deckStudySettings"].tap()
        app.switches["useDefaultNewCardLimit"].switches.firstMatch.tap()
        enterNumber("1", in: app.textFields["deckNewCardLimit"], app: app)
        app.buttons["finishDeckStudySettings"].tap()
        XCTAssertEqual(app.staticTexts["deckNewCount"].label, "1")
        app.buttons["deckStartStudy"].tap()
        app.buttons["showAnswer"].tap()
        app.buttons["rating4"].tap()
        app.buttons["undoReview"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].exists)
        app.buttons["showAnswer"].tap()
        app.buttons["rating4"].tap()
        app.buttons["finishStudy"].tap()
        XCTAssertEqual(app.staticTexts["deckNewCount"].label, "0")
    }

    func testOfficialModernPackageRendersHTMLAndRecordedAudio() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "modern", withExtension: "apkg"))
        let app = launch(importing: file.path)
        openDeck("Basics", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'capital of France'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Paris'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["readWord"].tap()
        XCTAssertTrue(app.staticTexts["Deck recording"].waitForExistence(timeout: 5))
    }

    func testNativeBackupRestoreRequiresConfirmation() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "backup", withExtension: "colpkg"))
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(en)"]
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = file.path
        app.launch()
        XCTAssertTrue(app.alerts["Restore full backup?"].waitForExistence(timeout: 15))
        app.alerts.buttons["Restore backup"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Backup native deck"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Getting started with Anki"].exists)
    }

    private func launchReviewer(diagnostics: URL, fixture: String = "reviewer", audioDiagnostics: URL? = nil, statisticsDiagnostics: URL? = nil, timerDiagnostics: URL? = nil, diagnosticsSide: String? = nil) throws -> XCUIApplication {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: fixture, withExtension: "colpkg"))
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(en)"]
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = file.path
        app.launchEnvironment["OPENANKI_REVIEWER_DIAGNOSTICS_FILE"] = diagnostics.path
        if let diagnosticsSide { app.launchEnvironment["OPENANKI_REVIEWER_DIAGNOSTICS_SIDE"] = diagnosticsSide }
        if let audioDiagnostics { app.launchEnvironment["OPENANKI_AUDIO_DIAGNOSTICS_FILE"] = audioDiagnostics.path }
        if let statisticsDiagnostics { app.launchEnvironment["OPENANKI_STATISTICS_DIAGNOSTICS_FILE"] = statisticsDiagnostics.path }
        if let timerDiagnostics { app.launchEnvironment["OPENANKI_TIMER_DIAGNOSTICS_FILE"] = timerDiagnostics.path }
        app.launch()
        XCTAssertTrue(app.alerts["Restore full backup?"].waitForExistence(timeout: 15))
        app.alerts.buttons["Restore backup"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        app.alerts.buttons["OK"].tap()
        return app
    }

    private func reviewerState(_ file: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    func testBrowserDeleteRemovesTheWholeNoteAndUndoRestoresBothOriginalCards() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "notes")
        app.buttons["tabCards"].tap()
        let search = app.textFields["cardSearch"]
        search.tap()
        search.typeText("Original sibling")
        XCTAssertTrue(app.staticTexts["2 cards"].waitForExistence(timeout: 5), app.debugDescription)
        app.staticTexts["Original sibling front"].firstMatch.tap()
        XCTAssertTrue(app.buttons["cardActions"].waitForExistence(timeout: 5))
        app.buttons["cardActions"].tap()
        app.buttons["deleteNote"].tap()
        XCTAssertTrue(app.staticTexts["Delete this note and all its cards?"].waitForExistence(timeout: 5))
        app.buttons["Delete note"].tap()
        XCTAssertTrue(app.staticTexts["0 cards"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["undoBrowser"].isEnabled)
        app.buttons["undoBrowser"].tap()
        XCTAssertTrue(app.staticTexts["2 cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Original sibling front"].exists)
        XCTAssertTrue(app.staticTexts["Original sibling answer"].exists)
    }

    private func waitForTimer(_ file: URL, predicate: @escaping ([String: Any]) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in predicate(reviewerState(file)) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       (try? String(contentsOf: file, encoding: .utf8)) ?? "Missing timer diagnostics")
    }

    func testUpstreamDisplayTimerStopsOnAnswerWithoutSharingTemplateGlobals() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let timer = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); attachReviewerDiagnostics(timer); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: timer) }
        let app = try launchReviewer(diagnostics: file, fixture: "timers", timerDiagnostics: timer)
        openDeck("Stopped timer", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Original template time variable"].waitForExistence(timeout: 10))
        waitForTimer(timer) { ($0["time"] as? Int ?? 0) >= 1 && $0["timerStopped"] as? Bool == false }
        app.buttons["showAnswer"].tap()
        waitForTimer(timer) { $0["timerStopped"] as? Bool == true }
        let stopped = reviewerState(timer)["time"] as? Int
        let increment = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in reviewerState(timer)["time"] as? Int != stopped }, object: nil)
        increment.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [increment], timeout: 2), .completed)
        XCTAssertEqual(reviewerState(timer)["maxTime"] as? Int, 10)
        app.buttons["rating4"].tap()
    }

    func testUpstreamDisplayTimerKeepsRunningAndHonorsItsNativeLimit() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let timer = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); attachReviewerDiagnostics(timer); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: timer) }
        let app = try launchReviewer(diagnostics: file, fixture: "timers", timerDiagnostics: timer)
        openDeck("Running timer", app: app)
        app.buttons["deckStartStudy"].tap()
        waitForTimer(timer) { ($0["time"] as? Int ?? 0) >= 1 }
        app.buttons["showAnswer"].tap()
        let before = reviewerState(timer)["time"] as? Int ?? 0
        waitForTimer(timer) { ($0["time"] as? Int ?? 0) > before && $0["timerStopped"] as? Bool == false }
        waitForTimer(timer) { $0["text"] as? String == "0:10" }
        app.buttons["rating4"].tap()
    }

    func testOfficialStatisticsPageLoadsRecordedHistoryOffline() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let graphs = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); attachReviewerDiagnostics(graphs); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: graphs) }
        let app = try launchReviewer(diagnostics: file, fixture: "backup", statisticsDiagnostics: graphs)
        app.buttons["tabStatistics"].tap()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let state = reviewerState(graphs)
            return (state["charts"] as? Int ?? 0) == 3 && (state["roundedBars"] as? Int ?? 0) > 0 && (state["text"] as? String)?.contains("Reviews") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed, (try? String(contentsOf: graphs, encoding: .utf8)) ?? app.debugDescription)
        let state = reviewerState(graphs)
        XCTAssertEqual((state["errors"] as? [String]) ?? [], [])
        let transport = try XCTUnwrap(state["transport"] as? [String: Any])
        let request = try XCTUnwrap(transport["/_anki/graphs"] as? [String: Any])
        XCTAssertEqual((request["request"] as? [String: Any])?["search"] as? String, "deck:current")
        let today = ((request["response"] as? [String: Any])?["today"] as? [String: Any])
        XCTAssertEqual(today?["answerCount"] as? Int, 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        let sections = try XCTUnwrap(state["sections"] as? [[String: Any]])
        XCTAssertEqual(Set(sections.compactMap { $0["role"] as? String }), Set(["reviews", "future", "added"]))
        XCTAssertEqual(state["visibleTables"] as? Int, 0)
        XCTAssertEqual(state["visibleOverlays"] as? Int, 0)
        let tickSizes = try XCTUnwrap(state["tickSizes"] as? [Double])
        XCTAssertFalse(tickSizes.isEmpty)
        XCTAssertTrue(tickSizes.allSatisfy { $0 >= 14.9 })
        XCTAssertFalse((state["text"] as? String ?? "").contains("Calendar"))
        XCTAssertTrue(sections.allSatisfy { $0["radius"] as? String == "24px" && $0["headingSize"] as? String == "25px" })
        screenshot.name = "three-upstream-bar-charts-with-readable-rounded-cards"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitForStatistics(_ file: URL, predicate: @escaping ([String: Any]) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in predicate(reviewerState(file)) }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 20)
        if result != .completed { attachReviewerDiagnostics(file) }
        XCTAssertEqual(result, .completed, "Search: \(reviewerState(file)["search"] ?? ""); request: \(statisticsRequest(file)); errors: \(reviewerState(file)["errors"] ?? "")")
    }

    private func statisticsRequest(_ file: URL, path: String = "/_anki/graphs") -> [String: Any] {
        let transport = reviewerState(file)["transport"] as? [String: Any]
        return (transport?[path] as? [String: Any])?["request"] as? [String: Any] ?? [:]
    }

    func testOfficialStatisticsScopesPreferencesAndGraphSearchUseAnki() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let graphs = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(graphs); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: graphs) }
        let app = try launchReviewer(diagnostics: file, fixture: "statistics", statisticsDiagnostics: graphs)
        app.buttons["tabStatistics"].tap()
        waitForStatistics(graphs) { ($0["charts"] as? Int ?? 0) > 0 }
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == 'collection'")).firstMatch.tap()
        waitForStatistics(graphs) { [self] _ in (statisticsRequest(graphs)["search"] as? String ?? "") == "" }
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == 'all history'")).firstMatch.tap()
        waitForStatistics(graphs) { [self] _ in (statisticsRequest(graphs)["days"] as? Int ?? 0) == 0 }
        let search = app.webViews.textFields.firstMatch
        search.tap()
        search.typeText("deck:\"Statistics B\"\n")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        app.webViews.staticTexts["Reviews"].firstMatch.tap()
        waitForStatistics(graphs) { [self] _ in statisticsRequest(graphs)["search"] as? String == "deck:\"Statistics B\"" }
        let state = reviewerState(graphs)
        let transport = try XCTUnwrap(state["transport"] as? [String: Any])
        let native = try XCTUnwrap((transport["/_anki/graphs"] as? [String: Any])?["response"] as? [String: Any])
        XCTAssertEqual(((native["cardCounts"] as? [String: Any])?["includingInactive"] as? [String: Any])?["newCards"] as? Int, 1)
        XCTAssertNotNil((transport["/_anki/getGraphPreferences"] as? [String: Any])?["response"])
        let newCards = app.webViews.buttons["Added 1"]
        for _ in 0..<8 where !newCards.isHittable { app.webViews.firstMatch.swipeUp() }
        XCTAssertTrue(newCards.exists, app.debugDescription)
        newCards.tap()
        let opened = app.textFields["cardSearch"].waitForExistence(timeout: 10)
        if !opened { attachReviewerDiagnostics(graphs) }
        XCTAssertTrue(opened, app.debugDescription)
        XCTAssertTrue((app.textFields["cardSearch"].value as? String)?.contains("Statistics B") == true)
        XCTAssertTrue(app.staticTexts["Statistics B original 0"].waitForExistence(timeout: 10))
        XCTAssertEqual((reviewerState(graphs)["errors"] as? [String]) ?? [], [])
    }

    func testOfficialStatisticsUsesTheChineseBackendTranslations() throws {
        let graphs = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(graphs); try? FileManager.default.removeItem(at: graphs) }
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["OPENANKI_STATISTICS_DIAGNOSTICS_FILE"] = graphs.path
        app.launch()
        app.buttons["tabStatistics"].tap()
        XCTAssertTrue(app.webViews.staticTexts["复习"].waitForExistence(timeout: 15), app.debugDescription)
        waitForStatistics(graphs) { ($0["text"] as? String)?.contains("近一年") == true }
        XCTAssertEqual((reviewerState(graphs)["errors"] as? [String]) ?? [], [])
    }

    func testOfficialTypedAnswerAndCustomSchedulingExecuteInWebKit() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file)
        openDeck("Typed answer", app: app)
        app.buttons["deckStartStudy"].tap()
        let input = app.webViews.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), app.debugDescription)
        input.tap()
        input.typeText("日本語")
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.buttons["rating3"].waitForExistence(timeout: 5), app.debugDescription)
        let compared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let state = self.reviewerState(file)
            return (state["html"] as? String)?.contains("typeGood") == true && state["statesMutated"] as? Bool == true
        }, object: nil)
        wait(for: [compared], timeout: 15)
        let state = reviewerState(file)
        let queued = try XCTUnwrap(state["queued"] as? [String: Any])
        let states = try XCTUnwrap(queued["states"] as? [String: Any])
        let good = try XCTUnwrap(states["good"] as? [String: Any])
        let normal = try XCTUnwrap(good["normal"] as? [String: Any])
        let learning = try XCTUnwrap(normal["learning"] as? [String: Any])
        XCTAssertEqual(learning["scheduledSecs"] as? Int, 42)
        let custom = try XCTUnwrap(good["customData"] as? String)
        let customData = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(custom.utf8)) as? [String: Any])
        XCTAssertEqual(customData["count"] as? Int, 1)
        XCTAssertEqual(customData["deck"] as? String, "Typed answer")
        XCTAssertTrue(app.buttons["rating3"].isEnabled)
        app.buttons["rating3"].tap()
        XCTAssertTrue(app.buttons["undoReview"].isEnabled)
        let repeated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let state = self.reviewerState(file)
            guard state["side"] as? String == "question", let queued = state["queued"] as? [String: Any],
                  let card = queued["card"] as? [String: Any], let data = card["customData"] as? String else { return false }
            return data.contains("\"count\":1") && state["statesMutated"] as? Bool == true
        }, object: nil)
        wait(for: [repeated], timeout: 15)
        XCTAssertTrue(app.webViews.textFields.firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "official-typed-answer-and-custom-scheduling"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testOfficialMathJaxAndImageOcclusionRenderOffline() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file)
        openDeck("MathJax", app: app)
        app.buttons["deckStartStudy"].tap()
        let formula = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.reviewerState(file)["mathJaxCount"] as? Int == 1
        }, object: nil)
        wait(for: [formula], timeout: 20)
        XCTAssertTrue((reviewerState(file)["html"] as? String)?.contains("mjx-container") == true)
        app.buttons["showAnswer"].tap()
        let answer = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let state = self.reviewerState(file)
            return state["side"] as? String == "answer" && state["mathJaxCount"] as? Int == 2
        }, object: nil)
        wait(for: [answer], timeout: 15)
        app.buttons["finishStudy"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        openDeck("Image occlusion", app: app)
        app.buttons["deckStartStudy"].tap()
        let mask = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let state = self.reviewerState(file)
            return (state["maskPixels"] as? Int ?? 0) > 100 && (state["canvasWidth"] as? Int ?? 0) > 0
        }, object: nil)
        wait(for: [mask], timeout: 15)
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.webViews.buttons["Toggle Masks"].waitForExistence(timeout: 15), app.debugDescription)
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.reviewerState(file)["side"] as? String == "answer"
        }, object: nil)
        wait(for: [revealed], timeout: 5)
        let before = reviewerState(file)["maskPixels"] as? Int ?? 0
        XCTAssertGreaterThan(before, 100)
        app.webViews.buttons["Toggle Masks"].tap()
        let toggled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let pixels = self.reviewerState(file)["maskPixels"] as? Int ?? before
            return pixels == 0
        }, object: nil)
        wait(for: [toggled], timeout: 5)
        app.webViews.buttons["Toggle Masks"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.reviewerState(file)["maskPixels"] as? Int == before
        }, object: nil)
        wait(for: [restored], timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "official-offline-image-occlusion"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func attachReviewerDiagnostics(_ file: URL) {
        if let data = try? Data(contentsOf: file) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "official-reviewer-diagnostics"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testOfficialCustomSchedulingWaitsForAsyncTransform() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file)
        openDeck("Async scheduling", app: app)
        app.buttons["deckStartStudy"].tap()
        _ = question(app)
        app.buttons["showAnswer"].tap()
        let rating = app.buttons["rating3"]
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        XCTAssertFalse(rating.isEnabled, "The pending upstream async transform must finish before answers can be submitted.")
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let state = self.reviewerState(file)
            guard state["statesMutated"] as? Bool == true, let queued = state["queued"] as? [String: Any],
                  let states = queued["states"] as? [String: Any], let good = states["good"] as? [String: Any],
                  let data = good["customData"] as? String else { return false }
            return data.contains("\"count\":1")
        }, object: nil)
        wait(for: [completed], timeout: 15)
        XCTAssertTrue(rating.isEnabled)
    }

    func testReviewEditingRedrawsQuestionAndUndoRestoresNativeNote() {
        let app = launch()
        app.buttons["startStudy"].tap()
        let original = question(app)
        app.buttons["reviewActions"].tap()
        app.buttons["Edit card"].tap()
        let field = app.textViews["cardFront"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Edited while reviewing")
        app.buttons["Save"].tap()
        let edited = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Edited while reviewing'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["showAnswer"].exists)
        XCTAssertTrue(app.buttons["undoReview"].isEnabled)
        app.buttons["undoReview"].tap()
        XCTAssertEqual(question(app), original)
        XCTAssertTrue(app.buttons["showAnswer"].exists)
        app.buttons["showAnswer"].tap()
        app.buttons["rating3"].tap()
        XCTAssertTrue(app.buttons["undoReview"].isEnabled)
    }

    func testReviewEditingOnAnswerKeepsAnswerSideAndUndoCount() {
        let app = launch()
        app.buttons["startStudy"].tap()
        _ = question(app)
        app.buttons["showAnswer"].tap()
        app.buttons["reviewActions"].tap()
        app.buttons["Edit card"].tap()
        let field = app.textViews["cardBack"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Changed answer during review")
        app.buttons["Save"].tap()
        let changed = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Changed answer during review'")).firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["rating3"].exists)
        app.buttons["undoReview"].tap()
        XCTAssertTrue(app.buttons["rating3"].exists)
        XCTAssertTrue(app.staticTexts["0 reviewed"].exists)
        XCTAssertFalse(changed.exists)
    }

    func testFilteredDeckSettingsRebuildEmptyAndOriginalAudioOptions() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let audio = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: audio) }
        let app = try launchReviewer(diagnostics: file, fixture: "filtered", audioDiagnostics: audio)
        openDeck("Filtered audio", app: app)
        app.buttons["deckStartStudy"].tap()
        _ = question(app)
        XCTAssertFalse(app.staticTexts["Deck recording"].exists, "Autoplay must follow the original deck's disabled setting.")
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Original filtered answer'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["readWord"].tap()
        XCTAssertTrue(app.staticTexts["Deck recording"].waitForExistence(timeout: 5))
        let playback = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: audio)) as? [String: Any])
        XCTAssertTrue((playback["attemptedFile"] as? String)?.hasSuffix("answer.wav") == true)
        app.buttons["finishStudy"].tap()
        app.buttons["deckStudySettings"].tap()
        enterNumber("12000", in: app.textFields["filteredLimit0"], app: app)
        app.buttons["rebuildFilteredDeck"].tap()
        XCTAssertTrue(app.buttons["deckStudySettings"].waitForExistence(timeout: 10))
        app.buttons["deckStudySettings"].tap()
        XCTAssertEqual(app.textFields["filteredLimit0"].value as? String, "12000")
        app.buttons["emptyFilteredDeck"].tap()
        XCTAssertTrue(app.buttons["deckStudySettings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["deckNewCount"].label, "0")
    }

    func testImportedLatexPngSvgAndMissingToolErrorUseOfficialRendering() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "latex")
        for name in ["LaTeX PNG", "LaTeX SVG"] {
            openDeck(name, app: app)
            app.buttons["deckStartStudy"].tap()
            let image = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let images = self.reviewerState(file)["images"] as? [[String: Any]], let first = images.first else { return false }
                return first["complete"] as? Bool == true && (first["width"] as? Int ?? 0) > 0 && (first["src"] as? String)?.hasPrefix("latex-") == true
            }, object: nil)
            wait(for: [image], timeout: 15)
            XCTAssertTrue(app.webViews.images.firstMatch.exists)
            app.buttons["finishStudy"].tap()
            app.navigationBars.buttons["BackButton"].tap()
        }
        openDeck("Missing LaTeX", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Error executing'")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Have you installed latex'")).firstMatch.exists)
    }

    func testDisabledLatexGenerationDisplaysUpstreamPreferenceMessage() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "latex-disabled")
        openDeck("Missing LaTeX", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'LaTeX image generation is disabled'")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["showAnswer"].exists)
    }

    func testFreshChineseProfileUsesLocalizedUpstreamNoteFields() {
        let app = launch(language: "zh-Hans")
        app.buttons["tabCards"].tap()
        app.buttons["addCard"].tap()
        XCTAssertTrue(app.textViews["cardFront"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正面"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["背面"].exists, app.debugDescription)
    }

    func testRestoreReloadsChineseBackendIntervalsAndOriginalContent() throws {
        continueAfterFailure = false
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "backup-zh", withExtension: "colpkg"))
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data", "-AppleLanguages", "(en)"]
        app.launchEnvironment["OPENANKI_IMPORT_FILE"] = file.path
        app.launch()
        XCTAssertTrue(app.alerts["Restore full backup?"].waitForExistence(timeout: 15))
        app.alerts.buttons["Restore backup"].tap()
        XCTAssertTrue(app.alerts["导入完成"].waitForExistence(timeout: 10))
        app.alerts.buttons["好"].tap()
        app.buttons["startStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Restored question"].waitForExistence(timeout: 10))
        app.buttons["showAnswer"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS '原始答案'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["rating3"].label.contains("分"), app.buttons["rating3"].label)
    }

    func testTemplateJavaScriptReadsOriginalOfflineJsonMedia() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "media")
        openDeck("Offline media", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Original offline data loaded"].waitForExistence(timeout: 15), app.debugDescription)
    }

    private func waitForPlayback(_ file: URL, timeout: TimeInterval = 15, predicate: @escaping ([String: Any]) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in predicate(reviewerState(file)) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       (try? String(contentsOf: file, encoding: .utf8)) ?? "Missing playback diagnostics")
    }

    func testTemplateJavaScriptImportsOriginalOfflineModuleMedia() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "media")
        openDeck("Offline module", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Original offline module loaded"].waitForExistence(timeout: 15), app.debugDescription)
    }

    func testSoundOrVideoPlayerUsesOriginalTracksInsteadOfFilenameExtension() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let audio = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: audio) }
        for (deck, filename, video) in [
            ("Video in audio extension", "original video.3gp", true),
            ("Audio in video extension", "original audio.mp4", false),
        ] {
            let app = try launchReviewer(diagnostics: file, fixture: "media", audioDiagnostics: audio)
            openDeck(deck, app: app)
            app.buttons["deckStartStudy"].tap()
            waitForPlayback(audio) { state in
                (state["attemptedFile"] as? String)?.hasSuffix(filename) == true
                    && state["videoVisible"] as? Bool == video
                    && (state["videoSeconds"] as? Double ?? 0) > 0.3
                    && state["videoGainDB"] as? Double == 6 && state["videoProcessingError"] as? Int == 0
            }
            waitForPlayback(audio) { state in
                (state["attemptedFile"] as? String)?.hasSuffix("after.wav") == true
                    && state["videoVisible"] as? Bool == false && state["playing"] as? Bool == true
            }
            waitForPlayback(audio) { $0["playing"] as? Bool == false }
            app.buttons["finishStudy"].tap()
            app.terminate()
        }
    }

    func testImportedTemplateUsesUpstreamDocumentAndLegacyThemeClasses() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        for (appearance, theme, visible) in [("Light", "light", "Original light template"), ("Dark", "dark", "Original dark template")] {
            let app = try launchReviewer(diagnostics: file, fixture: "media")
            app.buttons["tabSettings"].tap()
            app.buttons["interfaceAppearance"].tap()
            app.buttons[appearance].tap()
            openDeck("Original template theme", app: app)
            app.buttons["deckStartStudy"].tap()
            XCTAssertTrue(app.webViews.staticTexts[visible].waitForExistence(timeout: 15), app.debugDescription)
            waitForPlayback(file) { $0["theme"] as? String == theme }
            let state = reviewerState(file)
            let body = state["bodyClasses"] as? String ?? ""
            XCTAssertEqual(body.contains("nightMode"), theme == "dark")
            XCTAssertEqual(body.contains("night_mode"), theme == "dark")
            XCTAssertEqual((state["documentClasses"] as? String ?? "").contains("night-mode"), theme == "dark")
            app.buttons["showAnswer"].tap()
            XCTAssertTrue(app.webViews.staticTexts["Original theme answer"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testChangingAppearanceUpdatesTheExistingImportedCardDocument() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "media", diagnosticsSide: "question")
        app.buttons["tabSettings"].tap()
        app.buttons["interfaceAppearance"].tap()
        app.buttons["Light"].tap()
        app.buttons["tabCards"].tap()
        let search = app.textFields["cardSearch"]
        search.tap()
        search.typeText("deck:\"Original template theme\"")
        let row = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Original light template'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.webViews.staticTexts["Original light template"].waitForExistence(timeout: 10))
        waitForPlayback(file) { $0["side"] as? String == "question" && $0["theme"] as? String == "light" }
        let document = try XCTUnwrap(reviewerState(file)["documentIdentity"] as? String)
        for (appearance, theme, visible) in [("Dark", "dark", "Original dark template"), ("Light", "light", "Original light template")] {
            app.buttons["tabSettings"].tap()
            app.buttons["interfaceAppearance"].tap()
            app.buttons[appearance].tap()
            app.buttons["tabCards"].tap()
            XCTAssertTrue(app.webViews.staticTexts[visible].waitForExistence(timeout: 10), app.debugDescription)
            waitForPlayback(file) { $0["side"] as? String == "question" && $0["theme"] as? String == theme }
            XCTAssertEqual(reviewerState(file)["documentIdentity"] as? String, document)
        }
    }

    func testVideoTagsDisplayApplyGainContinueAndStopTheOriginalQueue() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let audio = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: audio) }
        let app = try launchReviewer(diagnostics: file, fixture: "media", audioDiagnostics: audio)
        openDeck("Video playback", app: app)
        app.buttons["deckStartStudy"].tap()
        waitForPlayback(audio) { state in
            state["videoVisible"] as? Bool == true && (state["videoSeconds"] as? Double ?? 0) > 0.3
                && state["videoGainDB"] as? Double == 6 && state["videoProcessingError"] as? Int == 0
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "original-video-frame-with-native-audio-gain"
        shot.lifetime = .keepAlways
        add(shot)
        waitForPlayback(audio) { state in
            (state["attemptedFile"] as? String)?.hasSuffix("after.wav") == true && state["playing"] as? Bool == true
        }
        waitForPlayback(audio) { $0["playing"] as? Bool == false }
        app.buttons["readWord"].tap()
        waitForPlayback(audio) { $0["videoVisible"] as? Bool == true && ($0["videoSeconds"] as? Double ?? 0) > 0.3 }
        app.buttons["stopAudio"].tap()
        waitForPlayback(audio, timeout: 5) { $0["playing"] as? Bool == false && $0["videoVisible"] as? Bool == false }
        let continued = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let state = reviewerState(audio)
            return (state["attemptedFile"] as? String)?.hasSuffix("after.wav") == true && state["playing"] as? Bool == true
        }, object: nil)
        continued.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [continued], timeout: 7), .completed)
    }

    func testMissingVideoCompletesAndAdvancesToTheFollowingRecording() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let audio = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: audio) }
        let app = try launchReviewer(diagnostics: file, fixture: "media", audioDiagnostics: audio)
        openDeck("Failed video playback", app: app)
        app.buttons["deckStartStudy"].tap()
        waitForPlayback(audio) { state in
            (state["attemptedFile"] as? String)?.hasSuffix("after.wav") == true && state["playing"] as? Bool == true
        }
        XCTAssertTrue(app.staticTexts["Deck recording"].exists)
        waitForPlayback(audio) { $0["playing"] as? Bool == false }
    }

    func testUnavailableTtsVoiceDoesNotInventAFallbackOrSkipToTheNextTag() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let audio = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: audio) }
        let app = try launchReviewer(diagnostics: file, fixture: "media", audioDiagnostics: audio)
        openDeck("Unavailable speech voice", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.staticTexts["No installed voice matches the requested language. Download a voice and try again."].waitForExistence(timeout: 10))
        let state = reviewerState(audio)
        XCTAssertEqual(state["playing"] as? Bool, false)
        XCTAssertEqual(state["attemptedFile"] as? String, "")
        XCTAssertEqual(state["queuedTags"] as? Int, 1)
    }

    func testNativeTtsSynthesisPlaysBeforeTheFollowingRecording() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let audio = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: audio) }
        let app = try launchReviewer(diagnostics: file, fixture: "media", audioDiagnostics: audio)
        openDeck("Native speech playback", app: app)
        app.buttons["deckStartStudy"].tap()
        waitForPlayback(audio, timeout: 20) { $0["source"] as? String == "设备语音" && $0["playing"] as? Bool == true }
        XCTAssertTrue(app.staticTexts["Device voice"].exists)
        waitForPlayback(audio, timeout: 20) { state in
            (state["attemptedFile"] as? String)?.hasSuffix("after.wav") == true && state["playing"] as? Bool == true
        }
        waitForPlayback(audio) { $0["playing"] as? Bool == false }
    }

    func testLanguageSwitchPreservesImportedTextAndPersists() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tsv")
        try "#separator:tab\n#deck:原文\nあいさつ\t寒暄；打招呼。\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let app = launch(language: "zh-Hans", importing: file.path)
        app.buttons["tabSettings"].tap()
        let picker = app.buttons["interfaceLanguage"]
        picker.tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["tabDecks"].tap()
        XCTAssertTrue(app.staticTexts["Getting started with Anki"].waitForExistence(timeout: 5))
        app.buttons["tabCards"].tap()
        let search = app.textFields["cardSearch"]
        search.tap()
        search.typeText("あいさつ")
        XCTAssertTrue(app.staticTexts["あいさつ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '寒暄'")).firstMatch.exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "OPENANKI_IMPORT_FILE")
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertEqual(app.buttons["startStudy"].label, "Start studying")
        XCTAssertTrue(app.staticTexts["Getting started with Anki"].exists)
    }

    func testSettingsFooterSettlesAboveNavigation() {
        let app = launch()
        app.buttons["tabSettings"].tap()
        for _ in 0..<5 { app.swipeUp() }
        let footer = app.staticTexts["settingsAboutFootnote"]
        XCTAssertTrue(footer.exists)
        XCTAssertLessThan(footer.frame.maxY, app.buttons["tabSettings"].frame.minY - 8)
    }

    func testSystemTabBarPreservesSearchAndKeepsVolumeInSettings() throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = try launchReviewer(diagnostics: file, fixture: "media")
        XCTAssertTrue(app.tabBars.firstMatch.exists, app.debugDescription)
        app.buttons["tabSettings"].tap()
        XCTAssertTrue(app.staticTexts["Playback volume"].waitForExistence(timeout: 5))
        app.buttons["tabCards"].tap()
        let search = app.textFields["cardSearch"]
        search.tap()
        search.typeText("deck:\"Video playback\"")
        XCTAssertTrue(app.staticTexts["1 cards"].waitForExistence(timeout: 10))
        for tab in ["tabDecks", "tabSettings", "tabCards"] { app.buttons[tab].tap() }
        XCTAssertEqual(search.value as? String, "deck:\"Video playback\"")
        XCTAssertTrue(app.staticTexts["1 cards"].exists)
        openDeck("Video playback", app: app)
        app.buttons["deckStartStudy"].tap()
        XCTAssertTrue(app.buttons["readWord"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Playback volume"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "review-without-per-card-volume-slider"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testUnsupportedSystemLanguageUsesEnglish() {
        let app = launch(language: "ja-JP")
        XCTAssertEqual(app.buttons["startStudy"].label, "Start studying")
        XCTAssertTrue(app.staticTexts["Getting started with Anki"].exists)
        XCTAssertFalse(app.staticTexts["日常英语"].exists)
        XCTAssertFalse(app.staticTexts["Swift 随手记"].exists)
    }

    func testExternalDeckBackgroundRatingsAdvanceAndUndoRestoresTheNativeCard() throws {
        guard let path = ProcessInfo.processInfo.environment["OPENANKI_TEST_APKG"] else {
            throw XCTSkip("Set OPENANKI_TEST_APKG to test a local package.")
        }
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { attachReviewerDiagnostics(file); try? FileManager.default.removeItem(at: file) }
        let app = launch(importing: path, reviewerDiagnostics: file.path)
        app.buttons["startStudy"].tap()
        func cardID(_ state: [String: Any]) -> String? {
            ((state["queued"] as? [String: Any])?["card"] as? [String: Any])?["id"] as? String
        }
        waitForPlayback(file) { cardID($0) != nil && $0["side"] as? String == "question" }
        var lastAnswered = ""
        for rating in [2, 3, 4] {
            lastAnswered = try XCTUnwrap(cardID(reviewerState(file)))
            app.buttons["showAnswer"].tap()
            let button = app.buttons["rating\(rating)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            waitForPlayback(file) { state in
                cardID(state) != nil && cardID(state) != lastAnswered && state["side"] as? String == "question"
            }
            XCTAssertTrue(app.buttons["showAnswer"].exists)
        }
        app.buttons["undoReview"].tap()
        waitForPlayback(file) { cardID($0) == lastAnswered && $0["side"] as? String == "question" }
    }

    func testForegroundMediaSessionAndBoostAreRetainedUntilBackground() throws {
        continueAfterFailure = false
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-data"]
        app.launchEnvironment["OPENANKI_AUDIO_DIAGNOSTICS_FILE"] = file.path
        app.launch()
        XCTAssertTrue(app.buttons["startStudy"].waitForExistence(timeout: 10))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(state["category"] as? String, "AVAudioSessionCategoryPlayback")
        XCTAssertEqual(state["foreground"] as? Bool, true)
        XCTAssertEqual(state["sessionActive"] as? Bool, true)
        XCTAssertEqual(state["gainDB"] as? Double, 6)
        XCTAssertEqual(state["peakLimiter"] as? Bool, true)
        XCUIDevice.shared.press(.home)
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return object["sessionActive"] as? Bool == false
        }, object: nil)
        wait(for: [released], timeout: 5)
    }

}
