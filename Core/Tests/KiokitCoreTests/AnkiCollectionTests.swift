import Foundation
import XCTest
@testable import KiokitCore

final class AnkiCollectionTests: XCTestCase {
    private func collection() throws -> AnkiCollection {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let collection = try AnkiCollection(directory: directory)
        addTeardownBlock { _ = try? collection.close(); try? FileManager.default.removeItem(at: directory) }
        return collection
    }

    private func addBasicNote(_ collection: AnkiCollection, deckID: Int64, front: String = "日本語", back: String = "中文翻译") throws -> Int64 {
        let defaults = try collection.backend.call("anki.notes.DefaultsForAdding")
        var note = try collection.newNote(noteTypeID: defaults["notetypeId"].int).object
        note["fields"] = .array([.string(front), .string(back)])
        let noteID = try collection.addNote(.object(note), deckID: deckID)
        return try XCTUnwrap(collection.backend.call("anki.notes.CardsOfNote", ["nid": .id(noteID)])["cids"].array.first).int
    }

    func testDetailsBackOmitsFrontSideWithoutChangingReviewerOrNativeData() throws {
        let collection = try collection()
        let deckID = try collection.addDeck(name: "Details")
        let cardID = try addBasicNote(collection, deckID: deckID)
        let before = try collection.card(cardID)
        let original = try collection.renderedCard(cardID)
        let details = try collection.renderedCard(cardID, includeFrontSide: false)
        XCTAssertEqual(details["question"], original["question"])
        XCTAssertFalse(details["answer"]["text"].string.contains("日本語"))
        XCTAssertTrue(details["answer"]["text"].string.contains("中文翻译"))
        XCTAssertEqual(try collection.card(cardID), before)
        XCTAssertEqual(try collection.renderedCard(cardID), original)

        // Custom templates need no separator marker. Only native FrontSide
        // replacement nodes are omitted; literal matching answer text stays.
        let noteID = before["noteId"].int
        let note = try collection.note(noteID)
        var type = try collection.noteType(note["notetypeId"].int).object
        var templates = type["templates"]!.array
        var template = templates[0].object
        var config = template["config"]!.object
        config["aFormat"] = "<section>{{FrontSide}}</section><b>{{Back}}</b><i>{{Front}}</i>"
        template["config"] = .object(config)
        templates[0] = .object(template)
        type["templates"] = .array(templates)
        _ = try collection.backend.call("anki.notetypes.UpdateNotetype", .object(type))
        let custom = try collection.renderedCard(cardID, includeFrontSide: false)
        XCTAssertEqual(custom["answer"]["text"].string, "<section></section><b>中文翻译</b><i>日本語</i>")
        XCTAssertTrue(try collection.renderedCard(cardID)["answer"]["text"].string.contains("<section>日本語</section>"))
    }

    func testNativeCRUDRenderingSchedulingAndReviewStatistics() throws {
        let collection = try collection()
        XCTAssertEqual(try collection.applicationMetadata(), [:])
        let deckID = try collection.addDeck(name: "原文牌组")
        try collection.selectDeck(deckID)
        let cardID = try addBasicNote(collection, deckID: deckID)
        let render = try collection.renderedCard(cardID)
        XCTAssertTrue(render["question"]["text"].string.contains("日本語"))
        XCTAssertTrue(render["answer"]["text"].string.contains("日本語"))
        XCTAssertTrue(render["answer"]["text"].string.contains("中文翻译"))
        let first = try XCTUnwrap(collection.queue()["cards"].array.first)
        XCTAssertEqual(first["card"]["id"].int, cardID)
        XCTAssertEqual(try collection.describeIntervals(first["states"]).count, 4)
        try collection.answer(first, rating: .good, millisecondsTaken: 2000)
        XCTAssertEqual(try collection.card(cardID)["reps"].int, 1)
        XCTAssertEqual(try collection.statistics()["today"]["answerCount"].int, 1)
        try collection.undo()
        XCTAssertEqual(try collection.card(cardID)["reps"].int, 0)
        XCTAssertEqual(try collection.statistics()["today"]["answerCount"].int, 0)
        try collection.suspendCards([cardID])
        XCTAssertEqual(try collection.card(cardID)["queue"].int, -1)
        try collection.restoreCards([cardID])
        XCTAssertEqual(try collection.card(cardID)["queue"].int, 0)
        let otherID = try collection.addDeck(name: "Other")
        try collection.moveCards([cardID], to: otherID)
        XCTAssertEqual(try collection.card(cardID)["deckId"].int, otherID)
        try collection.renameDeck(otherID, name: "Renamed")
        XCTAssertEqual(try collection.deck(otherID)["name"].string, "Renamed")
        try collection.removeCards([cardID])
        XCTAssertTrue(try collection.searchCards("").isEmpty)
    }

    func testNativeDeckOptionsAndCollectionBackupPreserveSettingsAndProgress() throws {
        let collection = try collection()
        let deckID = try collection.addDeck(name: "Options")
        try collection.selectDeck(deckID)
        let cardID = try addBasicNote(collection, deckID: deckID)
        let options = try collection.deckOptions(deckID)
        let currentID = options["currentDeck"]["configId"].int
        var config = try XCTUnwrap(options["allConfig"].array.first { $0["config"]["id"].int == currentID })["config"].object
        var values = config["config"]!.object
        values["newCardGatherPriority"] = "NEW_CARD_GATHER_PRIORITY_RANDOM_CARDS"
        values["newCardSortOrder"] = "NEW_CARD_SORT_ORDER_RANDOM_CARD"
        values["reviewOrder"] = "REVIEW_CARD_ORDER_RANDOM"
        values["reviewsPerDay"] = 2500
        config["config"] = .object(values)
        var flags = options.object
        flags["fsrs"] = true
        try collection.saveDeckOptions(deckID, config: .object(config), limits: ["new": 1234], options: .object(flags))
        try collection.saveApplicationMetadata(["interfaceLanguage": "zh-Hans", "appearance": "dark"])
        let queued = try XCTUnwrap(collection.queue()["cards"].array.first)
        XCTAssertFalse(queued["states"]["easy"]["normal"]["review"]["memoryState"].isNull)
        try collection.answer(queued, rating: .easy, millisecondsTaken: 3000)
        let beforeCard = try collection.card(cardID)
        let beforeOptions = try collection.deckOptions(deckID)
        XCTAssertEqual(beforeOptions["currentDeck"]["limits"]["new"].int, 1234)
        let backup = collection.directory.appendingPathComponent("backup.colpkg")
        try collection.exportCollection(to: backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try collection.card(cardID), beforeCard, "Export must reopen the collection")
        try collection.removeCards([cardID])
        try collection.restoreCollection(from: backup)
        XCTAssertEqual(try collection.card(cardID), beforeCard)
        XCTAssertEqual(try collection.deckOptions(deckID)["currentDeck"]["limits"], beforeOptions["currentDeck"]["limits"])
        XCTAssertEqual(try collection.applicationMetadata()["interfaceLanguage"].string, "zh-Hans")
        XCTAssertEqual(try collection.statistics()["today"]["answerCount"].int, 1)
    }

    func testNativeTextImportPreservesAnkiHeadersAndGeneratesCards() throws {
        let collection = try collection()
        let file = collection.directory.appendingPathComponent("Japanese.tsv")
        try "#separator:tab\n#html:true\n#deck:原文\n<b>日本語</b>\t中文翻译\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try collection.importText(file)
        let cards = try collection.searchCards("")
        XCTAssertEqual(cards.count, 1)
        let cardID = try XCTUnwrap(cards.first)
        let rendered = try collection.renderedCard(cardID)
        XCTAssertTrue(rendered["question"]["text"].string.contains("<b>日本語</b>"))
        XCTAssertTrue(rendered["answer"]["text"].string.contains("中文翻译"))
        XCTAssertTrue(try collection.deckNames().contains { $0["name"].string == "原文" })
    }

    func testUserProvidedPackageThroughOfficialImporter() throws {
        guard let path = ProcessInfo.processInfo.environment["OPENANKI_TEST_APKG"] else { throw XCTSkip("Set OPENANKI_TEST_APKG to test a local package.") }
        let collection = try collection()
        _ = try collection.importPackage(URL(fileURLWithPath: path))
        let cards = try collection.searchCards("")
        XCTAssertGreaterThan(cards.count, 0)
        let media = try FileManager.default.contentsOfDirectory(at: collection.mediaURL, includingPropertiesForKeys: nil)
        XCTAssertGreaterThan(media.count, 0)
        let projection = try collection.presentation(settings: StudySettings(), metadata: [:])
        XCTAssertEqual(projection.cards.count, cards.count)
        XCTAssertTrue(projection.cards.allSatisfy { $0.ankiID != nil && $0.ankiNoteID != nil && $0.ankiNoteTypeID != nil })
        for example in projection.cards.prefix(12) {
            let note = try collection.note(try XCTUnwrap(example.ankiNoteID))
            XCTAssertEqual(example.noteFields?.map(\.value), note["fields"].array.map(\.string))
            XCTAssertEqual(example.backPreview, try collection.browserTextLine(AnkiFrontend.stripAudioReferences(example.back)))
        }
    }

    func testTemplateErrorIsRenderedOnItsCardWithoutFailingCollection() throws {
        let collection = try collection()
        let cardID = try addBasicNote(collection, deckID: 1)
        let card = try collection.card(cardID)
        let note = try collection.note(card["noteId"].int)
        let response = try collection.backend.call("anki.notetypes.GetNotetypeLegacy", ["ntid": note["notetypeId"]])
        let data = try XCTUnwrap(Data(base64Encoded: response["json"].string))
        var type = try JSONDecoder().decode(AnkiJSON.self, from: data).object
        var templates = type["tmpls"]!.array
        var first = templates[0].object
        first["qfmt"] = "{{UnknownField}}"
        templates[0] = .object(first)
        type["tmpls"] = .array(templates)
        let updated = try JSONEncoder().encode(AnkiJSON.object(type)).base64EncodedString()
        try collection.backend.call("anki.notetypes.UpdateNotetypeLegacy", ["json": .string(updated), "skipChecks": true])
        XCTAssertThrowsError(try collection.backend.call("anki.card_rendering.RenderExistingCard", ["cardId": .id(cardID), "partialRender": false])) { error in
            XCTAssertEqual((error as? AnkiBackendError)?.kind, "TEMPLATE_PARSE")
        }
        let rendered = try collection.renderedCard(cardID)
        XCTAssertTrue(rendered["question"]["text"].string.contains("UnknownField"))
        XCTAssertEqual(rendered["question"], rendered["answer"])
        XCTAssertEqual(rendered["css"].string, "")
        XCTAssertTrue(rendered["question"]["avTags"].array.isEmpty)
        let snapshot = try collection.presentation(settings: StudySettings(), metadata: [:])
        XCTAssertEqual(snapshot.cards.count, 1)
    }

    func testFrontSideKeepsQuestionAudioReferencesOutOfAnswerAudioTags() throws {
        let collection = try collection()
        let card = try addBasicNote(collection, deckID: 1, front: "Question [sound:q.mp3]", back: "Answer [sound:a.mp3]")
        let render = try collection.renderedCard(card)
        XCTAssertEqual(render["question"]["avTags"].array.map { $0["soundOrVideo"].string }, ["q.mp3"])
        XCTAssertEqual(render["answer"]["avTags"].array.map { $0["soundOrVideo"].string }, ["a.mp3"])
        XCTAssertTrue(render["answer"]["text"].string.contains("[anki:play:q:0]"))
        XCTAssertTrue(render["answer"]["text"].string.contains("[anki:play:a:0]"))
    }
}
