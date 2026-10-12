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
    var interfaceLanguage: InterfaceLanguage { InterfaceLanguage(rawValue: settings.interfaceLanguage ?? "system") ?? .system }
    var uiLocale: Locale { interfaceLanguage.locale() }

    func text(_ message: LocalizedMessage) -> String { message.localized(locale: uiLocale) }
    func text(key: String) -> String { LocalizedMessage(key: key).localized(locale: uiLocale) }
    func errorText(_ error: Error) -> String {
        (error as? CollectionError)?.localizedDescription(locale: uiLocale) ?? error.localizedDescription
    }

    func reload() {
        do {
            if let existing = try repository.load() {
                let updated = Self.localizedBuiltInContent(existing)
                if updated.changed { try repository.save(updated.snapshot) }
                snapshot = updated.snapshot
            }
            else {
                let sample = BuiltInDecks.initialCollection(locale: InterfaceLanguage.system.locale())
                try repository.save(sample)
                snapshot = sample
            }
            loadFailed = false
            errorMessage = nil
        } catch {
            loadFailed = true
            errorMessage = text("读取本地数据失败，原文件已保留。\n\(errorText(error))")
        }
    }

    @discardableResult
    private func update(clearUndo: Bool = true, _ change: (inout CollectionSnapshot) -> Void) -> Bool {
        guard !loadFailed else { return false }
        var next = snapshot
        change(&next)
        do {
            let localized = Self.localizedBuiltInContent(next).snapshot
            try repository.save(localized)
            snapshot = localized
            if clearUndo { undoRecordID = nil }
            return true
        } catch {
            errorMessage = text("保存失败，本次操作尚未生效。\n\(errorText(error))")
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
            errorMessage = text("已经有同名牌组，请换一个名称。")
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
                let original = $0.cards[index]
                let contentChanged = original.front != card.front || original.back != card.back
                $0.cards[index] = card
                if contentChanged { $0.cards[index].pronunciation = nil }
                if contentChanged || card.deckID != original.deckID || card.tags != original.tags || card.isHTML != original.isHTML {
                    $0.cards[index].builtInID = nil
                }
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
            fresh.pronunciation = original.pronunciation
            fresh.builtInID = original.builtInID
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
                let localized = Self.localizedBuiltInContent(merged.snapshot).snapshot
                try repository.commit(imported, snapshot: localized)
                snapshot = localized
                undoRecordID = nil
                let details = imported.warnings.map { text($0) }.joined(separator: "\n")
                importMessage = text("已导入 \(merged.added) 张卡片") + (merged.skipped > 0 ? text("，跳过 \(merged.skipped) 张重复卡片") : "") + text("。\n新导入的 Anki 卡片从头开始学习。") + (details.isEmpty ? "" : "\n\n" + details)
            }
        } catch { errorMessage = text("导入失败，原有牌组已保留。\n\(errorText(error))") }
    }

    func restoreBackup() {
        guard let imported = pendingBackup else { return }
        defer { imported.cleanup(); pendingBackup = nil }
        do {
            let localized = Self.localizedBuiltInContent(imported.snapshot).snapshot
            try repository.commit(imported, snapshot: localized)
            snapshot = localized
            undoRecordID = nil
            importMessage = text("已恢复 \(decks.count) 个牌组和 \(cards.count) 张卡片，包括学习进度。")
        } catch { errorMessage = text("恢复失败，原有数据已保留。\n\(errorText(error))") }
    }

    func cancelRestore() { pendingBackup?.cleanup(); pendingBackup = nil }

    func backupData() async throws -> Data {
        let snapshot = snapshot
        let repository = repository
        return try await Task.detached(priority: .userInitiated) { try repository.backup(snapshot) }.value
    }

    private static func localizedBuiltInContent(_ snapshot: CollectionSnapshot) -> (snapshot: CollectionSnapshot, changed: Bool) {
        let language = InterfaceLanguage(rawValue: snapshot.settings.interfaceLanguage ?? "system") ?? .system
        return BuiltInDecks.updating(snapshot, locale: language.locale())
    }
}
