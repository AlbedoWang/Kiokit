import SwiftUI
import UIKit
import OpenAnkiCore

enum AnkiTheme {
    // Based on the v2 light/dark tokens in the user's saved Claude page.
    static let brand = Color(hex: 0xD97757)
    static let tint = adaptive(light: 0xA64F33, dark: 0xE69B7E)
    static let background = adaptive(light: 0xF9F9F7, dark: 0x151515)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x20201F)
    static let sidebar = adaptive(light: 0xF3F3F0, dark: 0x111111)
    static let subtle = adaptive(light: 0xF0EFEC, dark: 0x292928)
    static let selection = adaptive(light: 0xE7E6E1, dark: 0x333331)
    static let ink = adaptive(light: 0x131313, dark: 0xF9F9F7)
    static let muted = adaptive(light: 0x7B7974, dark: 0xA8A69E)
    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.10)
    })
    static let blue = adaptive(light: 0x586D85, dark: 0x9CB4CF)
    static let olive = adaptive(light: 0x647059, dark: 0xA8B59A)
    static let ochre = adaptive(light: 0x937343, dark: 0xCCAC78)
    static let palette: [Color] = [tint, blue, ochre, adaptive(light: 0x83677F, dark: 0xC0A4B9), olive]

    static func editorial(_ size: CGFloat) -> Font { .custom("Georgia", size: size, relativeTo: .title) }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
    }

    static func deckColor(_ deck: Deck) -> Color { palette[((deck.colorIndex % palette.count) + palette.count) % palette.count] }
    static func ratingColor(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: adaptive(light: 0xA04E45, dark: 0xDF9388)
        case .hard: ochre
        case .good: olive
        case .easy: blue
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

private extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

struct OpenAnkiMark: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                Capsule().fill(AnkiTheme.brand)
                    .frame(width: size * 0.16, height: size)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle().fill(AnkiTheme.brand).frame(width: size * 0.3, height: size * 0.3)
        }.frame(width: size, height: size).accessibilityHidden(true)
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
            .background(AnkiTheme.subtle, in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let symbol { Image(systemName: symbol) }
            }
            .font(.system(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(AnkiTheme.background)
            .background(AnkiTheme.ink, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
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
            Text(title).foregroundStyle(AnkiTheme.muted)
        }
        .font(.caption)
    }
}

struct SurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
    }
}

struct OutlineAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.caption, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 10)
                .foregroundStyle(AnkiTheme.ink)
                .background(AnkiTheme.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
        }.buttonStyle(.plain)
    }
}

struct FormTheme: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(AnkiTheme.background)
            .foregroundStyle(AnkiTheme.ink)
            .toolbarBackground(AnkiTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct AnkiSearchField: View {
    @Environment(CollectionStore.self) private var store
    @Binding var text: String
    let placeholder: String
    let accessibilityID: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(AnkiTheme.muted)
            TextField(placeholder, text: $text)
                .font(.system(size: 15)).foregroundStyle(AnkiTheme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .submitLabel(.search).focused($focused)
                .onSubmit { focused = false }
                .accessibilityIdentifier(accessibilityID)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(AnkiTheme.muted)
                }.buttonStyle(.plain).accessibilityLabel(store.text("清空搜索"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
    }
}

extension View {
    func ankiSurface() -> some View { modifier(SurfaceModifier()) }
    func ankiForm() -> some View { modifier(FormTheme()) }
}
