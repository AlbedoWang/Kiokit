import XCTest
@testable import OpenAnkiCore

final class SchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLearningGraduationAndLapse() {
        let card = Flashcard(deckID: UUID(), front: "Q", back: "A", createdAt: now)
        let learning = Scheduler.answer(card, rating: .good, now: now)
        XCTAssertEqual(learning.stage, .learning)
        XCTAssertEqual(learning.due.timeIntervalSince(now), 600)
        let graduated = Scheduler.answer(learning, rating: .good, now: learning.due)
        XCTAssertEqual(graduated.stage, .review)
        XCTAssertEqual(graduated.interval, 1)
        let lapse = Scheduler.answer(graduated, rating: .again, now: graduated.due)
        XCTAssertEqual(lapse.stage, .relearning)
        XCTAssertEqual(lapse.lapses, 1)
        XCTAssertEqual(lapse.due.timeIntervalSince(graduated.due), 60)
        let recovered = Scheduler.answer(lapse, rating: .good, now: lapse.due)
        XCTAssertEqual(recovered.stage, .review)
        XCTAssertGreaterThanOrEqual(recovered.interval, 1)
        XCTAssertEqual(recovered.repetitions, 4)
    }

    func testRatingIntervalsAndEaseFloor() {
        var card = Flashcard(deckID: UUID(), front: "Q", back: "A", createdAt: now)
        card.stage = .review
        card.interval = 10
        card.ease = 1.3
        let hard = Scheduler.answer(card, rating: .hard, now: now)
        let good = Scheduler.answer(card, rating: .good, now: now)
        let easy = Scheduler.answer(card, rating: .easy, now: now)
        XCTAssertEqual(hard.ease, 1.3)
        XCTAssertLessThan(hard.due, good.due)
        XCTAssertLessThan(good.due, easy.due)
        XCTAssertEqual(Scheduler.intervalLabel(for: card, rating: .again, now: now, locale: InterfaceLanguage.simplifiedChinese.locale()), "1 分钟")
    }

    func testQueueHonorsDailyLimitSuspensionAndDueDate() {
        let deck = Deck(name: "Deck")
        let newCards = (0..<3).map { Flashcard(deckID: deck.id, front: "\($0)", back: "A", createdAt: now.addingTimeInterval(Double($0))) }
        var due = newCards[0]
        due.id = UUID()
        due.stage = .review
        due.due = now
        var suspended = due
        suspended.id = UUID()
        suspended.isSuspended = true
        var future = due
        future.id = UUID()
        future.due = now.addingTimeInterval(3600)
        var settings = StudySettings()
        settings.newCardsPerDay = 2
        let record = ReviewRecord(card: newCards[0], rating: .good, date: now, duration: 3)
        let snapshot = CollectionSnapshot(decks: [deck], cards: [due, suspended, future] + Array(newCards.dropFirst()), reviews: [record], settings: settings)
        let queue = StudyQueue.cards(in: snapshot, now: now)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.first?.id, due.id)
        XCTAssertEqual(queue.last?.id, newCards[1].id)
    }
}
