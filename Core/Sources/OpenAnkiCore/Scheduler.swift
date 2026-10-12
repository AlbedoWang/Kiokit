import Foundation

/// A local SM-2 style scheduler with explicit learning and relearning steps.
/// Scheduling is independent of Anki's FSRS and imported cards start as new.
public enum Scheduler {
    public static func answer(_ original: Flashcard, rating: ReviewRating, now: Date = .now) -> Flashcard {
        var card = original
        let day: TimeInterval = 86_400
        var delay: TimeInterval

        if card.stage == .review {
            switch rating {
            case .again:
                card.stage = .relearning
                card.learningStep = 0
                card.lapses += 1
                card.ease = max(1.3, card.ease - 0.2)
                delay = 60
            case .hard:
                card.interval = max(card.interval + 1, card.interval * 1.2)
                card.ease = max(1.3, card.ease - 0.15)
                delay = card.interval * day
            case .good:
                card.interval = max(card.interval + 1, card.interval * card.ease)
                delay = card.interval * day
            case .easy:
                card.interval = max(card.interval + 1, card.interval * card.ease * 1.3)
                card.ease += 0.15
                delay = card.interval * day
            }
        } else {
            switch rating {
            case .again:
                if card.stage == .new { card.stage = .learning }
                card.learningStep = 0
                delay = 60
            case .hard:
                if card.stage == .new { card.stage = .learning }
                delay = card.learningStep == 0 ? 360 : 900
            case .good:
                if card.stage == .relearning {
                    card.stage = .review
                    card.interval = max(1, card.interval * 0.5)
                    delay = card.interval * day
                } else if card.learningStep == 0 {
                    card.stage = .learning
                    card.learningStep = 1
                    delay = 600
                } else {
                    card.stage = .review
                    card.interval = 1
                    delay = day
                }
            case .easy:
                card.stage = .review
                card.interval = max(4, card.interval * card.ease)
                delay = card.interval * day
            }
        }
        card.interval = min(card.interval, 36_500)
        delay = min(delay, 36_500 * day)
        card.due = now.addingTimeInterval(delay)
        card.lastReviewedAt = now
        card.repetitions += 1
        return card
    }

    public static func intervalLabel(for card: Flashcard, rating: ReviewRating, now: Date = .now, locale: Locale = InterfaceLanguage.system.locale()) -> String {
        let seconds = answer(card, rating: rating, now: now).due.timeIntervalSince(now)
        if seconds < 3600 { return LocalizedMessage(key: "%@ 分钟", arguments: [String(Int(seconds / 60))]).localized(locale: locale) }
        if seconds < 86_400 { return LocalizedMessage(key: "%@ 小时", arguments: [String(Int(seconds / 3600))]).localized(locale: locale) }
        let days = Int((seconds / 86_400).rounded())
        if days >= 365 { return LocalizedMessage(key: "%@ 年", arguments: [String(format: "%.1f", locale: locale, Double(days) / 365)]).localized(locale: locale) }
        return LocalizedMessage(key: "%@ 天", arguments: [String(days)]).localized(locale: locale)
    }
}
