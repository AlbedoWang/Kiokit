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
        let deck = Deck(name: "Imported Japanese vocabulary")
        let card = Flashcard(deckID: deck.id, front: "挨拶 / あいさつ", back: "寒暄；打招呼。\n例：おはようございます。")
        var snapshot = CollectionSnapshot(decks: [deck], cards: [card])
        snapshot.settings.interfaceLanguage = InterfaceLanguage.english.rawValue
        let restored = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.settings.interfaceLanguage, "en")
        XCTAssertEqual(restored.decks[0].name, deck.name)
        XCTAssertEqual(restored.cards[0].front, card.front)
        XCTAssertEqual(restored.cards[0].back, card.back)
    }

    func testUpstreamIntervalDescriptionsRespectBackendLanguage() throws {
        let states: AnkiJSON = ["current": ["normal": ["new": ["position": 1]]],
            "again": ["normal": ["learning": ["scheduledSecs": 60, "remainingSteps": 2]]],
            "hard": ["normal": ["learning": ["scheduledSecs": 330, "remainingSteps": 2]]],
            "good": ["normal": ["learning": ["scheduledSecs": 600, "remainingSteps": 1]]],
            "easy": ["normal": ["review": ["scheduledDays": 4, "easeFactor": .number(2.5)]]]]
        func labels(_ language: String) throws -> [String] {
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let collection = try AnkiCollection(directory: root, preferredLanguages: [language])
            defer { try? collection.close(); try? FileManager.default.removeItem(at: root) }
            return try collection.describeIntervals(states)
        }
        let english = try labels("en")
        let chinese = try labels("zh-CN")
        XCTAssertEqual(english.count, 4)
        XCTAssertEqual(chinese.count, 4)
        XCTAssertNotEqual(english, chinese)
        XCTAssertTrue(english[0].contains("1"))
        XCTAssertTrue(chinese[0].contains("1"))
    }
}
