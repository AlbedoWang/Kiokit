import SwiftUI
import KiokitCore

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
    func ankiFootnote() -> some View {
        font(.footnote).foregroundStyle(AnkiTheme.muted).fixedSize(horizontal: false, vertical: true)
    }
}
