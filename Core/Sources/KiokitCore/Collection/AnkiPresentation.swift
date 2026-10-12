import Foundation

public struct AnkiNoteField: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public var value: String
}

/// Audio data comes from Anki's ExtractAvTags, including the original TTS
/// language/voice/speed configuration. There is no field-name inference.
public struct AnkiAudioTag: Codable, Hashable, Sendable {
    public var filename: String?
    public var text: String?
    public var language: String?
    public var voices: [String]
    public var speed: Double
    public var otherArguments: [String]

    public init(_ value: AnkiJSON) {
        let normalized = AnkiAVFrontend.normalizedTag(value)
        filename = normalized["soundOrVideo"].isNull ? nil : normalized["soundOrVideo"].string
        let tts = value["tts"]
        text = tts.isNull ? nil : tts["fieldText"].string
        language = tts.isNull ? nil : tts["lang"].string
        voices = tts["voices"].array.map(\.string)
        speed = tts.isNull ? 1 : tts["speed"].double
        otherArguments = tts["otherArgs"].array.map(\.string)
    }
}

extension UUID {
    /// Reversible identity conversion for SwiftUI. Native Anki IDs remain Int64
    /// in the database and every upstream request.
    public static func anki(_ id: Int64) -> UUID {
        let bits = UInt64(bitPattern: id)
        return UUID(uuidString: String(format: "00000000-0000-0000-%04llx-%012llx", bits >> 48, bits & 0x0000ffffffffffff))!
    }
}

/// Memoized display data only. Native card/note/template/configuration values
/// form the key; no cached value is used for scheduling or collection writes.
struct AnkiPresentationCacheEntry {
    let key: AnkiJSON
    let storedCard: [AnkiJSON]
    let card: Flashcard
}

extension AnkiCollection {
    /// Creates a read-only UI snapshot from upstream responses. The snapshot is
    /// never saved as collection data or used to make scheduling decisions.
    public func presentation(settings: StudySettings, metadata: AnkiJSON, reuseUnchangedCards: Bool = false) throws -> CollectionSnapshot {
        presentationLock.lock()
        defer { presentationLock.unlock() }
        let timing = try timing()
        var decks: [Deck] = []
        var nativeDecks: [AnkiJSON] = []
        for entry in try deckNames() {
            let id = entry["id"].int
            let native = try deck(id)
            // template.py::_prepare_fields reads deck names for Deck/Subdeck;
            // native daily counters are unrelated to a card's rendered content.
            nativeDecks.append(["id": native["id"], "name": native["name"]])
            let options = native["filtered"].isNull ? try deckOptions(id) : .null
            let appearance = metadata["decks"][String(id)]
            var deck = Deck(id: .anki(id), name: native["name"].string,
                            symbol: appearance["symbol"].isNull ? "rectangle.stack.fill" : appearance["symbol"].string,
                            colorIndex: Int(appearance["colorIndex"].int), createdAt: Date(timeIntervalSince1970: Double(id) / 1000))
            deck.ankiID = id
            deck.ankiOptions = options
            deck.ankiFilteredConfiguration = native["filtered"].isNull ? nil : native["filtered"]
            deck.newCardsPerDay = options["currentDeck"]["limits"]["new"].isNull ? nil : Int(options["currentDeck"]["limits"]["new"].int)
            deck.reviewsPerDay = options["currentDeck"]["limits"]["review"].isNull ? nil : Int(options["currentDeck"]["limits"]["review"].int)
            deck.builtInID = metadata["guide"]["deckID"].int == id ? "guide" : nil
            decks.append(deck)
        }

        var cards: [Flashcard] = []
        var noteTypes: [Int64: AnkiJSON] = [:]
        var notes: [Int64: AnkiJSON] = [:]
        var deckConfigurations: [Int64: AnkiJSON] = [:]
        var updatedCache: [Int64: AnkiPresentationCacheEntry] = [:]
        #if DEBUG
        let diagnoseCache = ProcessInfo.processInfo.environment["OPENANKI_PRESENTATION_DIAGNOSTICS"] != nil
        var reportedMisses = 0
        #endif
        // Read-only fingerprints through Anki's DB proxy. Column order follows
        // rslib/src/storage/card/get_card.sql and note/get.sql; native services
        // still produce every changed card's presentation and scheduling data.
        let storedCards = Dictionary(uniqueKeysWithValues: try backend.query("SELECT id,nid,did,ord,cast(mod AS integer),usn,type,queue,due,cast(ivl AS integer),factor,reps,lapses,left,odue,odid,flags,data FROM cards").map { ($0[0].int, $0) })
        let storedNotes = Dictionary(uniqueKeysWithValues: try backend.query("SELECT id,guid,mid,mod,usn,tags,flds,cast(sfld AS text),csum,flags,data FROM notes").map { ($0[0].int, $0) })
        for id in try searchCards("") {
            guard let storedCard = storedCards[id], let storedNote = storedNotes[storedCard[1].int] else {
                throw AnkiBackendError(message: "Missing native presentation row.", kind: "TRANSPORT")
            }
            let noteID = storedCard[1].int
            let noteTypeID = storedNote[2].int
            let noteType = try noteTypes[noteTypeID] ?? self.noteType(noteTypeID)
            noteTypes[noteTypeID] = noteType
            let decksForCard: AnkiJSON = ["deckId": storedCard[2], "originalDeckId": storedCard[15]]
            let effectiveDeckID = decksForCard["originalDeckId"].int == 0 ? decksForCard["deckId"].int : decksForCard["originalDeckId"].int
            let configuration = try deckConfigurations[effectiveDeckID] ?? cardDeckConfiguration(decksForCard)
            deckConfigurations[effectiveDeckID] = configuration
            // notetype/render.rs::render_existing_card/add_special_fields use
            // identity, note, ordinal, original/current deck and flags. Changes
            // to queue/due/reps refresh native stats without re-rendering HTML.
            let renderCard = [0, 1, 2, 3, 15, 16].map { storedCard[$0] }
            let key: AnkiJSON = ["renderCard": .array(renderCard), "storedNote": .array(storedNote), "noteType": noteType,
                "configuration": configuration, "decks": .array(nativeDecks), "timing": timing, "guide": metadata["guide"]]
            #if DEBUG
            if diagnoseCache, reuseUnchangedCards, reportedMisses < 2,
               let cached = presentationCache[id], cached.key != key {
                let changed = key.object.keys.filter { key[$0] != cached.key[$0] }.sorted()
                print("Native presentation cache miss \(id): \(changed)")
                reportedMisses += 1
            }
            #endif
            if reuseUnchangedCards, let cached = presentationCache[id], cached.key == key {
                var card = cached.card
                // stats/card.rs::due_date returns None for new cards, and
                // includes TimestampSecs::now() for day-based review queues.
                if cached.storedCard != storedCard {
                    applySchedulingDisplay(try self.card(id), statistics: try cardStatistics(id), to: &card)
                } else if card.stage != .new {
                    let statistics = try cardStatistics(id)
                    card.due = statistics["dueDate"].isNull ? .distantFuture : Date(timeIntervalSince1970: statistics["dueDate"].double)
                    card.lastReviewedAt = statistics["latestReview"].isNull ? nil : Date(timeIntervalSince1970: statistics["latestReview"].double)
                }
                cards.append(card)
                updatedCache[id] = AnkiPresentationCacheEntry(key: key, storedCard: storedCard, card: card)
                continue
            }
            let native = try card(id)
            let note = try notes[noteID] ?? self.note(noteID)
            notes[noteID] = note
            let statistics = try cardStatistics(id)
            let rendered = try renderedCard(id)
            var card = Flashcard(id: .anki(id), deckID: .anki(native["deckId"].int),
                front: rendered["question"]["text"].string, back: rendered["answer"]["text"].string,
                tags: note["tags"].array.map(\.string), isHTML: true, css: rendered["css"].string,
                createdAt: Date(timeIntervalSince1970: statistics["added"].double))
            card.ankiID = id
            card.ankiNoteID = noteID
            card.ankiNoteTypeID = noteTypeID
            card.ankiOriginalDeckID = native["originalDeckId"].isNull ? nil : native["originalDeckId"].int
            card.ankiDeckConfiguration = configuration
            card.noteFields = zip(noteType["fields"].array, note["fields"].array).enumerated().map { index, pair in
                AnkiNoteField(id: index, name: pair.0["name"].string, value: pair.1.string)
            }
            card.questionAudio = rendered["question"]["avTags"].array.map(AnkiAudioTag.init)
            card.answerAudio = rendered["answer"]["avTags"].array.map(AnkiAudioTag.init)
            card.questionPreview = try browserTextLine(AnkiFrontend.stripAudioReferences(card.front))
            card.answerPreview = try browserTextLine(AnkiFrontend.stripAudioReferences(card.back))
            applySchedulingDisplay(native, statistics: statistics, to: &card)
            if let guideKey = metadata["guide"]["notes"].object.first(where: { $0.value.int == noteID })?.key { card.builtInID = guideKey }
            cards.append(card)
            updatedCache[id] = AnkiPresentationCacheEntry(key: key, storedCard: storedCard, card: card)
        }
        presentationCache = updatedCache
        return CollectionSnapshot(decks: decks, cards: cards, settings: settings)
    }

    private func applySchedulingDisplay(_ native: AnkiJSON, statistics: AnkiJSON, to card: inout Flashcard) {
        card.ankiQueue = Int(native["queue"].int)
        switch native["ctype"].int { case 1: card.stage = .learning; case 2: card.stage = .review; case 3: card.stage = .relearning; default: card.stage = .new }
        card.isSuspended = native["queue"].int == -1
        card.due = statistics["dueDate"].isNull ? .distantFuture : Date(timeIntervalSince1970: statistics["dueDate"].double)
        card.interval = native["interval"].double
        card.ease = native["easeFactor"].double / 1000
        card.repetitions = Int(native["reps"].int)
        card.lapses = Int(native["lapses"].int)
        card.lastReviewedAt = statistics["latestReview"].isNull ? nil : Date(timeIntervalSince1970: statistics["latestReview"].double)
    }
}
