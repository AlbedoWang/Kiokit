// Portions adapted from ankitects/anki 26.09.3, qt/aqt/reviewer.py and undo.py.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

public struct AnkiStudyCounts: Sendable {
    public var new: Int = 0
    public var learning: Int = 0
    public var review: Int = 0
    public var total: Int { new + learning + review }
    public var isEmpty: Bool { total == 0 }
    public init(new: Int = 0, learning: Int = 0, review: Int = 0) { self.new = new; self.learning = learning; self.review = review }
}

/// Binds application screens to upstream operations. Snapshots and metadata are
/// display state; collection data, queues, answers, limits, and undo belong to Anki.
@MainActor
public final class AnkiApplicationSession {
    public private(set) var collection: AnkiCollection
    public private(set) var snapshot = CollectionSnapshot()
    public private(set) var statistics: AnkiJSON = [:]
    public private(set) var queuedCard: AnkiJSON?
    public private(set) var intervalLabels: [String] = []
    public private(set) var congratulations: AnkiJSON = [:]
    public private(set) var canUndo = false
    public private(set) var undoTitle = ""
    public private(set) var noteTypes: [AnkiJSON] = []
    public private(set) var selectedDeckID: UUID?
    public private(set) var studyDayStart = Date.now
    public private(set) var studiedTodayMessage = ""
    public private(set) var nextLearningDate: Date?
    public private(set) var statesMutated = true
    public private(set) var stateMutationJavaScript: String?
    public private(set) var reviewGeneration = 0
    public private(set) var reviewTextGeneration = 0
    public private(set) var isReviewing = false
    public private(set) var stateMutationKey = String(UInt64.random(in: .min ... .max))
    public private(set) var reviewTimer: AnkiReviewTimer?
    #if DEBUG
    public private(set) var statisticsTransportDiagnostics: AnkiJSON = [:]
    #endif
    private var metadata: AnkiJSON
    private var countsByDeck: [UUID: AnkiStudyCounts] = [:]
    private var cardsByDeck: [UUID: Int] = [:]
    private var studyDay: Int64?
    private let directory: URL
    private let preferredSystemLanguages: [String]
    private let reviewClock: () -> TimeInterval

    public init(directory: URL, preferredSystemLanguages: [String] = Locale.preferredLanguages, reviewClock: @escaping () -> TimeInterval = { Date.now.timeIntervalSince1970 }) throws {
        self.directory = directory
        self.preferredSystemLanguages = preferredSystemLanguages
        self.reviewClock = reviewClock
        let existed = FileManager.default.fileExists(atPath: directory.appendingPathComponent("collection.anki2").path)
        if !existed && FileManager.default.fileExists(atPath: directory.appendingPathComponent("collection.json").path) {
            try LegacyCollectionMigration.migrate(directory: directory)
        }
        let initialLanguage = InterfaceLanguage.system.resolved(preferredLanguages: preferredSystemLanguages)
        collection = try AnkiCollection(directory: directory, preferredLanguages: [initialLanguage == .simplifiedChinese ? "zh-CN" : "en"])
        metadata = try collection.applicationMetadata()
        if !existed && metadata["initialized"].isNull {
            try seedGuide()
        }
        try reopenForInterfaceLanguage()
        try refresh()
    }

    public var currentCard: Flashcard? {
        guard let id = queuedCard?["card"]["id"].int else { return nil }
        return snapshot.cards.first { $0.ankiID == id }
    }

    public func counts(for deckID: UUID? = nil) -> AnkiStudyCounts {
        guard let id = deckID ?? selectedDeckID else { return AnkiStudyCounts() }
        return countsByDeck[id] ?? AnkiStudyCounts()
    }

    public func cardCount(for deckID: UUID) -> Int { cardsByDeck[deckID] ?? 0 }

    public func refresh(reuseUnchangedCards: Bool = false) throws {
        metadata = try collection.applicationMetadata()
        var settings = StudySettings()
        if !metadata["settings"].isNull {
            settings = try JSONDecoder().decode(StudySettings.self, from: JSONEncoder().encode(metadata["settings"]))
        }
        let config = try collection.backend.call("anki.deck_config.GetDeckConfig", ["dcid": .id(1)])["config"]
        settings.newCardsPerDay = Int(config["newPerDay"].int)
        settings.dailyGoal = Int(config["reviewsPerDay"].int)
        settings.autoPlayAudio = !config["disableAutoplay"].bool
        snapshot = try collection.presentation(settings: settings, metadata: metadata, reuseUnchangedCards: reuseUnchangedCards)
        try refreshSummary()
    }

    private func refreshSummary() throws {
        noteTypes = try collection.noteTypes()
        statistics = try collection.statistics()
        studiedTodayMessage = try collection.backend.call("anki.scheduler.StudiedToday")["val"].string
        let timing = try collection.timing()
        studyDay = timing["daysElapsed"].int
        // ts/routes/graphs/graph-helpers.ts::dateFromNextDayAt.
        studyDayStart = Date(timeIntervalSince1970: timing["nextDayAt"].double - 86400)
        let undo = try collection.undoStatus()["undo"].string
        canUndo = !undo.isEmpty
        // qt/aqt/undo.py::UndoActionsInfo.from_undo_status. Translation IDs
        // are from generated/_fluent.py at the pinned upstream revision.
        undoTitle = try collection.backend.call("anki.i18n.TranslateString", [
            "moduleIndex": 35, "messageIndex": .integer(canUndo ? 5 : 4),
            "args": canUndo ? ["val": ["str": .string(undo)]] : [:],
        ])["val"].string
        let current = try collection.backend.call("anki.decks.GetCurrentDeck")
        selectedDeckID = .anki(current["id"].int)
        countsByDeck = [:]
        cardsByDeck = [:]
        func display(_ node: AnkiJSON) {
            countsByDeck[.anki(node["deckId"].int)] = AnkiStudyCounts(new: Int(node["newCount"].int), learning: Int(node["learnCount"].int), review: Int(node["reviewCount"].int))
            cardsByDeck[.anki(node["deckId"].int)] = Int(node["totalIncludingChildren"].int)
            node["children"].array.forEach(display)
        }
        display(try collection.deckTree())
        try refreshCongratulations()
    }

    public func beginReview(deckID: UUID?) throws {
        if let deckID, let id = snapshot.decks.first(where: { $0.id == deckID })?.ankiID { try collection.selectDeck(id) }
        isReviewing = true
        try nextCard()
    }

    /// qt/aqt/reviewer.py::cleanup clears the displayed card when review ends.
    public func endReview() { isReviewing = false; queuedCard = nil; reviewTimer = nil }

    /// A restored collection starts a new upstream backend/frontend session,
    /// including language, queue context, options, undo, and render state.
    public func restoreCollection(from file: URL) throws {
        try collection.restoreCollection(from: file)
        let reviewing = isReviewing
        queuedCard = nil
        reviewTimer = nil
        intervalLabels = []
        metadata = try collection.applicationMetadata()
        try reopenForInterfaceLanguage()
        try refresh()
        if reviewing { try nextCard() }
    }

    /// Faithful dispatch of qt/aqt/reviewer.py::op_executed/refresh_if_needed.
    /// Nested changes are protobuf response envelopes, not inferred changes.
    public func refreshAfterOperation(_ response: AnkiJSON, reuseUnchangedCards: Bool = false) throws {
        try refresh(reuseUnchangedCards: reuseUnchangedCards)
        guard isReviewing else { return }
        var changes = response
        while !changes["changes"].isNull { changes = changes["changes"] }
        if changes["studyQueues"].bool {
            try nextCard()
        } else if changes["noteText"].bool {
            try reloadDisplayedCard()
            reviewTextGeneration += 1
        } else if changes["card"].bool {
            try reloadDisplayedCard()
        }
    }

    private func reloadDisplayedCard() throws {
        guard let queuedCard else { return }
        var queued = queuedCard.object
        queued["card"] = try collection.card(queuedCard["card"]["id"].int)
        self.queuedCard = .object(queued)
    }

    public func reviewerWillRedrawQuestion() { statesMutated = stateMutationJavaScript == nil }

    /// Only upstream timing determines when cached screen data needs refreshing.
    public func refreshStudyDay() throws {
        guard try collection.timing()["daysElapsed"].int != studyDay else { return }
        let reviewing = isReviewing
        try refresh()
        if reviewing { try nextCard() }
    }

    public func selectDeck(_ deckID: UUID) throws {
        guard let id = snapshot.decks.first(where: { $0.id == deckID })?.ankiID else { return }
        try collection.selectDeck(id)
        selectedDeckID = deckID
        try refreshCongratulations()
    }

    public func nextCard() throws {
        let result = try collection.queue()
        reviewGeneration += 1
        queuedCard = result["cards"].array.first
        // qt/aqt/reviewer.py::V3CardInfo.from_queue copies the card's custom
        // data into the current state before the official JS mutation hook.
        if let queuedCard {
            var card = queuedCard.object
            var states = queuedCard["states"].object
            var current = queuedCard["states"]["current"].object
            current["customData"] = queuedCard["card"]["customData"].isNull ? "" : queuedCard["card"]["customData"]
            states["current"] = .object(current)
            card["states"] = .object(states)
            self.queuedCard = .object(card)
            // qt/aqt/reviewer.py::_get_next_v3_card starts the card timer after
            // constructing V3CardInfo/Card, before rendering and mutation work.
            reviewTimer = AnkiReviewTimer(startedAt: reviewClock())
        } else {
            reviewTimer = nil
        }
        let customizer: String
        do {
            let value = try collection.backend.call("anki.config.GetConfigJson", ["val": "cardStateCustomizer"])
            guard let bytes = Data(base64Encoded: value["json"].string) else {
                throw AnkiBackendError(message: "Invalid Anki configuration response.", kind: "TRANSPORT")
            }
            customizer = try JSONDecoder().decode(AnkiJSON.self, from: bytes).string
        } catch let error as AnkiBackendError where error.kind == "NOT_FOUND_ERROR" { customizer = "" }
        statesMutated = customizer.isEmpty
        // qt/aqt/reviewer.py::RUN_STATE_MUTATION. Preserve newlines so a final
        // comment in the imported script cannot consume the wrapper.
        stateMutationJavaScript = customizer.isEmpty ? nil : """
        anki.mutateNextCardStates('\(stateMutationKey)', async (states, customData, ctx) => {
            \(customizer)
            }).finally(() => bridgeCommand('statesMutated'));
        """
        intervalLabels = try queuedCard.map { try collection.describeIntervals($0["states"]) } ?? []
        if queuedCard == nil {
            try refreshCongratulations()
        }
    }

    private func refreshCongratulations() throws {
        congratulations = try collection.congratulations()
        nextLearningDate = congratulations["learnRemaining"].int > 0 ? Date.now.addingTimeInterval(congratulations["secsUntilNextLearn"].double) : nil
    }

    public func answer(rating: ReviewRating, duration: TimeInterval? = nil) throws {
        guard let queuedCard, statesMutated else { return }
        guard let timer = duration.map({ _ in AnkiReviewTimer(startedAt: 0) }) ?? reviewTimer else {
            throw AnkiBackendError(message: "No reviewer card timer.", kind: "INVALID_INPUT")
        }
        // pylib/anki/scheduler/v3.py::build_answer requests capped=False.
        // Keep elapsed milliseconds intact for Anki's answer-time validation.
        let milliseconds = try timer.timeTaken(at: duration ?? reviewClock(), capped: false, timeLimitMilliseconds: 0)
        try collection.answer(queuedCard, rating: rating, millisecondsTaken: milliseconds)
        try refresh(reuseUnchangedCards: true)
        try nextCard()
    }

    /// Like reviewer.py::answer_card().run_in_background, submit the native
    /// answer away from the UI thread. The collection still owns every state
    /// transition; caching only avoids rendering unchanged browser rows.
    public func answerInBackground(rating: ReviewRating) async throws {
        guard let queuedCard, statesMutated, let timer = reviewTimer else { return }
        let milliseconds = try timer.timeTaken(at: reviewClock(), capped: false, timeLimitMilliseconds: 0)
        let collection = collection
        let settings = snapshot.settings
        let metadata = metadata
        let presentation = try await Task.detached(priority: .userInitiated) {
            try collection.answer(queuedCard, rating: rating, millisecondsTaken: milliseconds)
            return try collection.presentation(settings: settings, metadata: metadata, reuseUnchangedCards: true)
        }.value
        snapshot = presentation
        try refreshSummary()
        try nextCard()
    }

    /// Platform implementation of qt/aqt/mediasrv.py's reviewer endpoints.
    /// The messages and state transformation itself remain upstream code.
    public func reviewerRequest(path: String, data: Data) throws -> Data {
        switch path {
        case "/_anki/getSchedulingStatesWithContext":
            guard let queuedCard else { throw AnkiBackendError(message: "No reviewer card.", kind: "INVALID_INPUT") }
            return try collection.backend.encodeProtobuf("anki.frontend.SchedulingStatesWithContext", value: ["states": queuedCard["states"], "context": queuedCard["context"]])
        case "/_anki/setSchedulingStates":
            let request = try collection.backend.decodeProtobuf("anki.frontend.SetSchedulingStatesRequest", data: data)
            if request["key"].string == stateMutationKey, var queued = queuedCard?.object {
                queued["states"] = request["states"]
                queuedCard = .object(queued)
                intervalLabels = try collection.describeIntervals(request["states"])
            }
            return Data()
        case "/_anki/i18nResources":
            let request = try collection.backend.decodeProtobuf("anki.i18n.I18nResourcesRequest", data: data)
            let response = try collection.backend.call("anki.i18n.I18nResources", request)
            return try collection.backend.encodeProtobuf("anki.generic.Json", value: response)
        default:
            throw AnkiBackendError(message: "Unsupported Anki reviewer endpoint: \(path)", kind: "INVALID_INPUT")
        }
    }

    public func reviewerStatesMutated() { statesMutated = true }

    /// qt/aqt/mediasrv.py's generated backend handlers pass original protobuf
    /// messages through. Statistics computations/preferences remain upstream.
    public func statisticsRequest(path: String, data: Data) throws -> Data {
        let route: (method: String, input: String, output: String)
        switch path {
        case "/_anki/graphs": route = ("anki.stats.Graphs", "anki.stats.GraphsRequest", "anki.stats.GraphsResponse")
        case "/_anki/getGraphPreferences": route = ("anki.stats.GetGraphPreferences", "anki.generic.Empty", "anki.stats.GraphPreferences")
        case "/_anki/setGraphPreferences": route = ("anki.stats.SetGraphPreferences", "anki.stats.GraphPreferences", "anki.generic.Empty")
        case "/_anki/i18nResources": return try reviewerRequest(path: path, data: data)
        default: throw AnkiBackendError(message: "Unsupported Anki statistics endpoint: \(path)", kind: "INVALID_INPUT")
        }
        let request = try collection.backend.decodeProtobuf(route.input, data: data)
        let response = try collection.backend.call(route.method, request)
        #if DEBUG
        var diagnostics = statisticsTransportDiagnostics.object
        diagnostics[path] = ["request": request, "response": response]
        statisticsTransportDiagnostics = .object(diagnostics)
        #endif
        return try collection.backend.encodeProtobuf(route.output, value: response)
    }

    /// Titles from the pinned generated/_fluent.py accessors. UI selection uses
    /// the same localized labels as the unmodified upstream graph components.
    public func statisticsChartTitles() throws -> [String: String] {
        var titles: [String: String] = [:]
        for (name, index) in [("reviews", 100), ("future", 59), ("added", 1)] {
            titles[name] = try collection.backend.call("anki.i18n.TranslateString", ["moduleIndex": 32, "messageIndex": .integer(Int64(index))])["val"].string
        }
        return titles
    }

    public func typedAnswer(for cardID: Int64, question: String) throws -> AnkiTypedAnswer {
        let card = try collection.card(cardID)
        let note = try collection.note(card["noteId"].int)
        let type = try collection.noteType(note["notetypeId"].int)
        return try AnkiTypedAnswer(backend: collection.backend, question: question,
            fields: type["fields"], values: note["fields"], cardOrdinal: card["templateIdx"].int)
    }

    /// qt/aqt/main.py::prepare_card_text_for_display and _add_play_buttons.
    public func prepareCardTextForDisplay(_ html: String) throws -> String {
        let escaped = try escapeMediaFilenames(html)
        let hide = try collection.backend.call("anki.config.GetConfigBool", ["key": "HIDE_AUDIO_PLAY_BUTTONS"])["val"].bool
        return hide ? AnkiFrontend.stripAudioReferences(escaped) : AnkiFrontend.audioReferencesToPlayIcons(escaped)
    }

    public func escapeMediaFilenames(_ html: String) throws -> String {
        try collection.backend.call("anki.card_rendering.EncodeIriPaths", ["val": .string(html)])["val"].string
    }

    public func undo() throws { try refreshAfterOperation(collection.undo()) }

    public func saveDeck(_ deck: Deck) throws {
        let id: Int64
        let changes: AnkiJSON
        if let existing = deck.ankiID { id = existing; changes = try collection.renameDeck(id, name: deck.name) }
        else { let result = try collection.addDeckWithChanges(name: deck.name); id = result["id"].int; changes = result }
        var appearances = metadata["decks"].object
        appearances[String(id)] = ["symbol": .string(deck.symbol), "colorIndex": .integer(Int64(deck.colorIndex))]
        try saveMetadata(key: "decks", value: .object(appearances))
        try refreshAfterOperation(changes)
    }

    public func deleteDeck(_ deck: Deck) throws {
        guard let id = deck.ankiID else { return }
        try refreshAfterOperation(collection.removeDeck(id))
    }

    public func newNoteFields(noteTypeID: Int64) throws -> [AnkiNoteField] {
        let type = try collection.noteType(noteTypeID)
        let note = try collection.newNote(noteTypeID: noteTypeID)
        return zip(type["fields"].array, note["fields"].array).enumerated().map { AnkiNoteField(id: $0.offset, name: $0.element.0["name"].string, value: $0.element.1.string) }
    }

    public func defaultNoteTypeID() throws -> Int64 {
        try collection.backend.call("anki.notes.DefaultsForAdding")["notetypeId"].int
    }

    public func saveNote(card: Flashcard?, deckID: Int64, noteTypeID: Int64, fields: [AnkiNoteField], tags: String) throws {
        var note = try card?.ankiNoteID.map { try collection.note($0) } ?? collection.newNote(noteTypeID: noteTypeID)
        var values = note.object
        values["fields"] = .array(fields.map { .string($0.value) })
        // rslib/src/tags/register.rs::canonify_tags explicitly accepts raw text
        // as one list element. Anki splits only ASCII/ideographic spaces and
        // owns normalization, case, hierarchy, ordering, and deduplication.
        values["tags"] = [.string(tags)]
        note = .object(values)
        let changes: AnkiJSON
        if let card, let id = card.ankiID {
            let undo = try collection.backend.call("anki.collection.AddCustomUndoEntry", ["val": "Edit note"])["val"]
            try collection.updateNote(note)
            if card.deckID != .anki(deckID) { try collection.moveCards([id], to: deckID) }
            changes = try collection.backend.call("anki.collection.MergeUndoEntries", ["val": undo])
        } else { changes = try collection.addNoteWithChanges(note, deckID: deckID) }
        try refreshAfterOperation(changes)
    }

    /// qt/aqt/browser/browser.py::delete_selected_notes deletes the selected
    /// notes, not just one generated card. Native RemoveNotes owns that scope.
    public func deleteNote(of card: Flashcard) throws {
        guard let id = card.ankiID else { return }
        try refreshAfterOperation(collection.removeNotesForCards([id]))
    }
    public func toggleSuspended(_ card: Flashcard) throws {
        guard let id = card.ankiID else { return }
        let changes = try card.isSuspended ? collection.restoreCards([id]) : collection.suspendCards([id])
        try refreshAfterOperation(changes)
    }
    public func resetCard(_ card: Flashcard) throws {
        guard let id = card.ankiID else { return }
        try refreshAfterOperation(collection.resetCards([id]))
    }

    public func currentPreset(_ options: AnkiJSON) throws -> AnkiJSON {
        let id = options["currentDeck"]["configId"].int
        guard let config = options["allConfig"].array.first(where: { $0["config"]["id"].int == id })?["config"] else {
            throw AnkiBackendError(message: "The deck's Anki preset could not be read.", kind: "NOT_FOUND_ERROR")
        }
        return config
    }

    public func newCardLimit(_ deck: Deck) throws -> Int {
        guard let id = deck.ankiID else { return 0 }
        let options = try collection.deckOptions(id)
        return Int(options["currentDeck"]["limits"]["new"].isNull ? try currentPreset(options)["config"]["newPerDay"].int : options["currentDeck"]["limits"]["new"].int)
    }

    public func filteredDeckOptions(_ id: Int64) throws -> AnkiJSON {
        try collection.backend.call("anki.decks.GetOrCreateFilteredDeck", ["did": .id(id)])
    }

    /// qt/aqt/filtered_deck.py::_available_order_values hides FSRS-only orders
    /// unless the collection has FSRS enabled. Labels come from upstream.
    public func filteredOrderLabels() throws -> [(value: Int, title: String)] {
        let labels = try collection.backend.call("anki.decks.FilteredDeckOrderLabels")["vals"].array.map(\.string)
        let fsrs = try collection.deckOptions(1)["fsrs"].bool
        return labels.enumerated().filter { fsrs || ![8, 9].contains($0.offset) }.map { ($0.offset, $0.element) }
    }

    public func saveFilteredDeck(_ options: AnkiJSON) throws {
        // AddOrUpdateFilteredDeck also builds the deck, as in the Qt dialog.
        try refreshAfterOperation(collection.backend.call("anki.decks.AddOrUpdateFilteredDeck", options))
    }

    public func emptyFilteredDeck(_ id: Int64) throws {
        try refreshAfterOperation(collection.backend.call("anki.scheduler.EmptyFilteredDeck", ["did": .id(id)]))
    }

    public func saveDeckLimit(_ limit: Int?, key: String, deck: Deck) throws {
        guard let id = deck.ankiID else { return }
        let options = try collection.deckOptions(id)
        var limits = options["currentDeck"]["limits"].object
        if let limit { limits[key] = .integer(Int64(limit)) } else { limits.removeValue(forKey: key) }
        try refreshAfterOperation(collection.saveDeckOptions(id, config: currentPreset(options), limits: .object(limits), options: options))
    }

    public func savePresetValue(_ value: AnkiJSON, key: String, deck: Deck) throws {
        guard let id = deck.ankiID else { return }
        let options = try collection.deckOptions(id)
        var preset = try currentPreset(options).object
        var config = preset["config"]!.object
        config[key] = value
        preset["config"] = .object(config)
        try refreshAfterOperation(collection.saveDeckOptions(id, config: .object(preset), limits: options["currentDeck"]["limits"], options: options))
    }

    public func clonePreset(for deck: Deck) throws {
        guard let id = deck.ankiID else { return }
        let options = try collection.deckOptions(id)
        var preset = try currentPreset(options).object
        preset["id"] = .id(0)
        preset["name"] = .string(deck.name)
        try refreshAfterOperation(collection.saveDeckOptions(id, config: .object(preset), limits: options["currentDeck"]["limits"], options: options))
    }

    public func saveCollectionOption(_ value: AnkiJSON, key: String, deck: Deck) throws {
        guard let id = deck.ankiID else { return }
        var options = try collection.deckOptions(id).object
        options[key] = value
        let updated = AnkiJSON.object(options)
        try refreshAfterOperation(collection.saveDeckOptions(id, config: currentPreset(updated), limits: updated["currentDeck"]["limits"], options: updated))
    }

    public func saveSettings(_ settings: StudySettings) throws {
        let old = snapshot.settings
        var changes: AnkiJSON = [:]
        if old.newCardsPerDay != settings.newCardsPerDay || old.dailyGoal != settings.dailyGoal || old.autoPlayAudio != settings.autoPlayAudio {
            let options = try collection.deckOptions(1)
            var preset = try collection.backend.call("anki.deck_config.GetDeckConfig", ["dcid": .id(1)]).object
            var config = preset["config"]!.object
            config["newPerDay"] = .integer(Int64(settings.newCardsPerDay))
            config["reviewsPerDay"] = .integer(Int64(settings.dailyGoal))
            config["disableAutoplay"] = .bool(!(settings.autoPlayAudio ?? true))
            preset["config"] = .object(config)
            changes = try collection.saveDeckOptions(1, config: .object(preset), limits: options["currentDeck"]["limits"], options: options)
        }
        let encoded = try JSONDecoder().decode(AnkiJSON.self, from: JSONEncoder().encode(settings))
        try saveMetadata(key: "settings", value: encoded)
        if old.interfaceLanguage != settings.interfaceLanguage {
            try localizeGuide()
            try reopenForInterfaceLanguage()
        }
        try refreshAfterOperation(changes, reuseUnchangedCards: true)
        if isReviewing && old.interfaceLanguage != settings.interfaceLanguage { try nextCard() }
    }

    public func search(_ text: String, deckID: UUID?, stage: String) throws -> [UUID] {
        var filters: [AnkiJSON] = []
        if !text.isEmpty { filters.append(["parsableText": .string(text)]) }
        if let id = deckID.flatMap({ id in snapshot.decks.first { $0.id == id }?.ankiID }) { filters.append(["parsableText": .string("did:\(id)")]) }
        switch stage {
        case "new": filters.append(["cardState": "CARD_STATE_NEW"])
        case "learning": filters.append(["parsableText": "is:learn -is:review"])
        case "review": filters.append(["parsableText": "is:review -is:learn"])
        case "relearning": filters.append(["parsableText": "is:learn is:review"])
        case "suspended": filters.append(["cardState": "CARD_STATE_SUSPENDED"])
        default: break
        }
        let node: AnkiJSON = ["group": ["joiner": "AND", "nodes": .array(filters)]]
        let query = try collection.backend.call("anki.search.BuildSearchString", node)["val"].string
        return try collection.searchCards(query).map(UUID.anki)
    }

    private func saveMetadata(key: String, value: AnkiJSON) throws {
        var next = metadata.object
        next[key] = value
        let result = AnkiJSON.object(next)
        try collection.saveApplicationMetadata(result)
        metadata = result
    }

    private func seedGuide() throws {
        let sample = BuiltInDecks.initialCollection(locale: InterfaceLanguage.system.locale(preferredLanguages: preferredSystemLanguages))
        guard let deck = sample.decks.first else { return }
        let id = try collection.addDeck(name: deck.name)
        let type = try defaultNoteTypeID()
        var ids: [String: AnkiJSON] = [:]
        for card in sample.cards {
            var note = try collection.newNote(noteTypeID: type).object
            note["fields"] = [.string(card.front), .string(card.back)]
            note["tags"] = .array(card.tags.map(AnkiJSON.string))
            ids[card.builtInID!] = .id(try collection.addNote(.object(note), deckID: id))
        }
        try saveMetadata(key: "guide", value: ["deckID": .id(id), "notes": .object(ids)])
        try saveMetadata(key: "decks", value: .object([String(id): ["symbol": "sparkles", "colorIndex": 2]]))
        try saveMetadata(key: "initialized", value: true)
        try collection.selectDeck(id)
    }

    private func localizeGuide() throws {
        let settings = try JSONDecoder().decode(StudySettings.self, from: JSONEncoder().encode(metadata["settings"]))
        let language = InterfaceLanguage(rawValue: settings.interfaceLanguage ?? "system") ?? .system
        let sample = BuiltInDecks.initialCollection(locale: language.locale(preferredLanguages: preferredSystemLanguages))
        let original = [InterfaceLanguage.english, .simplifiedChinese].map { BuiltInDecks.initialCollection(locale: $0.locale()) }
        if metadata["guide"]["deckID"].int != 0 {
            let id = metadata["guide"]["deckID"].int
            do {
                let deck = try collection.deck(id)
                if original.contains(where: { $0.decks.first?.name == deck["name"].string }), let name = sample.decks.first?.name { try collection.renameDeck(id, name: name) }
            } catch let error as AnkiBackendError where error.kind == "NOT_FOUND_ERROR" { }
        }
        for card in sample.cards {
            guard let key = card.builtInID, let id = metadata["guide"]["notes"].object[key]?.int else { continue }
            do {
                var note = try collection.note(id).object
                let fields = note["fields"]!.array.map(\.string)
                if original.contains(where: { snapshot in snapshot.cards.contains { $0.builtInID == key && [$0.front, $0.back] == fields } }) {
                    note["fields"] = [.string(card.front), .string(card.back)]
                    note["tags"] = .array(card.tags.map(AnkiJSON.string))
                    try collection.updateNote(.object(note))
                }
            } catch let error as AnkiBackendError where error.kind == "NOT_FOUND_ERROR" { }
        }
    }

    private func reopenForInterfaceLanguage() throws {
        let language = InterfaceLanguage(rawValue: metadata["settings"]["interfaceLanguage"].string) ?? .system
        let preferred = language.resolved(preferredLanguages: preferredSystemLanguages).rawValue == "zh-Hans" ? "zh-CN" : "en"
        try collection.close()
        collection = try AnkiCollection(directory: directory, preferredLanguages: [preferred])
        // A new frontend/backend session gets the upstream reviewer identity.
        stateMutationKey = String(UInt64.random(in: .min ... .max))
    }
}
