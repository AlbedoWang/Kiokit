import SwiftUI
import KiokitCore

/// Only the browser detail's Back panel omits FrontSide; the collection,
/// templates, audio options, and reviewer presentation remain unchanged.
struct CardDetailAnswerView: View {
    @Environment(CollectionStore.self) private var store
    let card: Flashcard
    @State private var display: Flashcard?

    var body: some View {
        Group {
            if let display {
                CardContentView(card: display, answer: true, showQuestionAboveAnswer: false)
                    .id(display.back)
            }
            else { ProgressView() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardDetailBack")
        .task(id: card) {
            do { display = try store.detailsAnswerCard(card) }
            catch { store.errorMessage = store.errorText(error) }
        }
    }
}
