import Foundation
import Observation
import OpenAnkiCore

/// Observable presentation state. Collection operations execute Anki's backend.
@MainActor @Observable
final class CollectionStore {
    private(set) var snapshot = CollectionSnapshot()
    private(set) var statistics: AnkiJSON = [:]
    private(set) var loadFailed = false
    private(set) var isImporting = false
    private(set) var pendingBackup: URL?
    private(set) var canUndo = false
    private(set) var undoTitle = ""
    private(set) var selectedDeckID: UUID?
    private(set) var studyDayStart = Date.now
    private(set) var studiedTodayMessage = ""
    private(set) var statesMutated = true
    private(set) var reviewGeneration = 0
    private(set) var reviewTextGeneration = 0
    private(set) var backendIdentity = ""
    private(set) var presentationRevision = 0
    private(set) var isAnswering = false
    private(set) var isReviewing = false
    var errorMessage: String?
    var importMessage: String?
    var requestedBrowserSearch: String?
    private var session: AnkiApplicationSession?
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("OpenAnki", isDirectory: true)
        reload()
    }

    var decks: [Deck] { snapshot.decks }
    var cards: [Flashcard] { snapshot.cards }
    var settings: StudySettings { snapshot.settings }
    var noteTypes: [AnkiJSON] { session?.noteTypes ?? [] }
    var currentCard: Flashcard? {
        let cards = snapshot.cards
        guard let id = session?.queuedCard?["card"]["id"].int else { return nil }
        return cards.first { $0.ankiID == id }
    }
    var intervalLabels: [String] { session?.intervalLabels ?? [] }
    var congratulations: AnkiJSON { session?.congratulations ?? [:] }
    var nextLearningDate: Date? { session?.nextLearningDate }
    var mediaURL: URL { directory.appendingPathComponent("collection.media", isDirectory: true) }
    var interfaceLanguage: InterfaceLanguage { InterfaceLanguage(rawValue: settings.interfaceLanguage ?? "system") ?? .system }
    var uiLocale: Locale { interfaceLanguage.locale() }

    func text(_ message: LocalizedMessage) -> String { message.localized(locale: uiLocale) }
    func text(key: String) -> String { LocalizedMessage(key: key).localized(locale: uiLocale) }
    func errorText(_ error: Error) -> String {
        (error as? CollectionError)?.localizedDescription(locale: uiLocale) ?? error.localizedDescription
    }

    func reload() {
        do {
            if session == nil { session = try AnkiApplicationSession(directory: directory) }
            else { try session?.refresh() }
            display()
            loadFailed = false
            errorMessage = nil
        } catch {
            loadFailed = true
            errorMessage = text("读取本地数据失败，原文件已保留。\n\(errorText(error))")
        }
    }

    private func display() {
        guard let session else { return }
        if snapshot.cards != session.snapshot.cards || snapshot.decks != session.snapshot.decks || snapshot.settings != session.snapshot.settings {
            snapshot = session.snapshot
            presentationRevision += 1
        }
        statistics = session.statistics
        canUndo = session.canUndo
        undoTitle = session.undoTitle
        selectedDeckID = session.selectedDeckID
        studyDayStart = session.studyDayStart
        studiedTodayMessage = session.studiedTodayMessage
        statesMutated = session.statesMutated
        reviewGeneration = session.reviewGeneration
        reviewTextGeneration = session.reviewTextGeneration
        backendIdentity = session.stateMutationKey
        isReviewing = session.isReviewing
    }

    @discardableResult private func perform(_ operation: (AnkiApplicationSession) throws -> Void) -> Bool {
        guard let session, !loadFailed, !isAnswering else { return false }
        do { try operation(session); display(); return true }
        catch { errorMessage = errorText(error); return false }
    }

    func deck(_ id: UUID) -> Deck? { decks.first { $0.id == id } }
    func cards(in deckID: UUID) -> [Flashcard] { cards.filter { $0.deckID == deckID } }
    func counts(deckID: UUID? = nil) -> AnkiStudyCounts { session?.counts(for: deckID) ?? AnkiStudyCounts() }
    func cardCount(deckID: UUID) -> Int { session?.cardCount(for: deckID) ?? 0 }
    func selectDeck(_ id: UUID) { perform { try $0.selectDeck(id) } }
    func beginReview(deckID: UUID?) { perform { try $0.beginReview(deckID: deckID) } }
    func endReview() { guard !isAnswering else { return }; session?.endReview(); display() }
    func nextCard() { perform { try $0.nextCard() } }
    func refreshStudyDay() { if !isImporting { perform { try $0.refreshStudyDay() } } }
    var stateMutationJavaScript: String? { session?.stateMutationJavaScript }
    #if DEBUG
    var reviewerDiagnostics: AnkiJSON { session?.queuedCard ?? [:] }
    var statisticsDiagnostics: AnkiJSON { session?.statisticsTransportDiagnostics ?? [:] }
    #endif
    func reviewerRequest(path: String, data: Data) throws -> Data {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        let response = try session.reviewerRequest(path: path, data: data)
        display()
        return response
    }
    func reviewerStatesMutated() { session?.reviewerStatesMutated(); display() }
    func statisticsRequest(path: String, data: Data) throws -> Data {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        return try session.statisticsRequest(path: path, data: data)
    }
    func statisticsChartTitles() throws -> [String: String] {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        return try session.statisticsChartTitles()
    }
    func detailsAnswerCard(_ card: Flashcard) throws -> Flashcard {
        guard let session, let id = card.ankiID else { return card }
        let rendered = try session.collection.renderedCard(id, includeFrontSide: false)
        var display = card
        display.back = rendered["answer"]["text"].string
        display.css += "\n#qa hr#answer { display: none; }"
        return display
    }
    func reviewerWillRedrawQuestion() { session?.reviewerWillRedrawQuestion(); display() }
    func typedAnswer(for card: Flashcard) throws -> AnkiTypedAnswer {
        guard let session, let id = card.ankiID else { throw CollectionError.invalid("无法读取牌组。") }
        return try session.typedAnswer(for: id, question: session.prepareCardTextForDisplay(card.front))
    }
    func prepareCardTextForDisplay(_ html: String) throws -> String {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        return try session.prepareCardTextForDisplay(html)
    }
    func escapeMediaFilenames(_ html: String) throws -> String {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        return try session.escapeMediaFilenames(html)
    }

    @discardableResult func answer(_ card: Flashcard, rating: ReviewRating) async -> Bool {
        guard let session, !loadFailed, !isAnswering, statesMutated, currentCard?.id == card.id else { return false }
        isAnswering = true
        defer { isAnswering = false }
        do { try await session.answerInBackground(rating: rating); display(); return true }
        catch { errorMessage = errorText(error); return false }
    }
    @discardableResult func undo() -> Bool { perform { try $0.undo() } }
    @discardableResult func saveDeck(_ deck: Deck) -> Bool { perform { try $0.saveDeck(deck) } }
    func deleteDeck(_ id: UUID) { if let deck = deck(id) { perform { try $0.deleteDeck(deck) } } }
    func deleteNote(of id: UUID) { if let card = cards.first(where: { $0.id == id }) { perform { try $0.deleteNote(of: card) } } }
    func toggleSuspended(_ id: UUID) { if let card = cards.first(where: { $0.id == id }) { perform { try $0.toggleSuspended(card) } } }
    func resetCard(_ id: UUID) { if let card = cards.first(where: { $0.id == id }) { perform { try $0.resetCard(card) } } }
    func saveSettings(_ settings: StudySettings) { perform { try $0.saveSettings(settings) } }

    func defaultNoteTypeID() -> Int64? {
        var result: Int64?
        perform { result = try $0.defaultNoteTypeID() }
        return result
    }
    func newNoteFields(_ type: Int64) -> [AnkiNoteField] {
        var fields: [AnkiNoteField] = []
        perform { fields = try $0.newNoteFields(noteTypeID: type) }
        return fields
    }
    @discardableResult func saveNote(card: Flashcard?, deckID: UUID, noteTypeID: Int64, fields: [AnkiNoteField], tags: String) -> Bool {
        guard let nativeDeck = deck(deckID)?.ankiID else { return false }
        return perform { try $0.saveNote(card: card, deckID: nativeDeck, noteTypeID: noteTypeID, fields: fields, tags: tags) }
    }

    func newCardLimit(for id: UUID) -> Int {
        guard let options = deck(id)?.ankiOptions else { return 0 }
        let override = options["currentDeck"]["limits"]["new"]
        return Int(override.isNull ? preset(for: id)["config"]["newPerDay"].int : override.int)
    }
    func saveNewCardLimit(_ limit: Int?, for id: UUID) {
        if let deck = deck(id) { perform { try $0.saveDeckLimit(limit, key: "new", deck: deck) } }
    }
    func saveReviewLimit(_ limit: Int?, for id: UUID) {
        if let deck = deck(id) { perform { try $0.saveDeckLimit(limit, key: "review", deck: deck) } }
    }
    func preset(for id: UUID) -> AnkiJSON {
        guard let options = deck(id)?.ankiOptions else { return [:] }
        let configID = options["currentDeck"]["configId"].int
        return options["allConfig"].array.first { $0["config"]["id"].int == configID }?["config"] ?? [:]
    }
    func savePresetValue(_ value: AnkiJSON, key: String, for id: UUID) {
        if let deck = deck(id) { perform { try $0.savePresetValue(value, key: key, deck: deck) } }
    }
    func clonePreset(for id: UUID) {
        if let deck = deck(id) { perform { try $0.clonePreset(for: deck) } }
    }
    func saveCollectionOption(_ value: AnkiJSON, key: String, for id: UUID) {
        if let deck = deck(id) { perform { try $0.saveCollectionOption(value, key: key, deck: deck) } }
    }
    func filteredDeckOptions(for id: UUID) -> AnkiJSON? {
        guard let nativeID = deck(id)?.ankiID else { return nil }
        var result: AnkiJSON?
        perform { result = try $0.filteredDeckOptions(nativeID) }
        return result
    }
    func filteredOrderLabels() -> [(value: Int, title: String)] {
        var result: [(value: Int, title: String)] = []
        perform { result = try $0.filteredOrderLabels() }
        return result
    }
    @discardableResult func saveFilteredDeck(_ options: AnkiJSON) -> Bool { perform { try $0.saveFilteredDeck(options) } }
    @discardableResult func emptyFilteredDeck(_ id: UUID) -> Bool {
        guard let nativeID = deck(id)?.ankiID else { return false }
        return perform { try $0.emptyFilteredDeck(nativeID) }
    }

    func searchCards(_ text: String, deckID: UUID?, stage: String) throws -> [Flashcard] {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        let ids = try session.search(text, deckID: deckID, stage: stage)
        let display = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return ids.compactMap { display[$0] }
    }

    func importFile(_ url: URL) async {
        guard !isImporting, !isAnswering, let session else { return }
        isImporting = true
        defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            if ["colpkg", "openanki"].contains(url.pathExtension.lowercased()) {
                let copy = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                try FileManager.default.copyItem(at: url, to: copy)
                cancelRestore()
                pendingBackup = copy
                return
            }
            let collection = session.collection
            let result = try await Task.detached(priority: .userInitiated) {
                if url.pathExtension.lowercased() == "apkg" { return try collection.importPackage(url) }
                return try collection.importText(url)
            }.value
            try session.refreshAfterOperation(result)
            display()
            let log = result["log"]
            importMessage = text("新增 \(log["new"].array.count) 条笔记，更新 \(log["updated"].array.count) 条，重复 \(log["duplicate"].array.count) 条。")
        } catch { errorMessage = text("导入失败，原有牌组已保留。\n\(errorText(error))") }
    }

    func restoreBackup() {
        guard let file = pendingBackup else { return }
        defer { cancelRestore() }
        perform { session in
            if file.pathExtension.lowercased() == "openanki" {
                let converted = try LegacyBackupReader.convertedPackage(from: file)
                defer { try? FileManager.default.removeItem(at: converted.deletingLastPathComponent()) }
                try session.restoreCollection(from: converted)
            } else { try session.restoreCollection(from: file) }
            importMessage = text("已恢复 \(session.snapshot.decks.count) 个牌组和 \(session.snapshot.cards.count) 张卡片，包括学习进度。")
        }
    }

    func cancelRestore() {
        if let pendingBackup { try? FileManager.default.removeItem(at: pendingBackup) }
        pendingBackup = nil
    }

    func backupData() async throws -> Data {
        guard let session else { throw CollectionError.invalid("无法读取牌组。") }
        isImporting = true
        defer { isImporting = false }
        let collection = session.collection
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".colpkg")
        defer { try? FileManager.default.removeItem(at: file) }
        return try await Task.detached(priority: .userInitiated) {
            try collection.exportCollection(to: file)
            return try Data(contentsOf: file)
        }.value
    }
}
