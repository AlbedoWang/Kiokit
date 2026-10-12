import XCTest
@testable import KiokitCore

final class BuiltInDecksTests: XCTestCase {
    func testOnlyGuideIsSeededAndBothLanguagesPreserveLearningProgress() throws {
        let english = InterfaceLanguage.english.locale()
        var snapshot = BuiltInDecks.initialCollection(locale: english)
        XCTAssertEqual(snapshot.decks.map(\.name), ["Getting started with Anki"])
        XCTAssertEqual(snapshot.cards.count, 4)
        XCTAssertTrue(snapshot.cards.allSatisfy { $0.builtInID != nil && $0.tags == ["Guide"] })
        let original = snapshot.cards[0]
        snapshot.cards[0] = reviewFixture(original, rating: .easy)
        snapshot.reviews = [ReviewRecord(card: original, rating: .easy, date: .now, duration: 5)]
        let chinese = BuiltInDecks.updating(snapshot, locale: InterfaceLanguage.simplifiedChinese.locale())
        XCTAssertTrue(chinese.changed)
        XCTAssertEqual(chinese.snapshot.decks[0].name, "开始使用 Anki")
        XCTAssertEqual(chinese.snapshot.cards[0].front, "怎样开始复习？")
        XCTAssertTrue(chinese.snapshot.cards[0].back.contains("显示答案"))
        XCTAssertTrue(chinese.snapshot.cards.allSatisfy { $0.tags == ["使用指南"] })
        XCTAssertEqual(chinese.snapshot.cards.map(\.id), snapshot.cards.map(\.id))
        XCTAssertEqual(chinese.snapshot.cards[0].interval, snapshot.cards[0].interval)
        XCTAssertEqual(chinese.snapshot.cards[0].due, snapshot.cards[0].due)
        XCTAssertEqual(chinese.snapshot.reviews[0].id, snapshot.reviews[0].id)
        let restored = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONEncoder().encode(chinese.snapshot))
        let switched = BuiltInDecks.updating(restored, locale: english).snapshot
        XCTAssertEqual(switched.decks[0].id, snapshot.decks[0].id)
        XCTAssertEqual(switched.cards, snapshot.cards)
        XCTAssertFalse(BuiltInDecks.updating(switched, locale: english).changed)
    }

    func testLegacyMigrationRemovesRetiredSamplesAndPreservesImportedAndCustomCards() throws {
        let english = Deck(name: "日常英语", symbol: "textformat.abc")
        let swift = Deck(name: "Swift 随手记", symbol: "swift")
        let guide = Deck(name: "开始使用 Anki", symbol: "sparkles")
        let importedEnglish = Deck(name: "日常英语", symbol: "textformat.abc")
        let importedDeck = Deck(name: "Imported Japanese vocabulary")
        let word = Flashcard(deckID: english.id, front: "serendipity", back: "意外发现美好事物的幸运。\n\nFinding this little bookshop was pure serendipity.", tags: ["词汇"])
        let programming = Flashcard(deckID: swift.id, front: "Optional 表示什么？", back: "一个值可能存在，也可能是 nil。\n用 if let 或 guard let 安全解包。", tags: ["基础"])
        let custom = Flashcard(deckID: swift.id, front: "My own question", back: "My own answer")
        let help = Flashcard(deckID: guide.id, front: "怎样开始复习？", back: "选择一个牌组，点击「开始学习」。先回想答案，再点击「显示答案」。", tags: ["使用指南"])
        var importedWord = word
        importedWord.id = UUID()
        importedWord.deckID = importedEnglish.id
        importedWord.sourceKey = "imported:0"
        let japanese = Flashcard(deckID: importedDeck.id, front: "挨拶 / あいさつ", back: "寒暄；打招呼。", sourceKey: "imported:1")
        let reviewed = reviewFixture(japanese, rating: .easy)
        let review = ReviewRecord(card: japanese, rating: .easy, date: .now, duration: 6)
        let snapshot = CollectionSnapshot(decks: [english, swift, guide, importedEnglish, importedDeck], cards: [word, programming, custom, help, importedWord, reviewed], reviews: [ReviewRecord(card: word, rating: .good, date: .now, duration: 2), review])
        // Encoding nil provenance reproduces the fields omitted by older builds.
        let legacy = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONEncoder().encode(snapshot))
        let migrated = BuiltInDecks.updating(legacy, locale: InterfaceLanguage.english.locale()).snapshot
        try migrated.validate()
        XCTAssertFalse(migrated.decks.contains { $0.id == english.id })
        XCTAssertFalse(migrated.cards.contains { $0.id == word.id || $0.id == programming.id })
        XCTAssertEqual(migrated.cards.first { $0.id == custom.id }, custom)
        XCTAssertTrue(migrated.decks.contains { $0.id == swift.id })
        XCTAssertEqual(migrated.cards.first { $0.id == importedWord.id }, importedWord)
        XCTAssertEqual(migrated.cards.first { $0.id == reviewed.id }, reviewed)
        XCTAssertEqual(migrated.reviews.map(\.id), [review.id])
        XCTAssertEqual(migrated.decks.first { $0.id == guide.id }?.name, "Getting started with Anki")
        XCTAssertEqual(migrated.cards.first { $0.id == help.id }?.builtInID, "guide.start")
        XCTAssertEqual(migrated.settings.builtInContentVersion, 1)
    }

    func testDeletedOrCustomizedGuideContentIsNeverRecreatedOrOverwritten() {
        var snapshot = BuiltInDecks.initialCollection(locale: InterfaceLanguage.english.locale())
        snapshot.decks[0].name = "My learning guide"
        snapshot.cards[0].front = "My question"
        snapshot.cards[0].back = "My explanation"
        snapshot.cards[0].tags = ["custom"]
        let customized = snapshot.cards[0]
        let switched = BuiltInDecks.updating(snapshot, locale: InterfaceLanguage.simplifiedChinese.locale()).snapshot
        XCTAssertEqual(switched.decks[0].name, "My learning guide")
        XCTAssertEqual(switched.cards[0], customized)
        snapshot.decks.removeAll()
        snapshot.cards.removeAll()
        XCTAssertTrue(BuiltInDecks.updating(snapshot, locale: InterfaceLanguage.simplifiedChinese.locale()).snapshot.decks.isEmpty)
        XCTAssertTrue(BuiltInDecks.updating(CollectionSnapshot(), locale: InterfaceLanguage.english.locale()).snapshot.decks.isEmpty)
    }
    /// Authored legacy progress used to verify localization does not mutate it.
    private func reviewFixture(_ original: Flashcard, rating: ReviewRating) -> Flashcard {
        var card = original
        card.stage = .review
        card.interval = 4
        card.repetitions = 1
        card.lastReviewedAt = .now
        card.due = Date.now.addingTimeInterval(4 * 86400)
        return card
    }

}
