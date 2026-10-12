import Foundation

/// One-time file-format conversion for the discontinued OpenAnki JSON schema.
/// This is not a scheduler/import fallback: converted data is exported/imported
/// by Anki itself, and every subsequent operation uses the upstream collection.
/// The exact input is retained in Anki configuration and the original files are
/// untouched. Previously flattened note templates cannot be reconstructed.
public enum LegacyCollectionMigration {
    public static func migrate(directory: URL) throws {
        let source = directory.appendingPathComponent("collection.json")
        let data = try Data(contentsOf: source)
        let snapshot = try JSONDecoder().decode(CollectionSnapshot.self, from: data)
        try snapshot.validate()
        let package = try convert(snapshot, media: directory.appendingPathComponent("Media"), originalJSON: data)
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
        let backend = try AnkiBackend()
        // Import into a closed backend so no empty target DB can mask a failed
        // migration. Anki checks the replacement DB before its atomic rename.
        try backend.call("anki.import_export.ImportCollectionPackage", [
            "colPath": .string(directory.appendingPathComponent("collection.anki2").path),
            "backupPath": .string(package.path), "mediaFolder": .string(directory.appendingPathComponent("collection.media").path),
            "mediaDb": .string(directory.appendingPathComponent("collection.media.db2").path),
        ])
    }

    /// Converts authored legacy cards into native Basic note types. Separate
    /// media namespaces are merged by Anki's APKG importer, which performs all
    /// filename conflict handling and note/media reference rewriting.
    public static func convert(_ snapshot: CollectionSnapshot, media: URL, originalJSON: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenAnkiMigration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var successful = false
        defer { if !successful { try? FileManager.default.removeItem(at: root) } }
        let target = try AnkiCollection(directory: root.appendingPathComponent("target"))
        defer { try? target.close() }
        let groups = Dictionary(grouping: snapshot.cards, by: { $0.mediaFolder ?? "" })
        let history = Dictionary(grouping: snapshot.reviews, by: \.cardID)
        var cardIDs: [UUID: Int64] = [:]
        var usedCardIDs = Set<Int64>()
        var usedReviewIDs = Set<Int64>()

        for (groupIndex, group) in groups.sorted(by: { $0.key < $1.key }).enumerated() {
            let staging = try AnkiCollection(directory: root.appendingPathComponent("source-\(groupIndex)"))
            var closed = false
            defer { if !closed { try? staging.close() } }
            var decks: [UUID: Int64] = [:]
            for deck in snapshot.decks { decks[deck.id] = try staging.addDeck(name: deck.name) }
            if !group.key.isEmpty {
                guard CollectionSnapshot.safeComponent(group.key) else { throw CollectionError.invalid("媒体路径无效。") }
                let folder = media.appendingPathComponent(group.key)
                for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if file.lastPathComponent.hasPrefix(".openanki-render-") { continue }
                    if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile != true { continue }
                    let installed = try staging.backend.call("anki.media.AddMediaFromPath", ["path": .string(file.path)])["val"].string
                    guard installed == file.lastPathComponent else {
                        throw AnkiBackendError(message: "A legacy media filename requires normalization. Original files are preserved: \(file.lastPathComponent)", kind: "MIGRATION_MEDIA")
                    }
                }
            }
            var types: [String: Int64] = [:]
            let defaultType = try staging.backend.call("anki.notes.DefaultsForAdding")["notetypeId"].int
            let stock = try staging.noteType(defaultType)
            let timing = try staging.timing()
            let now = Date.now
            for card in group.value.sorted(by: { $0.createdAt < $1.createdAt }) {
                let typeID: Int64
                if let id = types[card.css] { typeID = id }
                else {
                    var type = stock.object
                    type["id"] = .id(0)
                    type["name"] = .string("OpenAnki legacy \(groupIndex + 1)-\(types.count + 1)")
                    var config = type["config"]!.object
                    config["css"] = .string(card.css)
                    type["config"] = .object(config)
                    var template = type["templates"]!.array[0].object
                    var templateConfig = template["config"]!.object
                    templateConfig["qFormat"] = "{{Front}}"
                    templateConfig["aFormat"] = "{{Back}}"
                    template["config"] = .object(templateConfig)
                    type["templates"] = .array([.object(template)])
                    typeID = try staging.backend.call("anki.notetypes.AddNotetype", .object(type))["id"].int
                    types[card.css] = typeID
                }
                var note = try staging.newNote(noteTypeID: typeID).object
                note["guid"] = .string(card.id.uuidString)
                note["fields"] = [.string(card.isHTML ? card.front : plainHTML(card.front)), .string(card.isHTML ? card.back : plainHTML(card.back))]
                note["tags"] = .array(card.tags.map(AnkiJSON.string))
                let noteID = try staging.addNote(.object(note), deckID: decks[card.deckID]!)
                let generated = try staging.backend.call("anki.notes.CardsOfNote", ["nid": .id(noteID)])["cids"].array[0].int
                // UUID -> native timestamp identity conversion preserves the
                // original added date (Anki stores it in the card identifier).
                var id = Int64((card.createdAt.timeIntervalSince1970 * 1000).rounded())
                while usedCardIDs.contains(id) { id += 1 }
                usedCardIDs.insert(id)
                cardIDs[card.id] = id
                let ctype: Int64
                let queue: Int64
                let due: Int64
                let left: Int64
                switch card.stage {
                case .new:
                    ctype = 0; queue = 0; due = try staging.card(generated)["due"].int; left = 0
                case .learning:
                    ctype = 1; queue = 1; due = Int64(card.due.timeIntervalSince1970); left = card.learningStep == 0 ? 2 : 1
                case .relearning:
                    ctype = 3; queue = 1; due = Int64(card.due.timeIntervalSince1970); left = 1
                case .review:
                    ctype = 2; queue = 2; left = 0
                    // Reverse of rslib/src/stats/card.rs::due_date. Anki review
                    // due values are integer study days, not wall-clock dates.
                    due = timing["daysElapsed"].int + Int64((card.due.timeIntervalSince(now) / 86400).rounded())
                }
                try staging.backend.call("anki.db", ["kind": "query", "sql": "update cards set id=?, type=?, queue=?, due=?, ivl=?, factor=?, reps=?, lapses=?, left=? where id=?", "first_row_only": false,
                    "args": .array([.integer(id), .integer(ctype), .integer(card.isSuspended ? -1 : queue), .integer(due), .integer(Int64(card.interval.rounded())), .integer(Int64((card.ease * 1000).rounded())), .integer(Int64(card.repetitions)), .integer(Int64(card.lapses)), .integer(left), .integer(generated)])])
                let records = (history[card.id] ?? []).sorted { $0.date < $1.date }
                for (index, record) in records.enumerated() {
                    let next = index + 1 < records.count ? records[index + 1].previousState : SchedulingState(card: card)
                    func interval(_ state: SchedulingState, reviewedAt: Date?) -> Int64 {
                        if state.stage == .review { return Int64(state.interval.rounded()) }
                        guard let reviewedAt else { return 0 }
                        return -Int64(state.due.timeIntervalSince(reviewedAt).rounded())
                    }
                    var reviewID = Int64((record.date.timeIntervalSince1970 * 1000).rounded())
                    while usedReviewIDs.contains(reviewID) { reviewID += 1 }
                    usedReviewIDs.insert(reviewID)
                    let kind: Int64 = record.previousState.stage == .review ? 1 : record.previousState.stage == .relearning ? 2 : 0
                    try staging.backend.call("anki.db", ["kind": "query", "first_row_only": false,
                        "sql": "insert into revlog(id,cid,usn,ease,ivl,lastIvl,factor,time,type) values(?,?,?,?,?,?,?,?,?)",
                        "args": [.integer(reviewID), .integer(id), -1, .integer(Int64(record.rating.rawValue)), .integer(interval(next, reviewedAt: record.date)), .integer(interval(record.previousState, reviewedAt: record.previousState.lastReviewedAt)), .integer(Int64((next.ease * 1000).rounded())), .integer(Int64((record.duration * 1000).rounded())), .integer(kind)]])
                }
            }
            let package = root.appendingPathComponent("namespace-\(groupIndex).apkg")
            try staging.backend.call("anki.import_export.ExportAnkiPackage", ["outPath": .string(package.path), "options": ["withScheduling": true, "withDeckConfigs": true, "withMedia": true, "legacy": false], "limit": ["wholeCollection": [:]]])
            try staging.close(); closed = true
            try target.backend.call("anki.import_export.ImportAnkiPackage", ["packagePath": .string(package.path), "options": ["withScheduling": true, "withDeckConfigs": true, "mergeNotetypes": false]])
        }

        var appearances: [String: AnkiJSON] = [:]
        var guideNotes: [String: AnkiJSON] = [:]
        var guideDeck: Int64 = 0
        for deck in snapshot.decks {
            let id: Int64
            do { id = try target.backend.call("anki.decks.GetDeckIdByName", ["val": .string(deck.name)])["did"].int }
            catch let error as AnkiBackendError where error.kind == "NOT_FOUND_ERROR" { id = try target.addDeck(name: deck.name) }
            appearances[String(id)] = ["symbol": .string(deck.symbol), "colorIndex": .integer(Int64(deck.colorIndex))]
            if deck.builtInID == "guide" { guideDeck = id }
            let options = try target.deckOptions(id)
            let configID = options["currentDeck"]["configId"].int
            var config = options["allConfig"].array.first { $0["config"]["id"].int == configID }!["config"].object
            var values = config["config"]!.object
            values["newPerDay"] = .integer(Int64(snapshot.settings.newCardsPerDay))
            values["disableAutoplay"] = .bool(!(snapshot.settings.autoPlayAudio ?? true))
            if deck.studyOrder == .random {
                config["id"] = .id(0); config["name"] = .string(deck.name)
                values["newCardGatherPriority"] = "NEW_CARD_GATHER_PRIORITY_RANDOM_CARDS"
                values["newCardSortOrder"] = "NEW_CARD_SORT_ORDER_RANDOM_CARD"
                values["reviewOrder"] = "REVIEW_CARD_ORDER_RANDOM"
            }
            config["config"] = .object(values)
            let limits: AnkiJSON = deck.newCardsPerDay.map { ["new": .integer(Int64($0))] } ?? [:]
            try target.saveDeckOptions(id, config: .object(config), limits: limits, options: options)
        }
        // Import today's recorded activity through Anki's own counter update,
        // including its parent propagation and configured study-day boundary.
        let nextDay = (try target.timing())["nextDayAt"].double
        for record in snapshot.reviews where record.date.timeIntervalSince1970 >= nextDay - 86400 && record.date.timeIntervalSince1970 < nextDay {
            guard let deck = snapshot.decks.first(where: { $0.id == record.deckID }) else { continue }
            let id = try target.backend.call("anki.decks.GetDeckIdByName", ["val": .string(deck.name)])["did"]
            try target.backend.call("anki.scheduler.UpdateStats", ["deckId": id,
                "newDelta": .integer(record.previousState.stage == .new ? 1 : 0),
                "reviewDelta": .integer(record.previousState.stage == .review ? 1 : 0),
                "millisecondDelta": .integer(Int64((record.duration * 1000).rounded()))])
        }
        for card in snapshot.cards {
            if let key = card.builtInID, let id = cardIDs[card.id] { guideNotes[key] = try target.card(id)["noteId"] }
        }
        let settings = try JSONDecoder().decode(AnkiJSON.self, from: JSONEncoder().encode(snapshot.settings))
        try target.saveApplicationMetadata(["initialized": true, "settings": settings, "decks": .object(appearances), "guide": ["deckID": .id(guideDeck), "notes": .object(guideNotes)]])
        // Store the original format verbatim, including fractional intervals,
        // UUIDs, provenance, and legacy read-aloud metadata. Native day/interval
        // fields necessarily have Anki's integer representation.
        let archived = try JSONEncoder().encode(AnkiJSON.string(originalJSON.base64EncodedString())).base64EncodedString()
        try target.backend.call("anki.config.SetConfigJsonNoUndo", ["key": "openAnki.legacyArchive", "valueJson": .string(archived)])
        let backup = root.appendingPathComponent("converted.colpkg")
        try target.exportCollection(to: backup)
        successful = true
        return backup
    }

    private static func plainHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
    }
}
