import Foundation

public struct Deck: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var colorIndex: Int
    public var createdAt: Date
    /// Identifies app-owned starter content; imported and user-created decks omit it.
    public var builtInID: String?

    public init(id: UUID = UUID(), name: String, symbol: String = "rectangle.stack.fill", colorIndex: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }
}

public enum CardStage: String, Codable, CaseIterable, Sendable {
    case new, learning, review, relearning

    public var title: String {
        switch self {
        case .new: "新卡片"
        case .learning: "学习中"
        case .review: "待复习"
        case .relearning: "重新学习"
        }
    }
}

public struct Flashcard: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var deckID: UUID
    public var front: String
    public var back: String
    public var tags: [String]
    public var isHTML: Bool
    public var css: String
    public var mediaFolder: String?
    public var sourceKey: String?
    public var pronunciation: Pronunciation?
    public var builtInID: String?
    public var createdAt: Date
    public var stage: CardStage = .new
    public var due: Date
    public var interval: Double = 0
    public var ease: Double = 2.5
    public var learningStep: Int = 0
    public var repetitions: Int = 0
    public var lapses: Int = 0
    public var isSuspended: Bool = false
    public var lastReviewedAt: Date?

    public init(id: UUID = UUID(), deckID: UUID, front: String, back: String, tags: [String] = [], isHTML: Bool = false, css: String = "", mediaFolder: String? = nil, sourceKey: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.deckID = deckID
        self.front = front
        self.back = back
        self.tags = tags
        self.isHTML = isHTML
        self.css = css
        self.mediaFolder = mediaFolder
        self.sourceKey = sourceKey
        self.createdAt = createdAt
        self.due = createdAt
    }

    public var frontPreview: String { TemplateRenderer.plainText(front) }
    public var backPreview: String { TemplateRenderer.plainText(back) }

    public mutating func restoreScheduling(_ state: SchedulingState) {
        stage = state.stage
        due = state.due
        interval = state.interval
        ease = state.ease
        learningStep = state.learningStep
        repetitions = state.repetitions
        lapses = state.lapses
        lastReviewedAt = state.lastReviewedAt
    }
}

/// Review history stores scheduling only, without duplicating card HTML/media.
public struct SchedulingState: Codable, Sendable {
    public var stage: CardStage
    public var due: Date
    public var interval: Double
    public var ease: Double
    public var learningStep: Int
    public var repetitions: Int
    public var lapses: Int
    public var lastReviewedAt: Date?

    public init(card: Flashcard) {
        stage = card.stage
        due = card.due
        interval = card.interval
        ease = card.ease
        learningStep = card.learningStep
        repetitions = card.repetitions
        lapses = card.lapses
        lastReviewedAt = card.lastReviewedAt
    }
}

public enum ReviewRating: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard, good, easy

    public var title: String {
        switch self {
        case .again: "重来"
        case .hard: "困难"
        case .good: "良好"
        case .easy: "简单"
        }
    }
}

public struct ReviewRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var cardID: UUID
    public var deckID: UUID
    public var date: Date
    public var rating: ReviewRating
    public var duration: TimeInterval
    public var previousState: SchedulingState

    public init(card: Flashcard, rating: ReviewRating, date: Date, duration: TimeInterval) {
        id = UUID()
        cardID = card.id
        deckID = card.deckID
        self.date = date
        self.rating = rating
        self.duration = max(0, min(duration, 3600))
        previousState = SchedulingState(card: card)
    }

    private enum CodingKeys: String, CodingKey {
        case id, cardID, deckID, date, rating, duration, previousState, previousCard
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        cardID = try values.decode(UUID.self, forKey: .cardID)
        deckID = try values.decode(UUID.self, forKey: .deckID)
        date = try values.decode(Date.self, forKey: .date)
        rating = try values.decode(ReviewRating.self, forKey: .rating)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        if let state = try values.decodeIfPresent(SchedulingState.self, forKey: .previousState) {
            previousState = state
        } else {
            previousState = SchedulingState(card: try values.decode(Flashcard.self, forKey: .previousCard))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(cardID, forKey: .cardID)
        try values.encode(deckID, forKey: .deckID)
        try values.encode(date, forKey: .date)
        try values.encode(rating, forKey: .rating)
        try values.encode(duration, forKey: .duration)
        try values.encode(previousState, forKey: .previousState)
    }
}

public struct StudySettings: Codable, Equatable, Sendable {
    public var dailyGoal: Int = 30
    public var newCardsPerDay: Int = 20
    public var appearance: String = "system"
    /// Missing in existing collections/backups means matching the system.
    public var interfaceLanguage: String?
    public var autoPlayAudio: Bool?
    public var builtInContentVersion: Int?
    public init() {}
}

public struct CollectionSnapshot: Codable, Sendable {
    public var version: Int = 1
    public var decks: [Deck]
    public var cards: [Flashcard]
    public var reviews: [ReviewRecord]
    public var settings: StudySettings

    public init(decks: [Deck] = [], cards: [Flashcard] = [], reviews: [ReviewRecord] = [], settings: StudySettings = StudySettings()) {
        self.decks = decks
        self.cards = cards
        self.reviews = reviews
        self.settings = settings
    }

    public func validate() throws {
        guard version == 1 else { throw CollectionError.invalid("此备份版本暂不受支持。") }
        let deckIDs = Set(decks.map(\.id))
        let cardIDs = Set(cards.map(\.id))
        guard deckIDs.count == decks.count, cardIDs.count == cards.count,
              Set(reviews.map(\.id)).count == reviews.count,
              decks.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              cards.allSatisfy({ deckIDs.contains($0.deckID) && $0.interval.isFinite && $0.interval >= 0 && $0.ease.isFinite && $0.ease >= 1.3 && ($0.mediaFolder == nil || Self.safeComponent($0.mediaFolder!)) }),
              reviews.allSatisfy({ cardIDs.contains($0.cardID) && deckIDs.contains($0.deckID) && $0.duration.isFinite && $0.duration >= 0 && $0.previousState.interval.isFinite && $0.previousState.interval >= 0 && $0.previousState.ease.isFinite && $0.previousState.ease >= 1.3 }),
              settings.dailyGoal > 0, settings.newCardsPerDay >= 0 else {
            throw CollectionError.invalid("牌组数据不完整或包含无效记录。")
        }
    }

    public static func safeComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
}

public enum CollectionError: LocalizedError, Sendable {
    case invalid(LocalizedMessage)
    public var errorDescription: String? {
        localizedDescription(locale: InterfaceLanguage.system.locale())
    }

    public func localizedDescription(locale: Locale) -> String {
        switch self { case .invalid(let message): message.localized(locale: locale) }
    }
}

public enum StudyQueue {
    public static func cards(in snapshot: CollectionSnapshot, deckID: UUID? = nil, now: Date = .now, calendar: Calendar = .current) -> [Flashcard] {
        let introduced = Set(snapshot.reviews.filter {
            calendar.isDate($0.date, inSameDayAs: now) && $0.previousState.stage == .new
        }.map(\.cardID)).count
        let newLimit = max(0, snapshot.settings.newCardsPerDay - introduced)
        let available = snapshot.cards.filter { !$0.isSuspended && (deckID == nil || $0.deckID == deckID) }
        let due = available.filter { $0.stage != .new && $0.due <= now }.sorted {
            let lhs = $0.stage == .review ? 1 : 0
            let rhs = $1.stage == .review ? 1 : 0
            return lhs == rhs ? $0.due < $1.due : lhs < rhs
        }
        let newCards = available.filter { $0.stage == .new }.sorted { $0.createdAt < $1.createdAt }
        return due + newCards.prefix(newLimit)
    }
}
