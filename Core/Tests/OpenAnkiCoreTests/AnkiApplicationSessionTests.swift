import Foundation
import XCTest
@testable import OpenAnkiCore

@MainActor final class AnkiApplicationSessionTests: XCTestCase {
    private func session() throws -> AnkiApplicationSession {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = try AnkiApplicationSession(directory: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return session
    }

    func testApplicationUsesUpstreamQueueStatesStatisticsAndUndo() async throws {
        let session = try session()
        XCTAssertEqual(session.snapshot.cards.count, 4)
        XCTAssertEqual(session.snapshot.settings.newCardsPerDay, 20)
        XCTAssertEqual(session.snapshot.settings.dailyGoal, 200)
        try session.beginReview(deckID: session.snapshot.decks.first?.id)
        let first = try XCTUnwrap(session.currentCard)
        let queued = try XCTUnwrap(session.queuedCard)
        XCTAssertEqual(session.intervalLabels, try session.collection.describeIntervals(queued["states"]))
        try session.answer(rating: .good, duration: 2)
        XCTAssertEqual(session.statistics["today"]["answerCount"].int, 1)
        XCTAssertEqual(try session.collection.card(first.ankiID!)["reps"].int, 1)
        try session.undo()
        XCTAssertEqual(session.currentCard?.ankiID, first.ankiID)
        XCTAssertEqual(session.statistics["today"]["answerCount"].int, 0)
        XCTAssertEqual(try session.collection.card(first.ankiID!)["reps"].int, 0)
    }

    func testExternalDeckBackgroundReviewsMatchNativePresentation() async throws {
        guard let path = ProcessInfo.processInfo.environment["OPENANKI_TEST_APKG"] else {
            throw XCTSkip("Set OPENANKI_TEST_APKG to benchmark a local collection.")
        }
        let session = try session()
        _ = try session.collection.importPackage(URL(fileURLWithPath: path))
        try session.refresh()
        let deck = try XCTUnwrap(session.snapshot.decks.first { $0.builtInID == nil && session.cardCount(for: $0.id) > 1000 })
        try session.beginReview(deckID: deck.id)
        for rating in [ReviewRating.hard, .good, .easy] {
            let start = ContinuousClock.now
            try await session.answerInBackground(rating: rating)
            let elapsed = start.duration(to: .now)
            print("External deck review \(rating): \(elapsed)")
            let comparisonStarted = Date.now
            let native = try session.collection.presentation(settings: session.snapshot.settings, metadata: session.collection.applicationMetadata())
            print("External deck native presentation: \(Date.now.timeIntervalSince(comparisonStarted)) seconds")
            let expected = Dictionary(uniqueKeysWithValues: native.cards.map { ($0.id, $0) })
            for card in session.snapshot.cards {
                let actualJSON = try JSONDecoder().decode(AnkiJSON.self, from: JSONEncoder().encode(card))
                let expectedJSON = try JSONDecoder().decode(AnkiJSON.self, from: JSONEncoder().encode(expected[card.id]!))
                // Native CardStats derives day-queue display timestamps from
                // its current wall clock; two projections run at different times.
                XCTAssertLessThanOrEqual(abs(card.due.timeIntervalSince(expected[card.id]!.due)), Date.now.timeIntervalSince(comparisonStarted) + 2)
                let differences = actualJSON.object.keys.filter { $0 != "due" && actualJSON[$0] != expectedJSON[$0] }.sorted()
                XCTAssertTrue(differences.isEmpty, "Native projection differences for \(card.ankiID!): \(differences)")
            }
            XCTAssertEqual(session.statistics, try session.collection.statistics())
        }
    }

    func testBackgroundAnswerKeepsNativeStatesAndAllowsMainActorWork() async throws {
        let session = try session()
        try session.beginReview(deckID: session.snapshot.decks.first?.id)
        let first = try XCTUnwrap(session.currentCard)
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }
        try await session.answerInBackground(rating: .hard)
        XCTAssertTrue(mainActorRan, "Native answering must not monopolize the UI actor.")
        await heartbeat.value
        let native = try session.collection.card(first.ankiID!)
        XCTAssertEqual(native["reps"].int, 1)
        XCTAssertEqual(session.statistics, try session.collection.statistics())
        let rendered = try session.collection.renderedCard(first.ankiID!)
        let presented = try XCTUnwrap(session.snapshot.cards.first { $0.id == first.id })
        XCTAssertEqual(presented.front, rendered["question"]["text"].string)
        XCTAssertEqual(presented.repetitions, Int(native["reps"].int))
        try session.undo()
        XCTAssertEqual(session.currentCard?.id, first.id)
        XCTAssertEqual(try session.collection.card(first.ankiID!)["reps"].int, 0)
    }

    func testPresentationCacheInvalidatesNativeNotesTemplatesDeckNamesAndFlags() async throws {
        let session = try session()
        let collection = session.collection
        let card = try XCTUnwrap(session.snapshot.cards.first)
        let deckID = try XCTUnwrap(session.snapshot.decks.first?.ankiID)
        let cardID = try XCTUnwrap(card.ankiID)
        let metadata = try collection.applicationMetadata()
        var type = try collection.noteType(card.ankiNoteTypeID!).object
        var templates = type["templates"]!.array
        var template = templates[0].object
        var templateConfig = template["config"]!.object
        templateConfig["qFormat"] = "{{Deck}} {{CardFlag}} {{Front}} {{Tags}}"
        template["config"] = .object(templateConfig)
        templates[0] = .object(template)
        type["templates"] = .array(templates)
        _ = try collection.backend.call("anki.notetypes.UpdateNotetype", .object(type))
        for change in 0..<4 {
            switch change {
            case 1:
                var note = try collection.note(card.ankiNoteID!).object
                var fields = note["fields"]!.array
                fields[0] = "Original changed field"
                note["fields"] = .array(fields)
                note["tags"] = ["OriginalTag"]
                try collection.updateNote(.object(note))
            case 2: try collection.renameDeck(deckID, name: "Original renamed deck")
            case 3: _ = try collection.backend.call("anki.cards.SetFlag", ["cardIds": [.id(cardID)], "flag": 2])
            default: break
            }
            let cached = try collection.presentation(settings: session.snapshot.settings, metadata: metadata, reuseUnchangedCards: true)
            let fresh = try collection.presentation(settings: session.snapshot.settings, metadata: metadata)
            XCTAssertEqual(cached.cards, fresh.cards)
            XCTAssertEqual(cached.decks, fresh.decks)
        }
    }

    func testReviewClockStartsWithQueuedCardSurvivesNoteRedrawAndRestartsAfterUndo() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var now = 100.0
        let session = try AnkiApplicationSession(directory: root, reviewClock: { now })
        let deck = try XCTUnwrap(session.snapshot.decks.first)
        try session.beginReview(deckID: deck.id)
        let card = try XCTUnwrap(session.currentCard)
        XCTAssertEqual(session.reviewTimer?.startedAt, 100)
        now = 103.8
        var fields = card.noteFields!
        fields[0].value = "Edited without resetting the native card timer"
        try session.saveNote(card: card, deckID: deck.ankiID!, noteTypeID: card.ankiNoteTypeID!, fields: fields, tags: "")
        XCTAssertEqual(session.currentCard?.id, card.id)
        XCTAssertEqual(session.reviewTimer?.startedAt, 100)
        try session.undo()
        XCTAssertEqual(session.reviewTimer?.startedAt, 100)
        now = 112.9999
        try session.answer(rating: .easy)
        let log = try session.collection.backend.call("anki.stats.GetReviewLogs", ["cid": .id(card.ankiID!)])["entries"].array
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0]["takenSecs"].double, 12.999, accuracy: 0.001)
        XCTAssertEqual(session.reviewTimer?.startedAt, now)
        now = 120
        try session.undo()
        XCTAssertEqual(session.currentCard?.id, card.id)
        XCTAssertEqual(session.reviewTimer?.startedAt, 120)
        session.endReview()
        XCTAssertNil(session.reviewTimer)
    }

    func testAnswerTimeCapAndInvalidElapsedValuesRemainNativeBackendRules() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var now = 100.0
        let session = try AnkiApplicationSession(directory: root, reviewClock: { now })
        let deck = try XCTUnwrap(session.snapshot.decks.first)
        try session.savePresetValue(2, key: "capAnswerTimeToSecs", deck: deck)
        try session.beginReview(deckID: deck.id)
        let card = try XCTUnwrap(session.currentCard)
        XCTAssertThrowsError(try session.answer(rating: .easy, duration: -1))
        XCTAssertThrowsError(try session.answer(rating: .easy, duration: 4_294_968))
        XCTAssertEqual(try session.collection.card(card.ankiID!)["reps"].int, 0)
        now = 500
        XCTAssertEqual(try session.reviewTimer?.timeTaken(at: now, capped: false, timeLimitMilliseconds: 0), 400_000)
        try session.answer(rating: .easy)
        let log = try session.collection.backend.call("anki.stats.GetReviewLogs", ["cid": .id(card.ankiID!)])["entries"].array
        XCTAssertEqual(log[0]["takenSecs"].double, 2)
    }

    func testStatisticsFrontendUsesNativeScopesHistoryPreferencesAndProtobuf() async throws {
        let session = try session()
        let backend = session.collection.backend
        let deck = try XCTUnwrap(session.snapshot.decks.first)
        try session.beginReview(deckID: deck.id)
        try session.answer(rating: .easy, duration: 2.5)
        for search in ["deck:current", "", "is:new", "is:suspended"] {
            for days in [365, 0] {
                let request: AnkiJSON = ["search": .string(search), "days": .integer(Int64(days))]
                let bytes = try backend.encodeProtobuf("anki.stats.GraphsRequest", value: request)
                let result = try session.statisticsRequest(path: "/_anki/graphs", data: bytes)
                XCTAssertEqual(try backend.decodeProtobuf("anki.stats.GraphsResponse", data: result), try session.collection.statistics(search: search, days: days))
            }
        }
        let prefs: AnkiJSON = ["calendarFirstDayOfWeek": "FRIDAY", "cardCountsSeparateInactive": true, "futureDueShowBacklog": true, "browserLinksSupported": true]
        let data = try backend.encodeProtobuf("anki.stats.GraphPreferences", value: prefs)
        XCTAssertTrue(try session.statisticsRequest(path: "/_anki/setGraphPreferences", data: data).isEmpty)
        let encoded = try session.statisticsRequest(path: "/_anki/getGraphPreferences", data: Data())
        XCTAssertEqual(try backend.decodeProtobuf("anki.stats.GraphPreferences", data: encoded), try backend.call("anki.stats.GetGraphPreferences"))
        XCTAssertEqual(try backend.call("anki.stats.GetGraphPreferences"), prefs)
        XCTAssertEqual(session.statistics["today"]["answerCount"].int, 1)
        XCTAssertThrowsError(try session.statisticsRequest(path: "/_anki/unsupported", data: Data()))
    }

    func testNoteEditorDelegatesAllTagSeparatorsAndNormalizationToAnki() async throws {
        let session = try session()
        let deck = try XCTUnwrap(session.snapshot.decks.first)
        let type = try session.defaultNoteTypeID()
        for (index, text) in ["Alpha  beta\u{3000}Gamma Alpha", "alpha\u{00a0}beta", "alpha\u{2009}beta", "alpha\tbeta\nGamma", "日本語::階層 e\u{301}", ""].enumerated() {
            var expected = try session.collection.newNote(noteTypeID: type).object
            expected["fields"] = [.string("Native tag oracle \(index)"), "Original answer"]
            expected["tags"] = [.string(text)]
            let result = try session.collection.addNoteWithChanges(.object(expected), deckID: deck.ankiID!)
            let tags = try session.collection.note(result["noteId"].int)["tags"]
            var fields = try session.newNoteFields(noteTypeID: type)
            fields[0].value = "Editor tags \(index)"
            fields[1].value = "Original answer"
            try session.saveNote(card: nil, deckID: deck.ankiID!, noteTypeID: type, fields: fields, tags: text)
            let card = try XCTUnwrap(session.snapshot.cards.first { $0.noteFields?.first?.value == fields[0].value })
            XCTAssertEqual(try session.collection.note(card.ankiNoteID!)["tags"], tags, text)
        }
    }

    func testBrowserDeletionRemovesNativeNoteSiblingsRetainsLogsAndUndoRestoresCards() async throws {
        let session = try session()
        try session.saveDeck(Deck(name: "Native deletion"))
        let deck = try XCTUnwrap(session.snapshot.decks.first { $0.name == "Native deletion" })
        let reversed = try XCTUnwrap(session.noteTypes.first { type in
            (try? session.collection.noteType(type["id"].int))?["config"]["originalStockKind"].string == "ORIGINAL_STOCK_KIND_BASIC_AND_REVERSED"
        })
        var fields = try session.newNoteFields(noteTypeID: reversed["id"].int)
        fields[0].value = "Original sibling front"
        fields[1].value = "Original sibling answer"
        try session.saveNote(card: nil, deckID: deck.ankiID!, noteTypeID: reversed["id"].int, fields: fields, tags: "pair")
        let pair = session.snapshot.cards.filter { $0.tags.contains("pair") }
        XCTAssertEqual(pair.count, 2)
        let basic = try session.defaultNoteTypeID()
        var independent = try session.newNoteFields(noteTypeID: basic)
        independent[0].value = "Independent original note"
        independent[1].value = "Original answer"
        try session.saveNote(card: nil, deckID: deck.ankiID!, noteTypeID: basic, fields: independent, tags: "independent")
        try session.beginReview(deckID: deck.id)
        let reviewed = try XCTUnwrap(session.currentCard)
        XCTAssertTrue(pair.contains { $0.id == reviewed.id })
        try session.answer(rating: .easy, duration: 1.5)
        let originals = try pair.map { try session.collection.card($0.ankiID!) }
        let history = try session.collection.backend.call("anki.stats.GetReviewLogs", ["cid": .id(reviewed.ankiID!)])
        XCTAssertEqual(history["entries"].array.count, 1)
        try session.deleteNote(of: reviewed)
        XCTAssertFalse(session.snapshot.cards.contains { $0.ankiNoteID == reviewed.ankiNoteID })
        XCTAssertEqual(session.snapshot.cards.filter { $0.tags.contains("independent") }.count, 1)
        XCTAssertEqual(try session.collection.backend.call("anki.stats.GetReviewLogs", ["cid": .id(reviewed.ankiID!)]), history)
        try session.undo()
        XCTAssertEqual(try pair.map { try session.collection.card($0.ankiID!) }, originals)
        XCTAssertEqual(try session.collection.backend.call("anki.stats.GetReviewLogs", ["cid": .id(reviewed.ankiID!)]), history)
    }

    func testNativeLimitsAndPresetCloningPersistWithoutChangingOtherDecks() async throws {
        let session = try session()
        let guide = try XCTUnwrap(session.snapshot.decks.first)
        try session.saveDeck(Deck(name: "Independent"))
        let other = try XCTUnwrap(session.snapshot.decks.first { $0.name == "Independent" })
        try session.clonePreset(for: guide)
        try session.savePresetValue("NEW_CARD_SORT_ORDER_RANDOM_CARD", key: "newCardSortOrder", deck: guide)
        let guideConfig = try session.currentPreset(session.collection.deckOptions(guide.ankiID!))
        let otherConfig = try session.currentPreset(session.collection.deckOptions(other.ankiID!))
        XCTAssertNotEqual(guideConfig["id"], otherConfig["id"])
        XCTAssertEqual(guideConfig["config"]["newCardSortOrder"].string, "NEW_CARD_SORT_ORDER_RANDOM_CARD")
        XCTAssertNotEqual(otherConfig["config"]["newCardSortOrder"].string, "NEW_CARD_SORT_ORDER_RANDOM_CARD")
        try session.saveDeckLimit(1, key: "new", deck: guide)
        XCTAssertEqual(session.counts(for: guide.id).new, 1)
        try session.beginReview(deckID: guide.id)
        try session.answer(rating: .easy, duration: 1)
        XCTAssertEqual(session.counts(for: guide.id).new, 0)
        try session.undo()
        XCTAssertEqual(session.counts(for: guide.id).new, 1)
        try session.collection.close()
        let restored = try AnkiApplicationSession(directory: session.collection.directory)
        XCTAssertEqual(restored.counts(for: guide.id).new, 1)
    }

    func testNativeNoteFieldsCreateSiblingsAndEditingUpdatesBothCards() async throws {
        let session = try session()
        let deck = try XCTUnwrap(session.snapshot.decks.first)
        let reversed = try XCTUnwrap(session.noteTypes.first { type in
            let config = try? session.collection.noteType(type["id"].int)
            return config?["config"]["originalStockKind"].string == "ORIGINAL_STOCK_KIND_BASIC_AND_REVERSED"
        })
        var fields = try session.newNoteFields(noteTypeID: reversed["id"].int)
        fields[0].value = "日本語"
        fields[1].value = "中文翻译"
        try session.saveNote(card: nil, deckID: deck.ankiID!, noteTypeID: reversed["id"].int, fields: fields, tags: "test test")
        let pair = session.snapshot.cards.filter { $0.tags.contains("test") }
        XCTAssertEqual(pair.count, 2)
        XCTAssertEqual(pair[0].ankiNoteID, pair[1].ankiNoteID)
        fields[1].value = "保留中文"
        try session.saveNote(card: pair[0], deckID: deck.ankiID!, noteTypeID: reversed["id"].int, fields: fields, tags: "test")
        XCTAssertEqual(session.snapshot.cards.filter { $0.tags.contains("test") }.count, 2)
        XCTAssertTrue(session.snapshot.cards.filter { $0.tags.contains("test") }.allSatisfy { $0.noteFields?[1].value == "保留中文" })
        XCTAssertEqual(try session.search("tag:test", deckID: deck.id, stage: "new").count, 2)
    }

    func testOfficialFrontendStateMessagesPreserveMutationsThroughAnswerAndUndo() async throws {
        let session = try session()
        let script = "customData.good.count = 1;"
        let bytes = try JSONEncoder().encode(AnkiJSON.string(script))
        try session.collection.backend.call("anki.config.SetConfigJsonNoUndo", ["key": "cardStateCustomizer", "valueJson": .string(bytes.base64EncodedString())])
        try session.beginReview(deckID: session.snapshot.decks.first?.id)
        XCTAssertFalse(session.statesMutated)
        XCTAssertTrue(session.stateMutationJavaScript!.contains(script))
        let before = try XCTUnwrap(session.queuedCard)
        let response = try session.reviewerRequest(path: "/_anki/getSchedulingStatesWithContext", data: Data())
        let envelope = try session.collection.backend.decodeProtobuf("anki.frontend.SchedulingStatesWithContext", data: response)
        XCTAssertEqual(envelope["context"], before["context"])
        var states = envelope["states"].object
        var good = states["good"]!.object
        good["customData"] = "{\"count\":1}"
        states["good"] = .object(good)
        func request(key: String) throws -> Data {
            try session.collection.backend.encodeProtobuf("anki.frontend.SetSchedulingStatesRequest", value: ["key": .string(key), "states": .object(states)])
        }
        _ = try session.reviewerRequest(path: "/_anki/setSchedulingStates", data: request(key: "another reviewer"))
        XCTAssertEqual(session.queuedCard?["states"], before["states"])
        _ = try session.reviewerRequest(path: "/_anki/setSchedulingStates", data: request(key: session.stateMutationKey))
        XCTAssertEqual(session.queuedCard?["states"]["good"]["customData"].string, "{\"count\":1}")
        session.reviewerStatesMutated()
        try session.answer(rating: .good, duration: 1)
        XCTAssertEqual(try session.collection.card(before["card"]["id"].int)["customData"].string, "{\"count\":1}")
        try session.undo()
        XCTAssertEqual(try session.collection.card(before["card"]["id"].int)["customData"], before["card"]["customData"])
    }

    func testEditingAndUndoingNoteRedrawsWithoutReplacingSchedulingStates() async throws {
        let session = try session()
        try session.beginReview(deckID: session.snapshot.decks.first?.id)
        let original = try XCTUnwrap(session.currentCard)
        let states = try XCTUnwrap(session.queuedCard)["states"]
        let generation = session.reviewGeneration
        let textGeneration = session.reviewTextGeneration
        var fields = try XCTUnwrap(original.noteFields)
        fields[0].value = "Edited during review"
        fields[1].value = "Updated native answer"
        let deckID = try session.collection.card(original.ankiID!)["deckId"].int
        try session.saveNote(card: original, deckID: deckID, noteTypeID: original.ankiNoteTypeID!, fields: fields, tags: original.tags.joined(separator: " "))
        XCTAssertEqual(session.queuedCard?["states"], states)
        XCTAssertEqual(session.reviewGeneration, generation)
        XCTAssertGreaterThan(session.reviewTextGeneration, textGeneration)
        XCTAssertTrue(session.currentCard!.front.contains("Edited during review"))
        XCTAssertTrue(session.canUndo)
        XCTAssertTrue(session.undoTitle.contains("Edit note"))
        try session.undo()
        XCTAssertEqual(session.currentCard?.front, original.front)
        XCTAssertEqual(session.queuedCard?["states"], states)
        XCTAssertEqual(session.statistics["today"]["answerCount"].int, 0)
    }

    func testCardMoveAndSuspensionFollowUpstreamQueueChangeFlags() async throws {
        let session = try session()
        let guide = try XCTUnwrap(session.snapshot.decks.first)
        try session.saveDeck(Deck(name: "Destination"))
        let destination = try XCTUnwrap(session.snapshot.decks.first { $0.name == "Destination" })
        try session.beginReview(deckID: guide.id)
        let moved = try XCTUnwrap(session.currentCard)
        let generation = session.reviewGeneration
        try session.saveNote(card: moved, deckID: destination.ankiID!, noteTypeID: moved.ankiNoteTypeID!, fields: moved.noteFields!, tags: moved.tags.joined(separator: " "))
        XCTAssertGreaterThan(session.reviewGeneration, generation)
        XCTAssertNotEqual(session.currentCard?.id, moved.id)
        XCTAssertEqual(try session.collection.card(moved.ankiID!)["deckId"].int, destination.ankiID!)
        let suspended = try XCTUnwrap(session.currentCard)
        try session.toggleSuspended(suspended)
        XCTAssertNotEqual(session.currentCard?.id, suspended.id)
        XCTAssertEqual(try session.collection.card(suspended.ankiID!)["queue"].int, -1)
        try session.undo()
        XCTAssertEqual(session.currentCard?.id, suspended.id)
        session.endReview()
        XCTAssertNil(session.currentCard)
    }

    func testFilteredCardUsesOriginalDeckAudioConfiguration() async throws {
        let session = try session()
        let guide = try XCTUnwrap(session.snapshot.decks.first)
        try session.clonePreset(for: guide)
        try session.savePresetValue(true, key: "disableAutoplay", deck: guide)
        try session.savePresetValue(true, key: "skipQuestionWhenReplayingAnswer", deck: guide)
        let card = try XCTUnwrap(session.snapshot.cards.first)
        var filtered = try session.collection.backend.call("anki.decks.GetOrCreateFilteredDeck", ["did": .id(0)]).object
        filtered["name"] = "Filtered verification"
        var config = filtered["config"]!.object
        var term = try XCTUnwrap(config["searchTerms"]?.array.first).object
        term["search"] = .string("cid:\(card.ankiID!)")
        term["limit"] = 1
        config["searchTerms"] = .array([.object(term)])
        filtered["config"] = .object(config)
        let result = try session.collection.backend.call("anki.decks.AddOrUpdateFilteredDeck", .object(filtered))
        let filteredID = result["id"].int
        let rebuilt = try session.collection.backend.call("anki.scheduler.RebuildFilteredDeck", ["did": .id(filteredID)])
        XCTAssertEqual(rebuilt["count"].int, 1)
        try session.refresh()
        let displayed = try XCTUnwrap(session.snapshot.cards.first { $0.ankiID == card.ankiID })
        XCTAssertEqual(displayed.deckID, .anki(filteredID))
        XCTAssertEqual(displayed.ankiOriginalDeckID, guide.ankiID)
        XCTAssertEqual(displayed.ankiDeckConfiguration?["autoplay"].bool, false)
        XCTAssertEqual(displayed.ankiDeckConfiguration?["replayq"].bool, false)
        try session.beginReview(deckID: .anki(filteredID))
        XCTAssertEqual(session.currentCard?.ankiID, card.ankiID)
        try session.answer(rating: .easy, duration: 1)
        XCTAssertEqual(try session.collection.card(card.ankiID!)["deckId"].int, guide.ankiID!)
    }

    func testNativeDeckTreeSuppliesParentCardTotals() async throws {
        let session = try session()
        try session.saveDeck(Deck(name: "Parent::Child"))
        let parent = try XCTUnwrap(session.snapshot.decks.first { $0.name == "Parent" })
        let child = try XCTUnwrap(session.snapshot.decks.first { $0.name == "Parent::Child" })
        let type = try session.defaultNoteTypeID()
        var fields = try session.newNoteFields(noteTypeID: type)
        fields[0].value = "Child question"
        fields[1].value = "Child answer"
        try session.saveNote(card: nil, deckID: child.ankiID!, noteTypeID: type, fields: fields, tags: "")
        XCTAssertEqual(session.cardCount(for: parent.id), 1)
        XCTAssertEqual(session.cardCount(for: child.id), 1)
        XCTAssertEqual(session.counts(for: parent.id).new, session.counts(for: child.id).new)
    }

    func testInterfaceMetadataDoesNotClearNativeUndoHistory() async throws {
        let session = try session()
        try session.beginReview(deckID: session.snapshot.decks.first?.id)
        let card = try XCTUnwrap(session.currentCard)
        try session.answer(rating: .good, duration: 1)
        let undo = try session.collection.undoStatus()
        var metadata = try session.collection.applicationMetadata().object
        metadata["appearanceTest"] = "dark"
        try session.collection.saveApplicationMetadata(.object(metadata))
        let after = try session.collection.undoStatus()
        XCTAssertEqual(after["undo"], undo["undo"])
        XCTAssertEqual(after["redo"], undo["redo"])
        try session.undo()
        XCTAssertEqual(try session.collection.card(card.ankiID!)["reps"].int, 0)
    }

    func testFilteredPreviewAndOrderAvailabilityUseNativeConfiguration() async throws {
        let session = try session()
        let card = try XCTUnwrap(session.snapshot.cards.first)
        var request = try session.filteredDeckOptions(0).object
        request["name"] = "Native preview"
        var config = request["config"]!.object
        config["reschedule"] = false
        config["previewGoodSecs"] = 0
        config["searchTerms"] = [["search": .string("cid:\(card.ankiID!)"), "limit": 12000, "order": "RANDOM"]]
        request["config"] = .object(config)
        try session.saveFilteredDeck(.object(request))
        let deck = try XCTUnwrap(session.snapshot.decks.first { $0.name == "Native preview" })
        XCTAssertEqual(try session.filteredDeckOptions(deck.ankiID!)["config"]["searchTerms"].array[0]["limit"].int, 12000)
        XCTAssertFalse(try session.filteredOrderLabels().contains { [8, 9].contains($0.value) })
        let before = try session.collection.card(card.ankiID!)
        try session.beginReview(deckID: deck.id)
        XCTAssertFalse(session.queuedCard!["states"]["good"]["filtered"]["preview"].isNull)
        try session.answer(rating: .good, duration: 1)
        let after = try session.collection.card(card.ankiID!)
        XCTAssertEqual(after["reps"], before["reps"])
        XCTAssertEqual(after["ctype"], before["ctype"])
        try session.emptyFilteredDeck(deck.ankiID!)
        XCTAssertEqual(session.cardCount(for: deck.id), 0)
    }

    func testFreshCollectionUsesSystemLanguageForUpstreamStockTypes() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try AnkiApplicationSession(directory: root, preferredSystemLanguages: ["zh-Hans-CN"])
        let oracle = try AnkiCollection(directory: root.appendingPathComponent("oracle"), preferredLanguages: ["zh-CN"])
        defer { try? oracle.close() }
        XCTAssertEqual(session.noteTypes.map { $0["name"].string }, try oracle.noteTypes().map { $0["name"].string })
        XCTAssertEqual(session.snapshot.decks.first?.name, BuiltInDecks.initialCollection(locale: InterfaceLanguage.simplifiedChinese.locale()).decks.first?.name)
        try session.collection.close()
    }

    func testRestoringDuringReviewReloadsLanguageQueueAndRejectsOldMutationKey() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try AnkiApplicationSession(directory: root.appendingPathComponent("source"), preferredSystemLanguages: ["en"])
        var settings = source.snapshot.settings
        settings.interfaceLanguage = "zh-Hans"
        try source.saveSettings(settings)
        try source.beginReview(deckID: source.snapshot.decks.first?.id)
        let expected = try XCTUnwrap(source.queuedCard)["card"]["id"]
        let expectedIntervals = source.intervalLabels
        let archive = root.appendingPathComponent("restore.colpkg")
        try source.collection.exportCollection(to: archive)
        let target = try AnkiApplicationSession(directory: root.appendingPathComponent("target"), preferredSystemLanguages: ["en"])
        try target.beginReview(deckID: target.snapshot.decks.first?.id)
        let oldKey = target.stateMutationKey
        let generation = target.reviewGeneration
        try target.restoreCollection(from: archive)
        XCTAssertEqual(target.snapshot.settings.interfaceLanguage, "zh-Hans")
        XCTAssertEqual(target.queuedCard?["card"]["id"], expected)
        XCTAssertEqual(target.intervalLabels, expectedIntervals)
        XCTAssertGreaterThan(target.reviewGeneration, generation)
        XCTAssertNotEqual(target.stateMutationKey, oldKey)
        let states = target.queuedCard!["states"]
        let stale = try target.collection.backend.encodeProtobuf("anki.frontend.SetSchedulingStatesRequest", value: ["key": .string(oldKey), "states": [:]])
        _ = try target.reviewerRequest(path: "/_anki/setSchedulingStates", data: stale)
        XCTAssertEqual(target.queuedCard?["states"], states)
        XCTAssertFalse(target.canUndo)
        try source.collection.close()
        try target.collection.close()
    }
}
