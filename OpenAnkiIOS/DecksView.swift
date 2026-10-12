import SwiftUI
import OpenAnkiCore

struct DecksView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var importing: Bool
    @State private var addingDeck = false
    @State private var addingCard = false
    @State private var studying = false
    @State private var searching = false
    @State private var search = ""

    private var filteredDecks: [Deck] {
        store.decks.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 13) {
                        HStack(spacing: 12) {
                            OpenAnkiMark(size: 30)
                            Text(store.text("今天想记住什么？"))
                                .font(AnkiTheme.editorial(sizeClass == .regular ? 36 : 29))
                                .foregroundStyle(AnkiTheme.ink)
                        }
                        Text(store.text("每天一点，让知识留得更久。"))
                            .font(.system(size: 14)).foregroundStyle(AnkiTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, sizeClass == .regular ? 66 : 28)
                    todayCard(now: context.date)
                    HStack(spacing: 8) {
                        OutlineAction(title: store.text("导入牌组"), symbol: "square.and.arrow.down") { importing = true }
                        OutlineAction(title: store.text("新建牌组"), symbol: "plus") { addingDeck = true }
                        OutlineAction(title: store.text("添加卡片"), symbol: "square.and.pencil") { addingCard = true }
                            .disabled(store.decks.isEmpty)
                    }.padding(.top, -12)
                    VStack(alignment: .leading, spacing: 15) {
                        HStack(spacing: 8) {
                            Text(store.text("你的牌组")).font(AnkiTheme.editorial(21))
                            Text("\(store.decks.count)").font(.caption).foregroundStyle(AnkiTheme.muted)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    searching.toggle()
                                    if !searching { search = "" }
                                }
                            } label: { Image(systemName: "magnifyingglass").font(.system(size: 15)).frame(width: 34, height: 34) }
                                .accessibilityLabel(store.text("搜索牌组"))
                            Button { addingDeck = true } label: { Image(systemName: "plus").font(.system(size: 17)).frame(width: 34, height: 34) }
                                .accessibilityLabel(store.text("新建牌组")).accessibilityIdentifier("addDeck")
                        }.foregroundStyle(AnkiTheme.ink)
                        if searching {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").foregroundStyle(AnkiTheme.muted)
                                TextField(store.text("搜索牌组"), text: $search).font(.subheadline)
                                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                            }.padding(13).background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
                        }
                        if filteredDecks.isEmpty {
                            ContentUnavailableView(search.isEmpty ? store.text("从第一个牌组开始") : store.text("没有找到牌组"), systemImage: "rectangle.stack", description: Text(search.isEmpty ? store.text("添加卡片，或导入已有的 Anki 牌组。") : store.text("试试其他关键词。")))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(filteredDecks.enumerated()), id: \.element.id) { index, deck in
                                    NavigationLink { DeckDetailView(deckID: deck.id) } label: {
                                        deckRow(deck, now: context.date)
                                    }.buttonStyle(.plain)
                                    if index < filteredDecks.count - 1 {
                                        Rectangle().fill(AnkiTheme.border).frame(height: 0.5).padding(.leading, 64)
                                    }
                                }
                            }
                            .background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
                        }
                    }.padding(.top, 4)
                    Text(store.text("学一点，记久一点。"))
                        .font(.system(size: 12)).foregroundStyle(AnkiTheme.muted).padding(.bottom, 16)
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }
        .background(AnkiTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sheet(isPresented: $addingDeck) { DeckEditorView() }
        .sheet(isPresented: $addingCard) { CardEditorView() }
        .fullScreenCover(isPresented: $studying) { ReviewView(deckID: nil) }
    }

    private var header: some View {
        HStack {
            Text("OpenAnki").font(AnkiTheme.editorial(23))
            Spacer()
            Text(store.text("离线学习")).font(.system(size: 11)).foregroundStyle(AnkiTheme.muted)
            Button { importing = true } label: {
                Image(systemName: "square.and.arrow.down").font(.system(size: 17)).frame(width: 38, height: 38)
            }.buttonStyle(.plain).foregroundStyle(AnkiTheme.ink)
                .accessibilityLabel(store.text("导入牌组")).accessibilityIdentifier("importDeck")
        }
        .padding(.horizontal, 24).padding(.vertical, 6)
        .background(AnkiTheme.background)
    }

    private func todayCard(now: Date) -> some View {
        let queue = store.queue(now: now)
        let reviewed = store.todayReviews(now: now).count
        let goal = store.settings.dailyGoal
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.text("今日学习")).font(.system(size: 13)).foregroundStyle(AnkiTheme.muted)
                Spacer()
                Text(store.text("\(reviewed) / \(goal) 次"))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(AnkiTheme.muted)
                    .accessibilityLabel(store.text("今日已评分 \(reviewed) 次，目标 \(goal) 次"))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(queue.count)").font(AnkiTheme.editorial(40)).monospacedDigit()
                Text(queue.isEmpty ? store.text("本轮已完成") : store.text("张卡片，等你回想。"))
                    .font(.system(size: 16)).foregroundStyle(AnkiTheme.muted)
            }
            ProgressView(value: min(Double(reviewed), Double(goal)), total: Double(goal))
                .tint(AnkiTheme.brand)
            HStack(spacing: 14) {
                Text(store.text("\(queue.filter { $0.stage == .new }.count) 张新卡片"))
                Text(store.text("\(queue.filter { $0.stage != .new }.count) 张复习"))
            }.font(.system(size: 12)).foregroundStyle(AnkiTheme.muted)
            Rectangle().fill(AnkiTheme.border).frame(height: 0.5)
            HStack {
                Label(store.text("慢慢来，记得更牢。"), systemImage: "book")
                    .font(.system(size: 11)).foregroundStyle(AnkiTheme.muted)
                Spacer(minLength: 4)
                Button { studying = true } label: {
                    HStack(spacing: 8) {
                        Text(queue.isEmpty ? store.text("已完成") : store.text("开始学习"))
                        Image(systemName: queue.isEmpty ? "checkmark" : "arrow.right")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.12, green: 0.08, blue: 0.06))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(AnkiTheme.brand.opacity(queue.isEmpty ? 0.3 : 1), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(queue.isEmpty).accessibilityIdentifier("startStudy")
            }
        }
        .padding(22).foregroundStyle(AnkiTheme.ink)
        .background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.025), radius: 10, x: 0, y: 3)
    }

    private func deckRow(_ deck: Deck, now: Date) -> some View {
        let cards = store.cards(in: deck.id)
        let queue = store.queue(deckID: deck.id, now: now)
        return HStack(spacing: 12) {
            DeckIcon(deck: deck, size: 36)
            VStack(alignment: .leading, spacing: 7) {
                Text(deck.name).font(.system(size: 15, weight: .medium)).foregroundStyle(AnkiTheme.ink).lineLimit(2)
                HStack(spacing: 10) {
                    Text(store.text("\(queue.filter { $0.stage == .new }.count) 新"))
                    Text(store.text("\(queue.filter { $0.stage != .new }.count) 复习"))
                    Text(store.text("共 \(cards.count) 张"))
                }.font(.system(size: 11)).monospacedDigit().foregroundStyle(AnkiTheme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(AnkiTheme.muted)
        }.padding(.horizontal, 16).padding(.vertical, 17).contentShape(Rectangle())
    }
}

struct DeckDetailView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    @State private var editingDeck = false
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
                            Text(store.text("\(store.cards(in: deckID).count) 张卡片 · 每一次回想，都算数"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.top, 20)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let queue = store.queue(deckID: deckID, now: context.date)
                            VStack(spacing: 22) {
                                HStack {
                                    metric(store.text("新卡片"), count: queue.filter { $0.stage == .new }.count, color: AnkiTheme.blue)
                                    Spacer()
                                    metric(store.text("学习中"), count: queue.filter { $0.stage == .learning || $0.stage == .relearning }.count, color: AnkiTheme.ochre)
                                    Spacer()
                                    metric(store.text("待复习"), count: queue.filter { $0.stage == .review }.count, color: AnkiTheme.tint)
                                }
                                PrimaryButton(title: queue.isEmpty ? store.text("本轮学习已完成") : store.text("开始学习"), symbol: queue.isEmpty ? "checkmark" : "arrow.right") { studying = true }
                                    .disabled(queue.isEmpty)
                                    .accessibilityIdentifier("deckStartStudy")
                                if queue.isEmpty {
                                    Text(nextDueMessage(now: context.date)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                }
                            }.ankiSurface()
                        }
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
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(store.text("编辑牌组"), systemImage: "pencil") { editingDeck = true }
                    Button(store.text("添加卡片"), systemImage: "plus") { addingCard = true }
                    Button(store.text("删除牌组"), systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingDeck) { if let deck = store.deck(deckID) { DeckEditorView(deck: deck) } }
        .sheet(isPresented: $addingCard) { CardEditorView(deckID: deckID) }
        .fullScreenCover(isPresented: $studying) { ReviewView(deckID: deckID) }
        .confirmationDialog(store.text("删除这个牌组及其所有卡片和复习记录？"), isPresented: $deleting, titleVisibility: .visible) {
            Button(store.text("删除牌组"), role: .destructive) { store.deleteDeck(deckID); if store.deck(deckID) == nil { dismiss() } }
        }
    }

    private func metric(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text("\(count)").font(AnkiTheme.editorial(34)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nextDueMessage(now: Date) -> String {
        if let next = store.cards(in: deckID).filter({ !$0.isSuspended && $0.stage != .new && $0.due > now }).map(\.due).min() {
            return store.text("下一次复习：\(next.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(store.uiLocale)))")
        }
        return store.cards(in: deckID).contains(where: { !$0.isSuspended && $0.stage == .new }) ? store.text("今日新卡片额度已用完，可在设置中调整。") : store.text("添加新卡片，或稍后再来复习。")
    }
}

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
