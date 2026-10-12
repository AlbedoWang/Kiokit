import XCTest
@testable import OpenAnkiCore

final class ImportAndPersistenceTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "apkg", subdirectory: "Fixtures"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testLegacyPackageRendersReverseClozeAndExtractsMedia() throws {
        let imported = try AnkiPackageImporter.load(url: fixture("legacy"))
        defer { imported.cleanup() }
        XCTAssertEqual(imported.snapshot.decks.count, 2)
        XCTAssertEqual(imported.snapshot.cards.count, 4)
        XCTAssertTrue(imported.snapshot.cards.contains { $0.front.contains("capital") && $0.back.contains("Paris") })
        XCTAssertTrue(imported.snapshot.cards.contains { $0.front == "Paris" })
        XCTAssertTrue(imported.snapshot.cards.contains { $0.front.contains("[city]") && !$0.front.contains("London") })
        XCTAssertTrue(imported.snapshot.cards.contains { $0.front.contains("London") && $0.front.contains("[…]") })
        let folder = try XCTUnwrap(imported.snapshot.cards.first?.mediaFolder)
        let staging = try XCTUnwrap(imported.stagingDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("Media/\(folder)/pixel.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("Media/\(folder)/tone.wav").path))
    }

    func testModernPackageAndSuspension() throws {
        let imported = try AnkiPackageImporter.load(url: fixture("modern"))
        defer { imported.cleanup() }
        XCTAssertEqual(imported.snapshot.cards.count, 4)
        XCTAssertTrue(imported.snapshot.cards.allSatisfy { $0.stage == .new })
        XCTAssertEqual(imported.snapshot.cards.filter(\.isSuspended).count, 1)
        XCTAssertTrue(imported.snapshot.decks.contains { $0.name == "Languages::Cities" })
        XCTAssertTrue(imported.snapshot.cards.contains { $0.front.contains("[city]") })
    }

    func testRepeatedImportPreservesScheduling() throws {
        let first = try AnkiPackageImporter.load(url: fixture("legacy"))
        defer { first.cleanup() }
        let second = try AnkiPackageImporter.load(url: fixture("legacy"))
        defer { second.cleanup() }
        var current = first.snapshot
        current.cards[0] = Scheduler.answer(current.cards[0], rating: .easy)
        let merged = CollectionRepository.merging(second.snapshot, into: current)
        XCTAssertEqual(merged.added, 0)
        XCTAssertEqual(merged.skipped, 4)
        XCTAssertEqual(merged.snapshot.cards[0].stage, .review)
        XCTAssertEqual(merged.snapshot.decks.count, 2)
    }

    func testBackupRoundTripIncludesProgressAndMedia() throws {
        let source = CollectionRepository(directory: try temporaryDirectory())
        let imported = try AnkiPackageImporter.load(url: fixture("modern"))
        defer { imported.cleanup() }
        var snapshot = imported.snapshot
        let original = snapshot.cards[0]
        snapshot.cards[0] = Scheduler.answer(original, rating: .easy)
        snapshot.reviews.append(ReviewRecord(card: original, rating: .easy, date: .now, duration: 10))
        snapshot.settings.dailyGoal = 45
        try source.commit(imported, snapshot: snapshot)
        XCTAssertEqual(try source.load()?.cards[0].interval, 4)
        let file = try temporaryDirectory().appendingPathComponent("backup.openanki")
        try source.backup(snapshot).write(to: file)
        let backup = try DeckImporter.load(url: file)
        defer { backup.cleanup() }
        let restored = CollectionRepository(directory: try temporaryDirectory())
        try restored.commit(backup, snapshot: backup.snapshot)
        let loaded = try XCTUnwrap(restored.load())
        XCTAssertEqual(loaded.cards[0].interval, 4)
        XCTAssertEqual(loaded.reviews.count, 1)
        XCTAssertEqual(loaded.settings.dailyGoal, 45)
        let mediaPath = restored.mediaURL.appendingPathComponent(try XCTUnwrap(loaded.cards[0].mediaFolder)).appendingPathComponent("tone.wav")
        XCTAssertGreaterThan(try Data(contentsOf: mediaPath).count, 44)
    }

    func testInvalidSaveAndCorruptImportDoNotOverwriteCollection() throws {
        let repository = CollectionRepository(directory: try temporaryDirectory())
        let deck = Deck(name: "Keep me")
        let snapshot = CollectionSnapshot(decks: [deck])
        try repository.save(snapshot)
        let before = try Data(contentsOf: repository.collectionURL)
        var invalid = snapshot
        invalid.version = 999
        XCTAssertThrowsError(try repository.save(invalid))
        XCTAssertEqual(try Data(contentsOf: repository.collectionURL), before)
        let bad = repository.directory.appendingPathComponent("bad.apkg")
        try Data("not a zip".utf8).write(to: bad)
        XCTAssertThrowsError(try DeckImporter.load(url: bad))
        XCTAssertEqual(try Data(contentsOf: repository.collectionURL), before)
    }

    func testUnsafeMediaNameIsRejected() throws {
        XCTAssertThrowsError(try AnkiPackageImporter.load(url: fixture("unsafe-media")))
    }

    func testCSVMultilineEscapingAndAnkiTSVHeaders() throws {
        let csv = "Front,Back,Tags\n\"hello, world\",\"line one\nline two with \"\"quotes\"\"\",tag\n"
        let imported = try TextDeckImporter.load(data: Data(csv.utf8), name: "CSV")
        XCTAssertEqual(imported.snapshot.cards.count, 1)
        XCTAssertEqual(imported.snapshot.cards[0].front, "hello, world")
        XCTAssertEqual(imported.snapshot.cards[0].back, "line one\nline two with \"quotes\"")
        let tsv = "#separator:tab\n#html:true\n#deck:Test Deck\n<b>Q</b>\tA\ttag1 tag2\n"
        let text = try TextDeckImporter.load(data: Data(tsv.utf8), name: "Fallback")
        XCTAssertEqual(text.snapshot.decks[0].name, "Test Deck")
        XCTAssertTrue(text.snapshot.cards[0].isHTML)
        XCTAssertEqual(text.snapshot.cards[0].tags, ["tag1", "tag2"])
        XCTAssertThrowsError(try TextDeckImporter.load(data: Data("\"unclosed,A".utf8), name: "Invalid"))
    }

    func testConditionalTemplateAndAudioEscaping() {
        let template = "{{#Extra}}<b>{{Extra}}</b>{{/Extra}}{{^Missing}}empty{{/Missing}} {{Front}}"
        XCTAssertEqual(TemplateRenderer.render(template, fields: ["Extra": "yes", "Front": "Q"], ordinal: 0, answer: false), "<b>yes</b>empty Q")
        XCTAssertTrue(TemplateRenderer.htmlWithAudio("[sound:a'b.wav]").contains("&#39;"))
        XCTAssertFalse(TemplateRenderer.htmlWithAudio("[sound:../secret.wav]").contains("audio"))
        XCTAssertEqual(TemplateRenderer.furigana("日本[にほん] 語[ご]"), "<ruby>日本<rt>にほん</rt></ruby> <ruby>語<rt>ご</rt></ruby>")
        XCTAssertTrue(TemplateRenderer.render("{{hint:同音}}", fields: ["同音": "例子"], ordinal: 0, answer: true).contains("<details>"))
    }

    func testUserProvidedAnkiDeck() throws {
        guard let path = ProcessInfo.processInfo.environment["OPENANKI_TEST_APKG"] else { throw XCTSkip("Set OPENANKI_TEST_APKG to test a local deck.") }
        let imported = try AnkiPackageImporter.load(url: URL(fileURLWithPath: path))
        defer { imported.cleanup() }
        XCTAssertGreaterThan(imported.snapshot.cards.count, 0)
        XCTAssertTrue(imported.snapshot.cards.allSatisfy { !$0.front.isEmpty && !$0.back.isEmpty })
        XCTAssertTrue(imported.warnings.isEmpty, imported.warnings.joined(separator: "\n"))
        print("Imported user deck: \(imported.snapshot.decks.map(\.name)), \(imported.snapshot.cards.count) cards")
        let repository = CollectionRepository(directory: try temporaryDirectory())
        try repository.commit(imported, snapshot: imported.snapshot)
        let loaded = try XCTUnwrap(repository.load())
        XCTAssertEqual(loaded.cards.count, imported.snapshot.cards.count)
        let mediaFolder = try XCTUnwrap(loaded.cards.first?.mediaFolder)
        let media = try FileManager.default.contentsOfDirectory(at: repository.mediaURL.appendingPathComponent(mediaFolder), includingPropertiesForKeys: nil)
        print("Extracted media files: \(media.count)")
        XCTAssertGreaterThan(media.count, 0)
        let file = try temporaryDirectory().appendingPathComponent("user-deck.openanki")
        try repository.backup(loaded).write(to: file)
        let restored = try DeckImporter.load(url: file)
        defer { restored.cleanup() }
        XCTAssertEqual(restored.snapshot.cards.count, loaded.cards.count)
        let restoredMedia = try FileManager.default.contentsOfDirectory(at: XCTUnwrap(restored.stagingDirectory).appendingPathComponent("Media/\(mediaFolder)"), includingPropertiesForKeys: nil)
        XCTAssertEqual(restoredMedia.count, media.count)
    }
}
