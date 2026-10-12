import SwiftUI
import OpenAnkiCore

struct ReviewView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID?
    @State private var currentID: UUID?
    @State private var revealed = false
    @State private var startedAt = Date.now
    @State private var reviewed = 0
    @State private var initialCount = 0
    @State private var editing = false
    @State private var lastAnsweredID: UUID?

    private var current: Flashcard? { store.cards.first { $0.id == currentID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let card = current {
                    VStack(spacing: 14) {
                        HStack {
                            Text(store.deck(card.deckID)?.name ?? "").lineLimit(1)
                            Spacer()
                            Text(store.text("已完成 \(reviewed) 次")).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: min(Double(reviewed), Double(max(1, initialCount))), total: Double(max(1, initialCount)))
                            .tint(AnkiTheme.tint)
                    }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
                    VStack(spacing: 12) {
                        HStack {
                            Text(revealed ? store.text("答案") : store.text("回想一下"))
                                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                            Spacer()
                            Text(store.text(key: card.stage.title)).font(.caption2.weight(.medium))
                                .foregroundStyle(AnkiTheme.tint).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(AnkiTheme.tint.opacity(0.08), in: Capsule())
                        }
                        CardContentView(card: card, answer: revealed, autoPlayAudio: true)
                            .id("\(card.id)-\(revealed)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(24)
                    .background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(AnkiTheme.border, lineWidth: 0.75) }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    VStack(spacing: 14) {
                        Text(revealed ? store.text("根据回忆的难易程度评分") : store.text("先在心里回忆答案，再翻开卡片"))
                            .font(.caption).foregroundStyle(.secondary)
                        if revealed {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { ratingButtons(card) }
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { ratingButtons(card) }
                            }
                        } else {
                            PrimaryButton(title: store.text("显示答案"), symbol: "arrow.turn.down.right") { revealed = true }
                                .keyboardShortcut(.space, modifiers: [])
                                .accessibilityIdentifier("showAnswer")
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 18)
                } else {
                    completionView
                }
            }
            .frame(maxWidth: 900).frame(maxWidth: .infinity)
            .background(AnkiTheme.background)
            .navigationTitle(deckID.flatMap { store.deck($0)?.name } ?? store.text("专注学习"))
            .navigationBarTitleDisplayMode(.inline)
            .foregroundStyle(AnkiTheme.ink)
            .toolbarBackground(AnkiTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(store.text("完成")) { dismiss() }.accessibilityIdentifier("finishStudy") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if store.undo() {
                            currentID = lastAnsweredID
                            lastAnsweredID = nil
                            reviewed = max(0, reviewed - 1)
                            revealed = false
                            startedAt = .now
                        }
                    } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!store.canUndo || lastAnsweredID == nil)
                    .accessibilityLabel(store.text("撤销上次评分")).accessibilityIdentifier("undoReview")
                    if current != nil {
                        Menu {
                            Button(store.text("编辑卡片"), systemImage: "pencil") { editing = true }
                            Button(store.text("暂停此卡片"), systemImage: "pause") {
                                if let currentID { store.toggleSuspended(currentID) }
                                advance()
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .onAppear {
                if currentID == nil && reviewed == 0 {
                    initialCount = store.queue(deckID: deckID).count
                    advance()
                }
            }
            .sheet(isPresented: $editing) { if let current { CardEditorView(card: current) } }
            .alert(store.text("操作未完成"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button(store.text("好"), role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private func ratingButtons(_ card: Flashcard) -> some View {
        ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
            Button {
                if store.answer(card, rating: rating, duration: Date.now.timeIntervalSince(startedAt)) {
                    lastAnsweredID = card.id
                    reviewed += 1
                    advance()
                }
            } label: {
                VStack(spacing: 7) {
                    Text(Scheduler.intervalLabel(for: card, rating: rating, locale: store.uiLocale)).font(.caption2).lineLimit(1)
                    Text(store.text(key: rating.title)).font(.subheadline.weight(.medium))
                }
                .frame(minWidth: 65, maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(AnkiTheme.ratingColor(rating))
                .background(AnkiTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AnkiTheme.ratingColor(rating).opacity(0.3), lineWidth: 0.75) }
            }.buttonStyle(.plain)
                .accessibilityIdentifier("rating\(rating.rawValue)")
                .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
        }
    }

    private var completionView: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 76, weight: .light)).foregroundStyle(AnkiTheme.tint)
                    .padding(28).background(AnkiTheme.tint.opacity(0.07), in: Circle())
                Text(store.text("这一轮，完成了。"))
                    .font(AnkiTheme.editorial(30))
                Text(reviewed > 0 ? store.text("你完成了 \(reviewed) 次回忆练习。\n让记忆沉淀一下，稍后再见。") : store.text("目前没有到期的卡片。\n添加新卡片，或稍后再来复习。"))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
                if let next = store.cards.filter({ !$0.isSuspended && $0.stage != .new && $0.due > context.date && (deckID == nil || $0.deckID == deckID) }).map(\.due).min() {
                    Label(store.text("下次复习 \(next.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(store.uiLocale)))"), systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !store.queue(deckID: deckID, now: context.date).isEmpty {
                    PrimaryButton(title: store.text("继续到期的卡片"), symbol: "arrow.right") { advance() }
                }
                PrimaryButton(title: store.text("返回牌组"), symbol: "arrow.left") { dismiss() }
            }.padding(32)
        }
    }

    private func advance() {
        currentID = store.queue(deckID: deckID).first?.id
        revealed = false
        startedAt = .now
    }
}
