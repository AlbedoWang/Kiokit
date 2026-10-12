import SwiftUI
import OpenAnkiCore

struct CardBrowserView: View {
    @Environment(CollectionStore.self) private var store
    var deckID: UUID? = nil
    var isActive = true
    @State private var search = ""
    @State private var stage = "all"
    @State private var selectedDeck: UUID?
    @State private var adding = false
    @State private var filtered: [Flashcard] = []
    @State private var searchError: String?
    @State private var searching = true

    private struct SearchRequest: Equatable {
        let text: String
        let deckID: UUID?
        let stage: String
        let revision: Int
        let active: Bool
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Menu {
                        Picker(store.text("状态"), selection: $stage) {
                            Text(store.text("全部状态")).tag("all")
                            ForEach(CardStage.allCases, id: \.rawValue) { Text(store.text(key: $0.title)).tag($0.rawValue) }
                            Text(store.text("已暂停")).tag("suspended")
                        }
                    } label: {
                        Label(stage == "all" ? store.text("全部状态") : stage == "suspended" ? store.text("已暂停") : store.text(key: CardStage(rawValue: stage)?.title ?? ""), systemImage: "line.3.horizontal.decrease")
                    }
                    if deckID == nil {
                        Menu {
                            Picker(store.text("牌组"), selection: $selectedDeck) {
                                Text(store.text("全部牌组")).tag(nil as UUID?)
                                ForEach(store.decks) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } label: { Label(selectedDeck.flatMap { store.deck($0)?.name } ?? store.text("全部牌组"), systemImage: "rectangle.stack") }
                    }
                    Spacer(minLength: 0)
                }.font(.caption.weight(.medium)).padding(.vertical, 4)
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            Section {
                if let searchError {
                    ContentUnavailableView(store.text("操作未完成"), systemImage: "magnifyingglass", description: Text(searchError))
                        .listRowBackground(Color.clear)
                } else if searching && filtered.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                } else if filtered.isEmpty {
                    ContentUnavailableView(store.text("没有卡片"), systemImage: "rectangle.on.rectangle", description: Text(search.isEmpty ? store.text("点击右上角添加，或导入一个牌组。") : store.text("尝试其他关键词或筛选条件。")))
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { card in
                    NavigationLink { CardDetailView(cardID: card.id) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(card.frontPreview.isEmpty ? store.text("[媒体卡片]") : card.frontPreview).font(.body.weight(.medium)).lineLimit(2)
                            Text(card.backPreview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 8) {
                                Text(store.deck(card.deckID)?.name ?? "").lineLimit(1)
                                Spacer(minLength: 8)
                                Text(card.isSuspended ? store.text("已暂停") : store.text(key: card.stage.title))
                                    .foregroundStyle(card.isSuspended ? AnkiTheme.muted : card.stage == .new ? AnkiTheme.blue : AnkiTheme.tint)
                            }.font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { store.toggleSuspended(card.id) } label: { Label(card.isSuspended ? store.text("恢复") : store.text("暂停"), systemImage: card.isSuspended ? "play" : "pause") }.tint(.orange)
                    }
                    .listRowBackground(AnkiTheme.surface)
                }
            } header: {
                Text(store.text("\(filtered.count) 张卡片"))
            }
        }
        .ankiForm()
        .navigationTitle(deckID.flatMap { store.deck($0)?.name } ?? store.text("卡片"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            AnkiSearchField(text: $search, placeholder: store.text("搜索内容或标签"), accessibilityID: "cardSearch")
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
                .background(AnkiTheme.background)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .disabled(store.decks.isEmpty).accessibilityLabel(store.text("添加卡片")).accessibilityIdentifier("addCard")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!store.canUndo).accessibilityLabel(store.undoTitle).accessibilityIdentifier("undoBrowser")
            }
        }
        .sheet(isPresented: $adding) { CardEditorView(deckID: deckID ?? selectedDeck) }
        .onAppear { applyRequestedSearch() }
        .onChange(of: store.requestedBrowserSearch) { _, _ in applyRequestedSearch() }
        .task(id: SearchRequest(text: search, deckID: deckID ?? selectedDeck, stage: stage, revision: store.presentationRevision, active: isActive && !store.isReviewing)) {
            guard isActive, !store.isReviewing else { return }
            searching = true
            if !search.isEmpty {
                do { try await Task.sleep(for: .milliseconds(120)) }
                catch { return }
            } else { await Task.yield() }
            guard !Task.isCancelled else { return }
            do {
                filtered = try store.searchCards(search, deckID: deckID ?? selectedDeck, stage: stage)
                searchError = nil
            } catch { filtered = []; searchError = store.errorText(error) }
            searching = false
        }
    }

    private func applyRequestedSearch() {
        guard deckID == nil, let query = store.requestedBrowserSearch else { return }
        search = query
        stage = "all"
        selectedDeck = nil
        store.requestedBrowserSearch = nil
    }
}
