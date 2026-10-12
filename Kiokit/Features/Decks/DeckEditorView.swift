import SwiftUI
import KiokitCore

struct DeckEditorView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var color: Int
    private let original: Deck?
    private let symbols = ["rectangle.stack.fill", "textformat.abc", "swift", "sparkles", "book.closed.fill", "globe.asia.australia.fill", "graduationcap.fill", "brain.head.profile"]

    init(deck: Deck? = nil) {
        original = deck
        _name = State(initialValue: deck?.name ?? "")
        _symbol = State(initialValue: deck?.symbol ?? "rectangle.stack.fill")
        _color = State(initialValue: deck?.colorIndex ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.text("牌组名称")) {
                    TextField(store.text("例如：日语单词"), text: $name).accessibilityIdentifier("deckName")
                }
                Section(store.text("图标")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(symbols, id: \.self) { item in
                            Button { symbol = item } label: {
                                Image(systemName: item).font(.title2).frame(maxWidth: .infinity).frame(height: 48)
                                    .background(symbol == item ? AnkiTheme.tint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).foregroundStyle(AnkiTheme.tint)
                                .accessibilityLabel(item).accessibilityAddTraits(symbol == item ? .isSelected : [])
                        }
                    }.padding(.vertical, 8)
                }
                Section(store.text("颜色")) {
                    HStack(spacing: 20) {
                        ForEach(AnkiTheme.palette.indices, id: \.self) { index in
                            Button { color = index } label: {
                                Circle().fill(AnkiTheme.palette[index]).frame(width: 34, height: 34)
                                    .overlay { if color == index { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            }.buttonStyle(.plain).accessibilityLabel(store.text("颜色 \(index + 1)"))
                        }
                    }.padding(.vertical, 8)
                }
            }
            .ankiForm()
            .navigationTitle(original == nil ? store.text("新建牌组") : store.text("编辑牌组")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("保存")) {
                        var deck = original ?? Deck(name: name)
                        deck.name = name; deck.symbol = symbol; deck.colorIndex = color
                        if store.saveDeck(deck) { dismiss() }
                    }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.large])
    }
}
