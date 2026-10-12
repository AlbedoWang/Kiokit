import Foundation

/// Only app-owned guide text follows the interface language. All other deck
/// content stays as authored, including cards sharing a guide's deck name.
public enum BuiltInDecks {
    private struct GuideEntry {
        let id: String
        let front: String
        let back: String
    }

    private static let guideName = "开始使用 Anki"
    private static let guideTag = "使用指南"
    private static let guide: [GuideEntry] = [
        GuideEntry(id: "guide.start", front: "怎样开始复习？", back: "选择一个牌组，点击「开始学习」。先回想答案，再点击「显示答案」。"),
        GuideEntry(id: "guide.ratings", front: "四个评分按钮怎么选？", back: "重来：没有想起来。\n困难：想起来了，但很费力。\n良好：正常回忆出来。\n简单：立刻就想起来。"),
        GuideEntry(id: "guide.import", front: "怎样导入桌面 Anki 牌组？", back: "在 Anki 桌面版导出 .apkg 文件，存到 iPhone 的「文件」中，再点击本应用的导入按钮。支持常见正反面、反向和填空卡片。"),
        GuideEntry(id: "guide.backup", front: "怎样备份学习进度？", back: "打开「设置」→「导出完整备份」。.openanki 文件包含牌组、进度和导入的媒体，保存后可以离线恢复。"),
    ]

    public static func initialCollection(locale: Locale) -> CollectionSnapshot {
        var deck = Deck(name: guideName, symbol: "sparkles", colorIndex: 2)
        deck.builtInID = "guide"
        let cards = guide.map { entry in
            var card = Flashcard(deckID: deck.id, front: entry.front, back: entry.back, tags: [guideTag])
            card.builtInID = entry.id
            return card
        }
        var snapshot = CollectionSnapshot(decks: [deck], cards: cards)
        snapshot.settings.builtInContentVersion = 1
        return updating(snapshot, locale: locale).snapshot
    }

    public static func updating(_ snapshot: CollectionSnapshot, locale: Locale) -> (snapshot: CollectionSnapshot, changed: Bool) {
        var result = snapshot
        var changed = false
        if (result.settings.builtInContentVersion ?? 0) < 1 {
            migrateLegacyContent(&result)
            result.settings.builtInContentVersion = 1
            changed = true
        }
        for index in result.decks.indices where result.decks[index].builtInID == "guide" {
            let old = result.decks[index].name
            let new = localized(guideName, locale: locale)
            if isShippedText(old, key: guideName), old != new {
                result.decks[index].name = new
                changed = true
            }
        }
        for index in result.cards.indices {
            guard let entry = guide.first(where: { $0.id == result.cards[index].builtInID }) else { continue }
            let front = localized(entry.front, locale: locale)
            let back = localized(entry.back, locale: locale)
            let tag = localized(guideTag, locale: locale)
            if isShippedText(result.cards[index].front, key: entry.front), result.cards[index].front != front {
                result.cards[index].front = front
                changed = true
            }
            if isShippedText(result.cards[index].back, key: entry.back), result.cards[index].back != back {
                result.cards[index].back = back
                changed = true
            }
            if result.cards[index].tags.count == 1, isShippedText(result.cards[index].tags[0], key: guideTag), result.cards[index].tags != [tag] {
                result.cards[index].tags = [tag]
                changed = true
            }
        }
        return (result, changed)
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        LocalizedMessage(key: key).localized(locale: locale)
    }

    private static func isShippedText(_ value: String, key: String) -> Bool {
        value == key || value == localized(key, locale: InterfaceLanguage.english.locale())
    }

    private static func isLegacyAppCard(_ card: Flashcard) -> Bool {
        card.sourceKey == nil && card.mediaFolder == nil && !card.isHTML && card.css.isEmpty
    }

    private static func migrateLegacyContent(_ snapshot: inout CollectionSnapshot) {
        // Fingerprints of the retired starter cards, never seeded into new data.
        // Checking their content and origin protects same-named imported decks
        // and keeps cards a user added, moved, or edited in those old decks.
        let retired: [(name: String, symbol: String, cards: [(front: String, back: String, tags: [String])])] = [
            ("日常英语", "textformat.abc", [
                ("serendipity", "意外发现美好事物的幸运。\n\nFinding this little bookshop was pure serendipity.", ["词汇"]),
                ("Take your time.", "慢慢来，不着急。", ["表达"]),
                ("What does “a silver lining” mean?", "困境中的一线希望。\nEvery cloud has a silver lining.", ["表达"]),
                ("resilient", "有韧性的；能从困难中恢复的。", ["词汇"]),
                ("I’m looking forward to it.", "我很期待。", ["表达"]),
            ]),
            ("Swift 随手记", "swift", [
                ("Swift 的 let 和 var 有什么区别？", "let 声明常量，初始化后不能重新赋值；var 声明变量。", ["基础"]),
                ("Optional 表示什么？", "一个值可能存在，也可能是 nil。\n用 if let 或 guard let 安全解包。", ["基础"]),
                ("SwiftUI 中 @State 的作用？", "保存视图拥有的状态。状态变化时，SwiftUI 更新依赖它的视图。", ["SwiftUI"]),
                ("struct 和 class 的主要区别？", "struct 是值类型，赋值时具有独立的值语义。class 是引用类型，可以共享同一个实例。", ["基础"]),
            ]),
        ]
        for sample in retired {
            for deck in snapshot.decks where deck.name == sample.name && deck.symbol == sample.symbol {
                let removed = Set(snapshot.cards.filter { card in
                    card.deckID == deck.id && isLegacyAppCard(card) && sample.cards.contains {
                        $0.front == card.front && $0.back == card.back && $0.tags == card.tags
                    }
                }.map(\.id))
                guard !removed.isEmpty else { continue }
                snapshot.cards.removeAll { removed.contains($0.id) }
                snapshot.reviews.removeAll { removed.contains($0.cardID) }
                if !snapshot.cards.contains(where: { $0.deckID == deck.id }) {
                    snapshot.decks.removeAll { $0.id == deck.id }
                }
            }
        }
        for index in snapshot.decks.indices {
            let deck = snapshot.decks[index]
            guard deck.builtInID == nil, isShippedText(deck.name, key: guideName), deck.symbol == "sparkles" else { continue }
            var identified = false
            for cardIndex in snapshot.cards.indices where snapshot.cards[cardIndex].deckID == deck.id {
                let card = snapshot.cards[cardIndex]
                if isLegacyAppCard(card), let entry = guide.first(where: {
                    isShippedText(card.front, key: $0.front) && isShippedText(card.back, key: $0.back)
                }) {
                    snapshot.cards[cardIndex].builtInID = entry.id
                    identified = true
                }
            }
            if identified { snapshot.decks[index].builtInID = "guide" }
        }
    }
}
