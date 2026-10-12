import SwiftUI
import OpenAnkiCore

enum AnkiTheme {
    static let tint = Color(red: 0.13, green: 0.40, blue: 0.34)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let palette: [Color] = [tint, Color(red: 0.31, green: 0.40, blue: 0.69), Color(red: 0.67, green: 0.43, blue: 0.22), Color(red: 0.58, green: 0.36, blue: 0.55), Color(red: 0.30, green: 0.52, blue: 0.61)]

    static func deckColor(_ deck: Deck) -> Color { palette[((deck.colorIndex % palette.count) + palette.count) % palette.count] }
    static func ratingColor(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: Color(red: 0.73, green: 0.30, blue: 0.31)
        case .hard: Color(red: 0.69, green: 0.45, blue: 0.20)
        case .good: tint
        case .easy: Color(red: 0.29, green: 0.43, blue: 0.69)
        }
    }
}

struct DeckIcon: View {
    let deck: Deck
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: deck.symbol)
            .font(.system(size: size * 0.40, weight: .medium))
            .foregroundStyle(AnkiTheme.deckColor(deck))
            .frame(width: size, height: size)
            .background(AnkiTheme.deckColor(deck).opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.30))
            .accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let symbol { Image(systemName: symbol) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
        }
        .buttonStyle(.borderedProminent)
        .tint(AnkiTheme.tint)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct StatPill: View {
    let count: Int
    let title: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
            Text(title).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct SurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

extension View {
    func ankiSurface() -> some View { modifier(SurfaceModifier()) }
}
