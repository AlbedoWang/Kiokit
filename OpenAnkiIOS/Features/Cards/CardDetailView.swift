import SwiftUI
import OpenAnkiCore

struct CardDetailView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: UUID
    @State private var editing = false
    @State private var deleting = false
    @State private var resetting = false

    private var card: Flashcard? { store.cards.first { $0.id == cardID } }

    var body: some View {
        Group {
            if let card {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(store.text("正面")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            CardContentView(card: card, answer: false).frame(minHeight: 130)
                        }.ankiSurface()
                        VStack(alignment: .leading, spacing: 16) {
                            Text(store.text("背面")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            CardDetailAnswerView(card: card).frame(minHeight: 160)
                        }.ankiSurface()
                        VStack(spacing: 12) {
                            info(store.text("牌组"), value: store.deck(card.deckID)?.name ?? "")
                            info(store.text("状态"), value: card.isSuspended ? store.text("已暂停") : store.text(key: card.stage.title))
                            if card.stage != .new { info(store.text("下次复习"), value: card.due.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(store.uiLocale))) }
                            info(store.text("复习次数"), value: "\(card.repetitions)")
                            info(store.text("遗忘次数"), value: "\(card.lapses)")
                            if !card.tags.isEmpty { info(store.text("标签"), value: card.tags.joined(separator: " · ")) }
                        }.ankiSurface()
                    }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }.background(AnkiTheme.background)
            }
        }
        .navigationTitle(store.text("卡片详情")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(store.text("编辑卡片"), systemImage: "pencil") { editing = true }
                    Button(card?.isSuspended == true ? store.text("恢复学习") : store.text("暂停学习"), systemImage: card?.isSuspended == true ? "play" : "pause") { store.toggleSuspended(cardID) }
                    Button(store.text("重置学习进度"), systemImage: "arrow.counterclockwise") { resetting = true }
                    Button(store.text("删除笔记"), systemImage: "trash", role: .destructive) { deleting = true }
                        .accessibilityIdentifier("deleteNote")
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityIdentifier("cardActions")
            }
        }
        .sheet(isPresented: $editing) { if let card { CardEditorView(card: card) } }
        .confirmationDialog(store.text("删除此笔记及其全部卡片？"), isPresented: $deleting, titleVisibility: .visible) {
            Button(store.text("删除笔记"), role: .destructive) { store.deleteNote(of: cardID); if card == nil { dismiss() } }
        }
        .confirmationDialog(store.text("将这张卡片重置为新卡片？"), isPresented: $resetting, titleVisibility: .visible) {
            Button(store.text("重置进度"), role: .destructive) { store.resetCard(cardID) }
        }
    }

    private func info(_ name: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 24)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}
