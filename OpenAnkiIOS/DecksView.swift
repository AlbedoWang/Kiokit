import SwiftUI
import OpenAnkiCore

struct DecksView: View {
    @Environment(CollectionStore.self) private var store
    @Binding var importing: Bool
    @State private var addingDeck = false
    @State private var studying = false
    @State private var search = ""

    private var filteredDecks: [Deck] {
        store.decks.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("每天一点，记得更久。")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.title2).foregroundStyle(AnkiTheme.tint)
                            .frame(width: 48, height: 48)
                            .background(AnkiTheme.tint.opacity(0.08), in: Circle())
                    }
                    todayCard(now: context.date)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("我的牌组").font(.title3.bold())
                            Text("\(store.decks.count)").font(.caption.bold()).foregroundStyle(.secondary)
                            Spacer()
                            Button { addingDeck = true } label: { Image(systemName: "plus").font(.headline).padding(8) }
                                .accessibilityLabel("新建牌组").accessibilityIdentifier("addDeck")
                        }
                        if filteredDecks.isEmpty {
                            ContentUnavailableView(search.isEmpty ? "创建你的第一个牌组" : "没有找到牌组", systemImage: "rectangle.stack", description: Text(search.isEmpty ? "添加卡片，或从 Anki 导入 .apkg 牌组。" : "试试其他关键词。"))
                            if search.isEmpty {
                                PrimaryButton(title: "导入牌组", symbol: "square.and.arrow.down") { importing = true }
                            }
                        } else {
                            ForEach(filteredDecks) { deck in
                                NavigationLink { DeckDetailView(deckID: deck.id) } label: {
                                    deckRow(deck, now: context.date)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "leaf").foregroundStyle(AnkiTheme.tint)
                        Text("给记忆一点时间。每次回想，都是一次生长。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.bottom, 10)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AnkiTheme.background)
        .navigationTitle("OpenAnki")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索牌组")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("导入牌组").accessibilityIdentifier("importDeck")
            }
        }
        .sheet(isPresented: $addingDeck) { DeckEditorView() }
        .fullScreenCover(isPresented: $studying) { ReviewView(deckID: nil) }
    }

    private func todayCard(now: Date) -> some View {
        let queue = store.queue(now: now)
        let reviewed = store.todayReviews(now: now).count
        let goal = store.settings.dailyGoal
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("今日学习").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(queue.count)").font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("张待学习").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, Double(reviewed) / Double(goal)))
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 3) {
                        Text("\(reviewed)").font(.title3.bold()).monospacedDigit()
                        Text("/ \(goal)").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }.frame(width: 62, height: 62).padding(.top, 5)
                    .accessibilityLabel("今日已评分 \(reviewed) 次，目标 \(goal) 次")
            }
            HStack(spacing: 18) {
                Text("\(queue.filter { $0.stage == .new }.count) 张新卡片")
                Text("\(queue.filter { $0.stage != .new }.count) 张复习卡片")
            }.font(.caption).foregroundStyle(.white.opacity(0.75))
            Button { studying = true } label: {
                HStack {
                    Text(queue.isEmpty ? "本轮学习已完成" : "开始学习").font(.headline)
                    Spacer()
                    Image(systemName: queue.isEmpty ? "checkmark.circle" : "arrow.right")
                }.padding(16).foregroundStyle(AnkiTheme.tint)
                    .background(.white, in: RoundedRectangle(cornerRadius: 15))
            }.disabled(queue.isEmpty).accessibilityIdentifier("startStudy")
        }
        .foregroundStyle(.white).padding(24)
        .background {
            RoundedRectangle(cornerRadius: 28).fill(AnkiTheme.tint.gradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "leaf.fill").font(.system(size: 120)).rotationEffect(.degrees(-30))
                        .foregroundStyle(.white.opacity(0.035)).offset(x: 25, y: 15)
                }.clipShape(RoundedRectangle(cornerRadius: 28))
        }
    }

    private func deckRow(_ deck: Deck, now: Date) -> some View {
        let cards = store.cards(in: deck.id)
        let queue = store.queue(deckID: deck.id, now: now)
        return HStack(spacing: 14) {
            DeckIcon(deck: deck)
            VStack(alignment: .leading, spacing: 8) {
                Text(deck.name).font(.headline).lineLimit(2)
                HStack(spacing: 12) {
                    StatPill(count: queue.filter { $0.stage == .new }.count, title: "新", color: .blue)
                    StatPill(count: queue.filter { $0.stage != .new }.count, title: "复习", color: AnkiTheme.tint)
                    Text("共 \(cards.count) 张").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(18).background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 22))
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
                            Text(deck.name).font(.title.bold()).multilineTextAlignment(.center)
                            Text("\(store.cards(in: deckID).count) 张卡片 · 每一次回想，都算数")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.top, 20)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let queue = store.queue(deckID: deckID, now: context.date)
                            VStack(spacing: 22) {
                                HStack {
                                    metric("新卡片", count: queue.filter { $0.stage == .new }.count, color: .blue)
                                    Spacer()
                                    metric("学习中", count: queue.filter { $0.stage == .learning || $0.stage == .relearning }.count, color: .orange)
                                    Spacer()
                                    metric("待复习", count: queue.filter { $0.stage == .review }.count, color: AnkiTheme.tint)
                                }
                                PrimaryButton(title: queue.isEmpty ? "本轮学习已完成" : "开始学习", symbol: queue.isEmpty ? "checkmark" : "arrow.right") { studying = true }
                                    .disabled(queue.isEmpty)
                                if queue.isEmpty {
                                    Text(nextDueMessage(now: context.date)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                }
                            }.ankiSurface()
                        }
                        NavigationLink { CardBrowserView(deckID: deckID) } label: {
                            HStack {
                                Label("浏览全部卡片", systemImage: "rectangle.on.rectangle")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.font(.subheadline.weight(.medium)).ankiSurface()
                        }.buttonStyle(.plain)
                        Button { addingCard = true } label: { Label("添加卡片", systemImage: "plus.circle") }
                            .font(.headline).padding(10)
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }.background(AnkiTheme.background)
            }
        }
        .navigationTitle("牌组").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑牌组", systemImage: "pencil") { editingDeck = true }
                    Button("添加卡片", systemImage: "plus") { addingCard = true }
                    Button("删除牌组", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingDeck) { if let deck = store.deck(deckID) { DeckEditorView(deck: deck) } }
        .sheet(isPresented: $addingCard) { CardEditorView(deckID: deckID) }
        .fullScreenCover(isPresented: $studying) { ReviewView(deckID: deckID) }
        .confirmationDialog("删除这个牌组及其所有卡片和复习记录？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除牌组", role: .destructive) { store.deleteDeck(deckID); if store.deck(deckID) == nil { dismiss() } }
        }
    }

    private func metric(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text("\(count)").font(.system(.largeTitle, design: .rounded, weight: .semibold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nextDueMessage(now: Date) -> String {
        if let next = store.cards(in: deckID).filter({ !$0.isSuspended && $0.stage != .new && $0.due > now }).map(\.due).min() {
            return "下一次复习：\(next.formatted(date: .abbreviated, time: .shortened))"
        }
        return store.cards(in: deckID).contains(where: { !$0.isSuspended && $0.stage == .new }) ? "今日新卡片额度已用完，可在设置中调整。" : "添加新卡片，或稍后再来复习。"
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
                Section("牌组名称") {
                    TextField("例如：日语单词", text: $name).accessibilityIdentifier("deckName")
                }
                Section("图标") {
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
                Section("颜色") {
                    HStack(spacing: 20) {
                        ForEach(AnkiTheme.palette.indices, id: \.self) { index in
                            Button { color = index } label: {
                                Circle().fill(AnkiTheme.palette[index]).frame(width: 34, height: 34)
                                    .overlay { if color == index { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            }.buttonStyle(.plain).accessibilityLabel("颜色 \(index + 1)")
                        }
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle(original == nil ? "新建牌组" : "编辑牌组").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var deck = original ?? Deck(name: name)
                        deck.name = name; deck.symbol = symbol; deck.colorIndex = color
                        if store.saveDeck(deck) { dismiss() }
                    }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.large])
    }
}
