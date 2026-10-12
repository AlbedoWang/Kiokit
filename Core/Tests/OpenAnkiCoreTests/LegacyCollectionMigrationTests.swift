import Foundation
import XCTest
@testable import OpenAnkiCore

final class LegacyCollectionMigrationTests: XCTestCase {
    func testLegacyCardsHistoryMediaNamespacesAndOriginalArchiveArePreserved() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = Deck(name: "First")
        let second = Deck(name: "Second")
        var reviewed = Flashcard(deckID: first.id, front: "日本語 [sound:word.mp3]", back: "中文翻译", isHTML: true, mediaFolder: "first")
        let previous = reviewed
        reviewed.stage = .review; reviewed.interval = 4; reviewed.repetitions = 1
        reviewed.due = Date.now.addingTimeInterval(4 * 86400); reviewed.lastReviewedAt = .now
        var suspended = Flashcard(deckID: second.id, front: "Other [sound:word.mp3]", back: "Original", isHTML: true, mediaFolder: "second")
        suspended.isSuspended = true
        let snapshot = CollectionSnapshot(decks: [first, second], cards: [reviewed, suspended], reviews: [ReviewRecord(card: previous, rating: .easy, date: .now, duration: 3)])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let collectionURL = root.appendingPathComponent("collection.json")
        try JSONEncoder().encode(snapshot).write(to: collectionURL)
        for (folder, bytes) in [("first", Data("recording-one".utf8)), ("second", Data("recording-two".utf8))] {
            let directory = root.appendingPathComponent("Media").appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: directory.appendingPathComponent("word.mp3"))
        }
        let original = try Data(contentsOf: collectionURL)
        try LegacyCollectionMigration.migrate(directory: root)
        XCTAssertEqual(try Data(contentsOf: collectionURL), original)
        let native = try AnkiCollection(directory: root)
        defer { try? native.close() }
        let cards = try native.searchCards("")
        XCTAssertEqual(cards.count, 2)
        let projection = try native.presentation(settings: StudySettings(), metadata: native.applicationMetadata())
        let restored = try XCTUnwrap(projection.cards.first { $0.backPreview.contains("中文翻译") })
        XCTAssertEqual(restored.stage, .review)
        XCTAssertEqual(restored.repetitions, 1)
        XCTAssertEqual(restored.interval, 4)
        XCTAssertEqual(try native.backend.call("anki.stats.GetReviewLogs", ["cid": .id(restored.ankiID!)])["entries"].array.count, 1)
        XCTAssertEqual(projection.cards.filter(\.isSuspended).count, 1)
        let recordings = try FileManager.default.contentsOfDirectory(at: native.mediaURL, includingPropertiesForKeys: nil).map { try Data(contentsOf: $0) }
        XCTAssertTrue(recordings.contains(Data("recording-one".utf8)))
        XCTAssertTrue(recordings.contains(Data("recording-two".utf8)))
        XCTAssertEqual(try native.statistics()["today"]["answerCount"].int, 1)
        let archive = try native.backend.call("anki.config.GetConfigJson", ["val": "openAnki.legacyArchive"])["json"].string
        let encoded = try JSONDecoder().decode(String.self, from: XCTUnwrap(Data(base64Encoded: archive)))
        XCTAssertEqual(Data(base64Encoded: encoded), original)
    }

    func testEmptyLegacyDeckDoesNotDisappear() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(CollectionSnapshot(decks: [Deck(name: "Empty")])).write(to: root.appendingPathComponent("collection.json"))
        try LegacyCollectionMigration.migrate(directory: root)
        let native = try AnkiCollection(directory: root)
        defer { try? native.close() }
        XCTAssertTrue(try native.deckNames().contains { $0["name"].string == "Empty" })
        XCTAssertTrue(try native.searchCards("").isEmpty)
    }
}
