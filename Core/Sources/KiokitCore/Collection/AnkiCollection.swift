// Portions adapted from pylib/anki/template.py in ankitects/anki 26.09.3.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

/// A collection owned by Anki. This class only binds upstream operations to
/// application paths and transports their arguments/results; it contains no
/// scheduling, sorting, importing, rendering, or collection mutation algorithms.
public final class AnkiCollection: @unchecked Sendable {
    public let directory: URL
    public let backend: AnkiBackend
    private let renderingLock = NSRecursiveLock()
    let presentationLock = NSLock()
    var presentationCache: [Int64: AnkiPresentationCacheEntry] = [:]
    private var latexWorkspace: URL?
    public var collectionURL: URL { directory.appendingPathComponent("collection.anki2") }
    public var mediaURL: URL { directory.appendingPathComponent("collection.media", isDirectory: true) }
    public var mediaDatabaseURL: URL { directory.appendingPathComponent("collection.media.db2") }

    public init(directory: URL, preferredLanguages: [String] = ["en"]) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        backend = try AnkiBackend(preferredLanguages: preferredLanguages)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try open()
    }

    public func open() throws {
        try backend.call("anki.collection.OpenCollection", [
            "collectionPath": .string(collectionURL.path),
            "mediaFolderPath": .string(mediaURL.path),
            "mediaDbPath": .string(mediaDatabaseURL.path),
        ])
    }

    deinit { if let latexWorkspace { try? FileManager.default.removeItem(at: latexWorkspace) } }

    /// Platform lifetime/serialization for Anki's reusable temporary TeX files.
    func withLatexWorkspace<T>(_ body: (URL) throws -> T) throws -> T {
        renderingLock.lock()
        defer { renderingLock.unlock() }
        if latexWorkspace == nil {
            let url = URL.temporaryDirectory.appendingPathComponent("openanki-latex-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            latexWorkspace = url
        }
        return try body(latexWorkspace!)
    }

    public func close() throws { try backend.call("anki.collection.CloseCollection") }

    public func deckNames() throws -> [AnkiJSON] {
        try backend.call("anki.decks.GetDeckNames", ["skipEmptyDefault": true, "includeFiltered": true])["entries"].array
    }

    public func deck(_ id: Int64) throws -> AnkiJSON {
        try backend.call("anki.decks.GetDeck", ["did": .id(id)])
    }

    @discardableResult
    public func addDeck(name: String) throws -> Int64 {
        try addDeckWithChanges(name: name)["id"].int
    }

    public func addDeckWithChanges(name: String) throws -> AnkiJSON {
        var deck = try backend.call("anki.decks.NewDeck").object
        deck["name"] = .string(name)
        return try backend.call("anki.decks.AddDeck", .object(deck))
    }

    @discardableResult public func renameDeck(_ id: Int64, name: String) throws -> AnkiJSON {
        try backend.call("anki.decks.RenameDeck", ["deckId": .id(id), "newName": .string(name)])
    }

    @discardableResult public func removeDeck(_ id: Int64) throws -> AnkiJSON {
        try backend.call("anki.decks.RemoveDecks", ["dids": [.id(id)]])
    }

    public func selectDeck(_ id: Int64) throws {
        try backend.call("anki.decks.SetCurrentDeck", ["did": .id(id)])
    }

    public func deckTree() throws -> AnkiJSON {
        try backend.call("anki.decks.DeckTree", ["now": .id(Int64(Date.now.timeIntervalSince1970))])
    }

    public func card(_ id: Int64) throws -> AnkiJSON {
        try backend.call("anki.cards.GetCard", ["cid": .id(id)])
    }

    /// pylib/anki/cards.py::current_deck_id and decks.py::config_dict_for_deck_id.
    /// Filtered cards use their original deck; filtered decks without an original
    /// deck use the upstream embedded configuration. Missing normal presets use
    /// the Default preset, exactly as the pinned Python implementation does.
    public func cardDeckConfiguration(_ card: AnkiJSON) throws -> AnkiJSON {
        let original = card["originalDeckId"].int
        let id = original == 0 ? card["deckId"].int : original
        func decode(_ response: AnkiJSON) throws -> AnkiJSON {
            guard let data = Data(base64Encoded: response["json"].string) else {
                throw AnkiBackendError(message: "Invalid Anki configuration transport.", kind: "TRANSPORT")
            }
            return try JSONDecoder().decode(AnkiJSON.self, from: data)
        }
        let deck = try decode(backend.call("anki.decks.GetDeckLegacy", ["did": .id(id)]))
        guard !deck.isNull else { throw AnkiBackendError(message: "Missing card deck.", kind: "NOT_FOUND_ERROR") }
        if deck["conf"].isNull { return deck }
        let config: AnkiJSON
        do { config = try decode(backend.call("anki.deck_config.GetDeckConfigLegacy", ["dcid": .id(deck["conf"].int)])) }
        catch let error as AnkiBackendError where error.kind == "NOT_FOUND_ERROR" {
            config = try decode(backend.call("anki.deck_config.GetDeckConfigLegacy", ["dcid": .id(1)]))
        }
        var values = config.object
        values["dyn"] = false
        return .object(values)
    }

    public func note(_ id: Int64) throws -> AnkiJSON {
        try backend.call("anki.notes.GetNote", ["nid": .id(id)])
    }

    public func noteTypes() throws -> [AnkiJSON] {
        try backend.call("anki.notetypes.GetNotetypeNames")["entries"].array
    }

    public func noteType(_ id: Int64) throws -> AnkiJSON {
        try backend.call("anki.notetypes.GetNotetype", ["ntid": .id(id)])
    }

    public func newNote(noteTypeID: Int64) throws -> AnkiJSON {
        try backend.call("anki.notes.NewNote", ["ntid": .id(noteTypeID)])
    }

    @discardableResult
    public func addNote(_ note: AnkiJSON, deckID: Int64) throws -> Int64 {
        try addNoteWithChanges(note, deckID: deckID)["noteId"].int
    }

    public func addNoteWithChanges(_ note: AnkiJSON, deckID: Int64) throws -> AnkiJSON {
        try backend.call("anki.notes.AddNote", ["note": note, "deckId": .id(deckID)])
    }

    @discardableResult public func updateNote(_ note: AnkiJSON) throws -> AnkiJSON {
        try backend.call("anki.notes.UpdateNotes", ["notes": .array([note])])
    }

    @discardableResult public func moveCards(_ ids: [Int64], to deckID: Int64) throws -> AnkiJSON {
        try backend.call("anki.cards.SetDeck", ["cardIds": .array(ids.map(AnkiJSON.id)), "deckId": .id(deckID)])
    }

    @discardableResult public func removeCards(_ ids: [Int64]) throws -> AnkiJSON {
        try backend.call("anki.cards.RemoveCards", ["cardIds": .array(ids.map(AnkiJSON.id))])
    }

    /// Browser deletion removes notes and every sibling card. Review-log
    /// retention and undo are controlled by Anki's native removal operation.
    /// RemoveNotes' cardIds input delegates card-to-note selection to Anki.
    @discardableResult public func removeNotesForCards(_ ids: [Int64]) throws -> AnkiJSON {
        try backend.call("anki.notes.RemoveNotes", ["cardIds": .array(ids.map(AnkiJSON.id))])
    }

    @discardableResult public func suspendCards(_ ids: [Int64]) throws -> AnkiJSON {
        try backend.call("anki.scheduler.BuryOrSuspendCards", ["cardIds": .array(ids.map(AnkiJSON.id)), "mode": "SUSPEND"])
    }

    @discardableResult public func restoreCards(_ ids: [Int64]) throws -> AnkiJSON {
        try backend.call("anki.scheduler.RestoreBuriedAndSuspendedCards", ["cids": .array(ids.map(AnkiJSON.id))])
    }

    @discardableResult public func resetCards(_ ids: [Int64]) throws -> AnkiJSON {
        let defaults = try backend.call("anki.scheduler.ScheduleCardsAsNewDefaults", ["context": "BROWSER"])
        return try backend.call("anki.scheduler.ScheduleCardsAsNew", [
            "cardIds": .array(ids.map(AnkiJSON.id)), "context": "BROWSER", "log": true,
            "restorePosition": defaults["restorePosition"], "resetCounts": defaults["resetCounts"],
        ])
    }

    public func searchCards(_ search: String, order: AnkiJSON = ["builtin": ["column": "noteCrt", "reverse": true]]) throws -> [Int64] {
        try backend.call("anki.search.SearchCards", ["search": .string(search), "order": order])["ids"].array.map(\.int)
    }

    public func queue(fetchLimit: Int = 1) throws -> AnkiJSON {
        try backend.call("anki.scheduler.GetQueuedCards", ["fetchLimit": .integer(Int64(fetchLimit))])
    }

    /// Answer from the exact states supplied by Anki, including its FSRS/SM-2
    /// choices, fuzzing, leech handling, learning steps, and custom card data.
    public func answer(_ queuedCard: AnkiJSON, rating: ReviewRating, millisecondsTaken: Int64) throws {
        let name: String
        switch rating { case .again: name = "again"; case .hard: name = "hard"; case .good: name = "good"; case .easy: name = "easy" }
        try backend.call("anki.scheduler.AnswerCard", [
            "cardId": queuedCard["card"]["id"], "currentState": queuedCard["states"]["current"],
            "newState": queuedCard["states"][name], "rating": .string(name.uppercased()),
            "answeredAtMillis": .id(Int64(Date.now.timeIntervalSince1970 * 1000)),
            "millisecondsTaken": .integer(millisecondsTaken),
        ])
    }

    public func describeIntervals(_ states: AnkiJSON) throws -> [String] {
        try backend.call("anki.scheduler.DescribeNextStates", states)["vals"].array.map(\.string)
    }

    public func undoStatus() throws -> AnkiJSON { try backend.call("anki.collection.GetUndoStatus") }
    @discardableResult public func undo() throws -> AnkiJSON { try backend.call("anki.collection.Undo") }
    public func congratulations() throws -> AnkiJSON { try backend.call("anki.scheduler.CongratsInfo") }
    public func timing() throws -> AnkiJSON { try backend.call("anki.scheduler.SchedTimingToday") }
    public func statistics(search: String = "", days: Int = 365) throws -> AnkiJSON {
        try backend.call("anki.stats.Graphs", ["search": .string(search), "days": .integer(Int64(days))])
    }
    public func cardStatistics(_ id: Int64) throws -> AnkiJSON { try backend.call("anki.stats.CardStats", ["cid": .id(id)]) }

    public func deckOptions(_ id: Int64) throws -> AnkiJSON {
        try backend.call("anki.deck_config.GetDeckConfigsForUpdate", ["did": .id(id)])
    }

    /// Preserves the current upstream options and collection-wide flags when
    /// saving a preset/limits. Callers pass the complete upstream configuration.
    @discardableResult public func saveDeckOptions(_ id: Int64, config: AnkiJSON, limits: AnkiJSON, options: AnkiJSON) throws -> AnkiJSON {
        let request: AnkiJSON = [
            "targetDeckId": .id(id), "configs": .array([config]), "limits": limits,
            "mode": "UPDATE_DECK_CONFIGS_MODE_NORMAL",
            "cardStateCustomizer": options["cardStateCustomizer"].isNull ? "" : options["cardStateCustomizer"],
            "newCardsIgnoreReviewLimit": options["newCardsIgnoreReviewLimit"],
            "fsrs": options["fsrs"], "applyAllParentLimits": options["applyAllParentLimits"],
            "fsrsHealthCheck": options["fsrsHealthCheck"],
        ]
        return try backend.call("anki.deck_config.UpdateDeckConfigs", request.omittingNullValues)
    }

    public func importPackage(_ url: URL) throws -> AnkiJSON {
        let options = try backend.call("anki.import_export.GetImportAnkiPackagePresets")
        return try backend.call("anki.import_export.ImportAnkiPackage", ["packagePath": .string(url.path), "options": options])
    }

    public func importText(_ url: URL) throws -> AnkiJSON {
        let metadata = try backend.call("anki.import_export.GetCsvMetadata", ["path": .string(url.path)])
        return try backend.call("anki.import_export.ImportCsv", ["path": .string(url.path), "metadata": metadata])
    }

    public func exportCollection(to url: URL) throws {
        // Upstream consumes/closes the collection during a full export.
        do {
            try backend.call("anki.import_export.ExportCollectionPackage", ["outPath": .string(url.path), "includeMedia": true, "legacy": false])
            try open()
        } catch {
            try? open()
            throw error
        }
    }

    public func restoreCollection(from url: URL) throws {
        try close()
        do {
            try backend.call("anki.import_export.ImportCollectionPackage", [
                "colPath": .string(collectionURL.path), "backupPath": .string(url.path),
                "mediaFolder": .string(mediaURL.path), "mediaDb": .string(mediaDatabaseURL.path),
            ])
            try open()
        } catch {
            try? open()
            throw error
        }
    }

    public func applicationMetadata() throws -> AnkiJSON {
        let response: AnkiJSON
        do { response = try backend.call("anki.config.GetConfigJson", ["val": "openAnki.interface"]) }
        catch let error as AnkiBackendError where error.kind == "NOT_FOUND_ERROR" { return [:] }
        let json = response["json"].string
        guard let bytes = Data(base64Encoded: json) else { return [:] }
        return try JSONDecoder().decode(AnkiJSON.self, from: bytes)
    }

    /// pylib/anki/collection.py::set_config uses SkipUndo by default, which
    /// preserves existing undo history. SetConfigJsonNoUndo clears that history.
    @discardableResult public func saveApplicationMetadata(_ metadata: AnkiJSON) throws -> AnkiJSON {
        let json = try JSONEncoder().encode(metadata).base64EncodedString()
        return try backend.call("anki.config.SetConfigJson", ["key": "openAnki.interface", "valueJson": .string(json), "undoable": false])
    }

    public func stripHTML(_ html: String) throws -> String {
        try backend.call("anki.card_rendering.StripHtml", ["text": .string(html)])["val"].string
    }

    /// rslib/src/browser_table.rs::RenderContext.side_str uses html_to_text_line(html,
    /// true) to avoid HTML whitespace becoming empty browser-list lines.
    public func browserTextLine(_ html: String) throws -> String {
        try backend.call("anki.card_rendering.HtmlToTextLine", ["text": .string(html), "preserveMediaFilenames": true])["val"].string
    }

    /// FrontSide completion follows pylib/anki/template.py::apply_custom_filters.
    /// Built-in filters are evaluated upstream (partialRender=true); native
    /// desktop add-on hooks are not available on iOS.
    public func renderedCard(_ id: Int64, browser: Bool = false, includeFrontSide: Bool = true) throws -> AnkiJSON {
        renderingLock.lock()
        defer { renderingLock.unlock() }
        let rendered: AnkiJSON
        do { rendered = try backend.call("anki.card_rendering.RenderExistingCard", ["cardId": .id(id), "browser": .bool(browser), "partialRender": true]) }
        catch let error as AnkiBackendError where error.kind == "TEMPLATE_PARSE" {
            // pylib/anki/template.py::render displays the backend's template
            // error on this card, instead of failing the entire collection.
            let side: AnkiJSON = ["text": .string(error.message), "avTags": []]
            return ["question": side, "answer": side, "css": ""]
        }
        func complete(_ nodes: AnkiJSON, frontSide: String?) -> String {
            nodes.array.map { node in
                if !node["text"].isNull { return node["text"].string }
                let replacement = node["replacement"]
                if replacement["fieldName"].string == "FrontSide", let frontSide { return frontSide }
                return replacement["currentText"].string
            }.joined()
        }
        let question = complete(rendered["questionNodes"], frontSide: nil)
        var questionAV = try backend.call("anki.card_rendering.ExtractAvTags", ["text": .string(question), "questionSide": true])
        // Card Details can omit the already displayed FrontSide. This is a
        // transient UI projection; ordinary rendering keeps Anki's exact output.
        let answer = complete(rendered["answerNodes"], frontSide: includeFrontSide ? questionAV["text"].string : "")
        var answerAV = try backend.call("anki.card_rendering.ExtractAvTags", ["text": .string(answer), "questionSide": false])
        func adaptTags(_ side: AnkiJSON) -> AnkiJSON {
            var value = side.object
            if !side["avTags"].isNull {
                value["avTags"] = .array(side["avTags"].array.map(AnkiAVFrontend.normalizedTag))
            }
            return .object(value)
        }
        questionAV = adaptTags(questionAV)
        answerAV = adaptTags(answerAV)
        if !browser {
            // pylib/anki/template.py invokes card_did_render after AV extraction;
            // the upstream LaTeX hook then updates only the side's HTML text.
            var model: AnkiJSON?
            func noteTypeForLatex() throws -> AnkiJSON {
                if let model { return model }
                let noteID = try card(id)["noteId"].int
                model = try noteType(note(noteID)["notetypeId"].int)
                return model!
            }
            var q = questionAV.object
            q["text"] = .string(try AnkiLatexRenderer.render(questionAV["text"].string, svg: rendered["latexSvg"].bool, collection: self, noteType: noteTypeForLatex))
            questionAV = .object(q)
            var a = answerAV.object
            a["text"] = .string(try AnkiLatexRenderer.render(answerAV["text"].string, svg: rendered["latexSvg"].bool, collection: self, noteType: noteTypeForLatex))
            answerAV = .object(a)
        }
        return ["question": questionAV, "answer": answerAV, "css": rendered["css"], "isEmpty": rendered["isEmpty"], "latexSvg": rendered["latexSvg"]]
    }
}

extension AnkiJSON {
    /// Protobuf optional fields may be absent; sending JSON null would clear
    /// them. Omit absent fields when constructing an upstream request.
    fileprivate var omittingNullValues: AnkiJSON { .object(object.filter { !$0.value.isNull }) }
}
