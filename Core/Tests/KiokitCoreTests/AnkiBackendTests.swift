import Foundation
import XCTest
@testable import KiokitCore

final class AnkiBackendTests: XCTestCase {
    func testOfficialBackendCreatesRendersSchedulesAndUndoesCard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = try AnkiBackend()
        try backend.call("anki.collection.OpenCollection", [
            "collectionPath": .string(directory.appendingPathComponent("collection.anki2").path),
            "mediaFolderPath": .string(directory.appendingPathComponent("collection.media").path),
            "mediaDbPath": .string(directory.appendingPathComponent("collection.media.db2").path),
        ])
        defer { _ = try? backend.call("anki.collection.CloseCollection") }
        let defaults = try backend.call("anki.notes.DefaultsForAdding")
        let deckID = defaults["deckId"].int
        let noteTypeID = defaults["notetypeId"].int
        var note = try backend.call("anki.notes.NewNote", ["ntid": .id(noteTypeID)]).object
        note["fields"] = ["日本語", "中文翻译"]
        let added = try backend.call("anki.notes.AddNote", ["note": .object(note), "deckId": .id(deckID)])
        let ids = try backend.call("anki.notes.CardsOfNote", ["nid": added["noteId"]])["cids"].array
        let cardID = try XCTUnwrap(ids.first)
        let rendered = try backend.call("anki.card_rendering.RenderExistingCard", ["cardId": cardID, "partialRender": false])
        XCTAssertTrue(rendered["questionNodes"].array.contains { $0["text"].string.contains("日本語") })
        let queue = try backend.call("anki.scheduler.GetQueuedCards", ["fetchLimit": 1])
        let queued = try XCTUnwrap(queue["cards"].array.first)
        XCTAssertEqual(queued["card"]["id"], cardID)
        let states = queued["states"]
        try backend.call("anki.scheduler.AnswerCard", [
            "cardId": cardID, "currentState": states["current"], "newState": states["good"],
            "rating": "GOOD", "answeredAtMillis": .id(Int64(Date.now.timeIntervalSince1970 * 1000)), "millisecondsTaken": 1250,
        ])
        let reviewed = try backend.call("anki.cards.GetCard", ["cid": cardID])
        XCTAssertEqual(reviewed["reps"].int, 1)
        let logs = try backend.call("anki.stats.GetReviewLogs", ["cid": cardID])
        XCTAssertEqual(logs["entries"].array.count, 1)
        try backend.call("anki.collection.Undo")
        let restored = try backend.call("anki.cards.GetCard", ["cid": cardID])
        XCTAssertEqual(restored["reps"].int, 0)
        XCTAssertEqual(restored["ctype"].int, 0)
        let afterUndo = try backend.call("anki.stats.GetReviewLogs", ["cid": cardID])
        XCTAssertTrue(afterUndo["entries"].array.isEmpty)
    }

    func testUpstreamErrorsReachSwiftWithoutReplacementRules() throws {
        let backend = try AnkiBackend()
        XCTAssertThrowsError(try backend.call("anki.cards.GetCard", ["cid": .id(999)])) { error in
            XCTAssertEqual((error as? AnkiBackendError)?.kind, "INVALID_INPUT")
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
