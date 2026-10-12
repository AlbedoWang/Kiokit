import XCTest
@testable import OpenAnkiCore

final class LocalizationTests: XCTestCase {
    func testSystemMatchingUsesOnlySupportedFirstLanguage() {
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh_CN"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hans-TW"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hans-HK"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-HK"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["en-GB"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["ja-JP", "zh-Hans"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW"]), .english)
        XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(InterfaceLanguage.english.resolved(preferredLanguages: ["zh-Hans"]), .english)
        XCTAssertEqual(InterfaceLanguage.simplifiedChinese.resolved(preferredLanguages: ["en"]), .simplifiedChinese)
    }

    func testUIAndInterpolatedErrorMessagesInBothLanguages() {
        let message: LocalizedMessage = "已恢复 \(2) 个牌组和 \(3) 张卡片，包括学习进度。"
        XCTAssertEqual(message.localized(locale: InterfaceLanguage.english.locale()), "Restored 2 decks and 3 cards, including study progress.")
        XCTAssertEqual(message.localized(locale: InterfaceLanguage.simplifiedChinese.locale()), "已恢复 2 个牌组和 3 张卡片，包括学习进度。")
        let error = CollectionError.invalid("媒体文件夹缺失，无法生成完整备份：\("日本語%")")
        XCTAssertEqual(error.localizedDescription(locale: InterfaceLanguage.english.locale()), "A media folder is missing, so a complete backup cannot be created: 日本語%")
        XCTAssertEqual(LocalizedMessage(key: "跟随系统").localized(locale: InterfaceLanguage.english.locale()), "Match system")
    }

    func testOldSettingsRemainCompatibleAndLanguagePersistsWithoutChangingDeckText() throws {
        let old = Data(#"{"dailyGoal":30,"newCardsPerDay":20,"appearance":"system"}"#.utf8)
        let settings = try JSONDecoder().decode(StudySettings.self, from: old)
        XCTAssertNil(settings.interfaceLanguage)
        XCTAssertNil(settings.autoPlayAudio)
        let deck = Deck(name: "日本语红宝书::N4")
        let card = Flashcard(deckID: deck.id, front: "挨拶 / あいさつ", back: "寒暄；打招呼。\n例：おはようございます。")
        var snapshot = CollectionSnapshot(decks: [deck], cards: [card])
        snapshot.settings.interfaceLanguage = InterfaceLanguage.english.rawValue
        let restored = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.settings.interfaceLanguage, "en")
        XCTAssertEqual(restored.decks[0].name, deck.name)
        XCTAssertEqual(restored.cards[0].front, card.front)
        XCTAssertEqual(restored.cards[0].back, card.back)
    }

    func testSchedulerIntervalsRespectSelectedLanguage() {
        let card = Flashcard(deckID: UUID(), front: "Q", back: "A")
        XCTAssertEqual(Scheduler.intervalLabel(for: card, rating: .again, locale: InterfaceLanguage.english.locale()), "1 min")
        XCTAssertEqual(Scheduler.intervalLabel(for: card, rating: .again, locale: InterfaceLanguage.simplifiedChinese.locale()), "1 分钟")
    }
}
