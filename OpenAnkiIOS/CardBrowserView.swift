import SwiftUI
import OpenAnkiCore

struct CardBrowserView: View {
    @Environment(CollectionStore.self) private var store
    var deckID: UUID? = nil
    @State private var search = ""
    @State private var stage = "all"
    @State private var selectedDeck: UUID?
    @State private var adding = false

    private var filtered: [Flashcard] {
        store.cards.filter { card in
            (deckID == nil || card.deckID == deckID) &&
            (selectedDeck == nil || card.deckID == selectedDeck) &&
            (stage == "all" || (stage == "suspended" ? card.isSuspended : !card.isSuspended && card.stage.rawValue == stage)) &&
            (search.isEmpty || card.frontPreview.localizedCaseInsensitiveContains(search) || card.backPreview.localizedCaseInsensitiveContains(search) || card.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) }))
        }.sorted { $0.createdAt > $1.createdAt }
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
                if filtered.isEmpty {
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
        }
        .sheet(isPresented: $adding) { CardEditorView(deckID: deckID ?? selectedDeck) }
    }
}

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
                            CardContentView(card: card, answer: true).frame(minHeight: 160)
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
                    Button(store.text("删除卡片"), systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { if let card { CardEditorView(card: card) } }
        .confirmationDialog(store.text("删除这张卡片及其复习记录？"), isPresented: $deleting, titleVisibility: .visible) {
            Button(store.text("删除卡片"), role: .destructive) { store.deleteCard(cardID); if card == nil { dismiss() } }
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

struct CardEditorView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var front: String
    @State private var back: String
    @State private var tags: String
    @State private var selectedDeck: UUID?
    @State private var isHTML: Bool
    @State private var reversed = false
    private let original: Flashcard?

    init(card: Flashcard? = nil, deckID: UUID? = nil) {
        original = card
        _front = State(initialValue: card?.front ?? "")
        _back = State(initialValue: card?.back ?? "")
        _tags = State(initialValue: card?.tags.joined(separator: " ") ?? "")
        _selectedDeck = State(initialValue: card?.deckID ?? deckID)
        _isHTML = State(initialValue: card?.isHTML ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(store.text("牌组"), selection: $selectedDeck) {
                        ForEach(store.decks) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section(store.text("正面 · 问题")) {
                    TextEditor(text: $front).frame(minHeight: 120).accessibilityIdentifier("cardFront")
                }
                Section(store.text("背面 · 答案")) {
                    TextEditor(text: $back).frame(minHeight: 150).accessibilityIdentifier("cardBack")
                }
                Section {
                    TextField(store.text("标签，用空格分隔"), text: $tags).autocorrectionDisabled()
                    Toggle(store.text("使用 HTML 格式"), isOn: $isHTML)
                    if original == nil { Toggle(store.text("同时添加反向卡片"), isOn: $reversed) }
                } footer: {
                    if original?.sourceKey != nil {
                        Text(store.text("这里编辑此卡片渲染后的内容；同笔记的其他卡片保持独立。HTML 中的媒体文件名可以继续使用。"))
                    } else { Text(store.text("问题尽量具体，答案尽量简短。标签可以帮助你快速找到卡片。")) }
                }
            }
            .ankiForm()
            .navigationTitle(original == nil ? store.text("添加卡片") : store.text("编辑卡片")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("保存")) {
                        guard let selectedDeck else { return }
                        var card = original ?? Flashcard(deckID: selectedDeck, front: front, back: back)
                        card.deckID = selectedDeck; card.front = front; card.back = back
                        card.tags = Array(Set(tags.split(whereSeparator: \.isWhitespace).map(String.init))).sorted()
                        card.isHTML = isHTML
                        if store.saveCard(card, addReverse: reversed) { dismiss() }
                    }.fontWeight(.semibold).disabled(selectedDeck == nil || front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if selectedDeck == nil { selectedDeck = store.decks.first?.id } }
        }
    }
}
