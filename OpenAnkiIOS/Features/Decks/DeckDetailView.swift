import SwiftUI
import OpenAnkiCore

struct DeckDetailView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    @State private var editingDeck = false
    @State private var editingStudySettings = false
    @State private var addingCard = false
    @State private var studying = false
    @State private var deleting = false

    var body: some View {
        Group {
            if let deck = store.deck(deckID) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 14) {
                            DeckIcon(deck: deck, size: 80)
                            Text(deck.name).font(AnkiTheme.editorial(30)).multilineTextAlignment(.center)
                            Text(store.text("\(store.cardCount(deckID: deckID)) 张卡片 · 每一次回想，都算数"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.top, 20)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let queue = store.counts(deckID: deckID)
                            VStack(spacing: 22) {
                                HStack {
                                    metric(store.text("新卡片"), count: queue.new, color: AnkiTheme.blue, identifier: "deckNewCount")
                                    Spacer()
                                    metric(store.text("学习中"), count: queue.learning, color: AnkiTheme.ochre)
                                    Spacer()
                                    metric(store.text("待复习"), count: queue.review, color: AnkiTheme.tint)
                                }
                                PrimaryButton(title: queue.isEmpty ? store.text("本轮学习已完成") : store.text("开始学习"), symbol: queue.isEmpty ? "checkmark" : "arrow.right") { studying = true }
                                    .disabled(queue.isEmpty)
                                    .accessibilityIdentifier("deckStartStudy")
                                if queue.isEmpty {
                                    Text(nextDueMessage(now: context.date)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                }
                            }.ankiSurface()
                        }
                        Button { editingStudySettings = true } label: {
                            HStack {
                                Label(store.text(key: deck.ankiFilteredConfiguration == nil ? "每日新卡片" : "筛选牌组"), systemImage: "slider.horizontal.3")
                                Spacer()
                                Text(deck.ankiFilteredConfiguration == nil ? (deck.newCardsPerDay == nil ? store.text("默认 · \(store.newCardLimit(for: deckID)) 张") : store.text("\(store.newCardLimit(for: deckID)) 张")) : store.text("学习设置"))
                                    .foregroundStyle(AnkiTheme.muted)
                                    .accessibilityIdentifier("deckNewCardLimitSummary")
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AnkiTheme.muted)
                            }.font(.subheadline).ankiSurface()
                        }.buttonStyle(.plain).accessibilityIdentifier("deckStudySettings")
                        NavigationLink { CardBrowserView(deckID: deckID) } label: {
                            HStack {
                                Label(store.text("浏览全部卡片"), systemImage: "rectangle.on.rectangle")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.font(.subheadline.weight(.medium)).ankiSurface()
                        }.buttonStyle(.plain)
                        Button { addingCard = true } label: { Label(store.text("添加卡片"), systemImage: "plus.circle") }
                            .font(.headline).padding(10)
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }.background(AnkiTheme.background)
            }
        }
        .navigationTitle(store.text("牌组")).navigationBarTitleDisplayMode(.inline)
        .onAppear { store.selectDeck(deckID) }
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(store.text("编辑牌组"), systemImage: "pencil") { editingDeck = true }
                    Button(store.text("学习设置"), systemImage: "slider.horizontal.3") { editingStudySettings = true }
                    Button(store.text("添加卡片"), systemImage: "plus") { addingCard = true }
                    Button(store.text("删除牌组"), systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingDeck) { if let deck = store.deck(deckID) { DeckEditorView(deck: deck) } }
        .sheet(isPresented: $editingStudySettings) {
            if store.deck(deckID)?.ankiFilteredConfiguration != nil { FilteredDeckSettingsView(deckID: deckID) }
            else { DeckStudySettingsView(deckID: deckID) }
        }
        .sheet(isPresented: $addingCard) { CardEditorView(deckID: deckID) }
        .fullScreenCover(isPresented: $studying, onDismiss: { store.endReview() }) { ReviewView(deckID: deckID) }
        .confirmationDialog(store.text("删除这个牌组及其所有卡片和复习记录？"), isPresented: $deleting, titleVisibility: .visible) {
            Button(store.text("删除牌组"), role: .destructive) { store.deleteDeck(deckID); if store.deck(deckID) == nil { dismiss() } }
        }
    }

    private func metric(_ title: String, count: Int, color: Color, identifier: String = "") -> some View {
        VStack(spacing: 8) {
            Text("\(count)").font(AnkiTheme.editorial(34)).foregroundStyle(color).accessibilityIdentifier(identifier)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nextDueMessage(now: Date) -> String {
        if let next = store.nextLearningDate {
            return store.text("下一次复习：\(next.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(store.uiLocale)))")
        }
        return store.text("添加新卡片，或稍后再来复习。")
    }
}
