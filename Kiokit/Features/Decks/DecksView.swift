import SwiftUI
import KiokitCore

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
                            KiokitMark(size: 30)
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
        .fullScreenCover(isPresented: $studying, onDismiss: { store.endReview() }) { ReviewView(deckID: nil) }
    }

    private var header: some View {
        HStack {
            Text("Kiokit").font(AnkiTheme.editorial(23))
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
        let queue = store.counts()
        let reviewed = Int(store.statistics["today"]["answerCount"].int)
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.text("今日学习")).font(.system(size: 13)).foregroundStyle(AnkiTheme.muted)
                Spacer()
                Text(store.text("\(reviewed) 次评分"))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(AnkiTheme.muted)
                    .accessibilityLabel(store.studiedTodayMessage)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(queue.total)").font(AnkiTheme.editorial(40)).monospacedDigit()
                Text(queue.isEmpty ? store.text("本轮已完成") : store.text("张卡片，等你回想。"))
                    .font(.system(size: 16)).foregroundStyle(AnkiTheme.muted)
            }
            Text(store.studiedTodayMessage).font(.caption).foregroundStyle(AnkiTheme.muted)
            HStack(spacing: 14) {
                Text(store.text("\(queue.new) 张新卡片"))
                Text(store.text("\(queue.learning + queue.review) 张复习"))
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
        let cardCount = store.cardCount(deckID: deck.id)
        let queue = store.counts(deckID: deck.id)
        return HStack(spacing: 12) {
            DeckIcon(deck: deck, size: 36)
            VStack(alignment: .leading, spacing: 7) {
                Text(deck.name).font(.system(size: 15, weight: .medium)).foregroundStyle(AnkiTheme.ink).lineLimit(2)
                HStack(spacing: 10) {
                    Text(store.text("\(queue.new) 新"))
                    Text(store.text("\(queue.learning + queue.review) 复习"))
                    Text(store.text("共 \(cardCount) 张"))
                }.font(.system(size: 11)).monospacedDigit().foregroundStyle(AnkiTheme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(AnkiTheme.muted)
        }.padding(.horizontal, 16).padding(.vertical, 17).contentShape(Rectangle())
    }
}
