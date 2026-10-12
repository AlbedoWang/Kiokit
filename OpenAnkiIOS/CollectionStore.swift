import Foundation
import Observation
import OpenAnkiCore

@MainActor @Observable
final class CollectionStore {
    private(set) var snapshot = CollectionSnapshot()
    private(set) var loadFailed = false
    private(set) var isImporting = false
    private(set) var pendingBackup: ImportedCollection?
    var errorMessage: String?
    var importMessage: String?
    private var undoRecordID: UUID?
    let repository: CollectionRepository

    init(directory: URL? = nil) {
        let root = directory ?? URL.applicationSupportDirectory.appendingPathComponent("OpenAnki", isDirectory: true)
        repository = CollectionRepository(directory: root)
        reload()
    }

    var decks: [Deck] { snapshot.decks.sorted { $0.createdAt < $1.createdAt } }
    var cards: [Flashcard] { snapshot.cards }
    var settings: StudySettings { snapshot.settings }
    var canUndo: Bool { undoRecordID != nil }

    func reload() {
        do {
            if let existing = try repository.load() { snapshot = existing }
            else {
                let sample = Self.sampleCollection()
                try repository.save(sample)
                snapshot = sample
            }
            loadFailed = false
            errorMessage = nil
        } catch {
            loadFailed = true
            errorMessage = "读取本地数据失败，原文件已保留。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func update(clearUndo: Bool = true, _ change: (inout CollectionSnapshot) -> Void) -> Bool {
        guard !loadFailed else { return false }
        var next = snapshot
        change(&next)
        do {
            try repository.save(next)
            snapshot = next
            if clearUndo { undoRecordID = nil }
            return true
        } catch {
            errorMessage = "保存失败，本次操作尚未生效。\n\(error.localizedDescription)"
            return false
        }
    }

    func deck(_ id: UUID) -> Deck? { snapshot.decks.first { $0.id == id } }
    func cards(in deckID: UUID) -> [Flashcard] { cards.filter { $0.deckID == deckID } }
    func queue(deckID: UUID? = nil, now: Date = .now) -> [Flashcard] { StudyQueue.cards(in: snapshot, deckID: deckID, now: now) }
    func todayReviews(now: Date = .now) -> [ReviewRecord] { snapshot.reviews.filter { Calendar.current.isDate($0.date, inSameDayAs: now) } }

    @discardableResult
    func saveDeck(_ deck: Deck) -> Bool {
        let name = deck.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard !decks.contains(where: { $0.id != deck.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "已经有同名牌组，请换一个名称。"
            return false
        }
        var trimmed = deck
        trimmed.name = name
        return update {
            if let index = $0.decks.firstIndex(where: { $0.id == deck.id }) { $0.decks[index] = trimmed }
            else { $0.decks.append(trimmed) }
        }
    }

    func deleteDeck(_ id: UUID) {
        update {
            $0.decks.removeAll { $0.id == id }
            $0.cards.removeAll { $0.deckID == id }
            $0.reviews.removeAll { $0.deckID == id }
        }
    }

    @discardableResult
    func saveCard(_ card: Flashcard, addReverse: Bool = false) -> Bool {
        guard !card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !card.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              deck(card.deckID) != nil else { return false }
        return update {
            if let index = $0.cards.firstIndex(where: { $0.id == card.id }) {
                $0.cards[index] = card
                for reviewIndex in $0.reviews.indices where $0.reviews[reviewIndex].cardID == card.id {
                    $0.reviews[reviewIndex].deckID = card.deckID
                }
            }
            else {
                $0.cards.append(card)
                if addReverse { $0.cards.append(Flashcard(deckID: card.deckID, front: card.back, back: card.front, tags: card.tags, isHTML: card.isHTML)) }
            }
        }
    }

    func deleteCard(_ id: UUID) {
        update {
            $0.cards.removeAll { $0.id == id }
            $0.reviews.removeAll { $0.cardID == id }
        }
    }

    func toggleSuspended(_ id: UUID) {
        update {
            guard let index = $0.cards.firstIndex(where: { $0.id == id }) else { return }
            $0.cards[index].isSuspended.toggle()
        }
    }

    func resetCard(_ id: UUID) {
        update {
            guard let index = $0.cards.firstIndex(where: { $0.id == id }) else { return }
            let original = $0.cards[index]
            var fresh = Flashcard(id: original.id, deckID: original.deckID, front: original.front, back: original.back, tags: original.tags, isHTML: original.isHTML, css: original.css, mediaFolder: original.mediaFolder, sourceKey: original.sourceKey, createdAt: original.createdAt)
            fresh.isSuspended = original.isSuspended
            $0.cards[index] = fresh
        }
    }

    @discardableResult
    func answer(_ card: Flashcard, rating: ReviewRating, duration: TimeInterval) -> Bool {
        guard let original = cards.first(where: { $0.id == card.id }), !original.isSuspended else { return false }
        let now = Date.now
        let record = ReviewRecord(card: original, rating: rating, date: now, duration: duration)
        let success = update(clearUndo: false) {
            guard let index = $0.cards.firstIndex(where: { $0.id == card.id }) else { return }
            $0.cards[index] = Scheduler.answer(original, rating: rating, now: now)
            $0.reviews.append(record)
        }
        if success { undoRecordID = record.id }
        return success
    }

    @discardableResult
    func undo() -> Bool {
        guard let id = undoRecordID, let record = snapshot.reviews.last, record.id == id else { return false }
        return update {
            guard let index = $0.cards.firstIndex(where: { $0.id == record.cardID }) else { return }
            $0.cards[index].restoreScheduling(record.previousState)
            $0.reviews.removeLast()
        }
    }

    func saveSettings(_ settings: StudySettings) { update { $0.settings = settings } }

    func importFile(_ url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try await Task.detached(priority: .userInitiated) { try DeckImporter.load(url: url) }.value
            if imported.isBackup {
                pendingBackup?.cleanup()
                pendingBackup = imported
            } else {
                defer { imported.cleanup() }
                let merged = CollectionRepository.merging(imported.snapshot, into: snapshot)
                try repository.commit(imported, snapshot: merged.snapshot)
                snapshot = merged.snapshot
                undoRecordID = nil
                let details = imported.warnings.joined(separator: "\n")
                importMessage = "已导入 \(merged.added) 张卡片" + (merged.skipped > 0 ? "，跳过 \(merged.skipped) 张重复卡片" : "") + "。\n新导入的 Anki 卡片从头开始学习。" + (details.isEmpty ? "" : "\n\n" + details)
            }
        } catch { errorMessage = "导入失败，原有牌组已保留。\n\(error.localizedDescription)" }
    }

    func restoreBackup() {
        guard let imported = pendingBackup else { return }
        defer { imported.cleanup(); pendingBackup = nil }
        do {
            try repository.commit(imported, snapshot: imported.snapshot)
            snapshot = imported.snapshot
            undoRecordID = nil
            importMessage = "已恢复 \(decks.count) 个牌组和 \(cards.count) 张卡片，包括学习进度。"
        } catch { errorMessage = "恢复失败，原有数据已保留。\n\(error.localizedDescription)" }
    }

    func cancelRestore() { pendingBackup?.cleanup(); pendingBackup = nil }

    func backupData() async throws -> Data {
        let snapshot = snapshot
        let repository = repository
        return try await Task.detached(priority: .userInitiated) { try repository.backup(snapshot) }.value
    }

    private static func sampleCollection() -> CollectionSnapshot {
        let english = Deck(name: "日常英语", symbol: "textformat.abc", colorIndex: 0)
        let swift = Deck(name: "Swift 随手记", symbol: "swift", colorIndex: 1)
        let guide = Deck(name: "开始使用 Anki", symbol: "sparkles", colorIndex: 2)
        let examples: [(Deck, [(String, String, [String])])] = [
            (english, [
                ("serendipity", "意外发现美好事物的幸运。\n\nFinding this little bookshop was pure serendipity.", ["词汇"]),
                ("Take your time.", "慢慢来，不着急。", ["表达"]),
                ("What does “a silver lining” mean?", "困境中的一线希望。\nEvery cloud has a silver lining.", ["表达"]),
                ("resilient", "有韧性的；能从困难中恢复的。", ["词汇"]),
                ("I’m looking forward to it.", "我很期待。", ["表达"]),
            ]),
            (swift, [
                ("Swift 的 let 和 var 有什么区别？", "let 声明常量，初始化后不能重新赋值；var 声明变量。", ["基础"]),
                ("Optional 表示什么？", "一个值可能存在，也可能是 nil。\n用 if let 或 guard let 安全解包。", ["基础"]),
                ("SwiftUI 中 @State 的作用？", "保存视图拥有的状态。状态变化时，SwiftUI 更新依赖它的视图。", ["SwiftUI"]),
                ("struct 和 class 的主要区别？", "struct 是值类型，赋值时具有独立的值语义。class 是引用类型，可以共享同一个实例。", ["基础"]),
            ]),
            (guide, [
                ("怎样开始复习？", "选择一个牌组，点击「开始学习」。先回想答案，再点击「显示答案」。", ["使用指南"]),
                ("四个评分按钮怎么选？", "重来：没有想起来。\n困难：想起来了，但很费力。\n良好：正常回忆出来。\n简单：立刻就想起来。", ["使用指南"]),
                ("怎样导入桌面 Anki 牌组？", "在 Anki 桌面版导出 .apkg 文件，存到 iPhone 的「文件」中，再点击本应用的导入按钮。支持常见正反面、反向和填空卡片。", ["使用指南"]),
                ("怎样备份学习进度？", "打开「设置」→「导出完整备份」。.openanki 文件包含牌组、进度和导入的媒体，保存后可以离线恢复。", ["使用指南"]),
            ]),
        ]
        let cards = examples.flatMap { deck, entries in entries.map { Flashcard(deckID: deck.id, front: $0.0, back: $0.1, tags: $0.2) } }
        return CollectionSnapshot(decks: [english, swift, guide], cards: cards)
    }
}
