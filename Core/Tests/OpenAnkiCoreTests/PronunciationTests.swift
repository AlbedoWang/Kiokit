import XCTest
@testable import OpenAnkiCore

final class PronunciationTests: XCTestCase {
    func testJapaneseSpeechKeepsOriginalMeaningAndReadsOnlyJapaneseExamples() throws {
        let fields = ["假名": "<div>ああ</div>", "中文释义": "[副]那样，那么",
                      "例句": "△ああすると、こちらは困る。/你那么做的话，我们会为难的。<br><div>△ああ言えばこう言う。/强词夺理。</div>"]
        let pronunciation = try XCTUnwrap(Pronunciation.japanese(fields: fields))
        XCTAssertEqual(pronunciation.language, "ja-JP")
        XCTAssertEqual(pronunciation.word, "ああ")
        XCTAssertEqual(pronunciation.examples, ["ああすると、こちらは困る。", "ああ言えばこう言う。"])
        XCTAssertEqual(fields["中文释义"], "[副]那样，那么")
        XCTAssertNil(Pronunciation.japanese(fields: ["Front": "English", "Back": "中文"]))
    }

    func testAudioNamesAreSafeAndOrderedWithoutChangingStoredHTML() {
        let html = "<b>日本語</b>[sound:ああ.mp3][sound:../secret.mp3][sound:ああ.mp3][sound:second.wav]"
        XCTAssertEqual(CardAudio.filenames(in: html), ["ああ.mp3", "second.wav"])
        XCTAssertEqual(CardAudio.removingSoundMarkers(from: html), "<b>日本語</b>")
        XCTAssertTrue(html.contains("[sound:ああ.mp3]"))
    }

    func testOldCardsDecodeAndReimportAddsSpeechWithoutResettingProgress() throws {
        let deck = Deck(name: "日本语红宝书::N4")
        let old = Flashcard(deckID: deck.id, front: "ああ", back: "那样，那么", sourceKey: "note:0")
        let restored = try JSONDecoder().decode(Flashcard.self, from: JSONEncoder().encode(old))
        XCTAssertNil(restored.pronunciation)
        var current = CollectionSnapshot(decks: [deck], cards: [Scheduler.answer(restored, rating: .easy)])
        var incoming = old
        incoming.pronunciation = Pronunciation(language: "ja-JP", word: "ああ", examples: ["ああ言えばこう言う。"])
        let imported = CollectionSnapshot(decks: [deck], cards: [incoming])
        let merged = CollectionRepository.merging(imported, into: current)
        XCTAssertEqual(merged.added, 0)
        XCTAssertEqual(merged.snapshot.cards[0].stage, .review)
        XCTAssertEqual(merged.snapshot.cards[0].pronunciation, incoming.pronunciation)
        current.cards[0].front = "Edited card"
        XCTAssertNil(CollectionRepository.merging(imported, into: current).snapshot.cards[0].pronunciation)
    }
}
