import SwiftUI
import KiokitCore

struct DeckStudySettingsView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(store.text("预设"), value: store.preset(for: deckID)["name"].string)
                    Button(store.text("为此牌组克隆预设")) { store.clonePreset(for: deckID) }
                        .accessibilityIdentifier("clonePreset")
                    Toggle(store.text("使用预设的新卡片额度"), isOn: Binding(
                        get: { store.deck(deckID)?.newCardsPerDay == nil },
                        set: { store.saveNewCardLimit($0 ? nil : store.newCardLimit(for: deckID), for: deckID) }
                    )).accessibilityIdentifier("useDefaultNewCardLimit")
                    if store.deck(deckID)?.newCardsPerDay == nil {
                        LabeledContent(store.text("每日新卡片"), value: store.text("\(store.newCardLimit(for: deckID)) 张"))
                            .accessibilityIdentifier("inheritedNewCardLimit")
                    } else {
                        AnkiNumberField(title: store.text("每日新卡片"), value: Binding(
                            get: { store.newCardLimit(for: deckID) },
                            set: { if store.deck(deckID)?.newCardsPerDay != nil { store.saveNewCardLimit($0, for: deckID) } }
                        ), minimum: 0, accessibilityID: "deckNewCardLimit")
                    }
                    Toggle(store.text("使用预设的复习额度"), isOn: Binding(
                        get: { store.deck(deckID)?.reviewsPerDay == nil },
                        set: { store.saveReviewLimit($0 ? nil : Int(store.preset(for: deckID)["config"]["reviewsPerDay"].int), for: deckID) }
                    )).accessibilityIdentifier("useDefaultReviewLimit")
                    if let limit = store.deck(deckID)?.reviewsPerDay {
                        AnkiNumberField(title: store.text("每日复习上限"), value: Binding(
                            get: { store.deck(deckID)?.reviewsPerDay ?? limit },
                            set: { if store.deck(deckID)?.reviewsPerDay != nil { store.saveReviewLimit($0, for: deckID) } }
                        ), minimum: 0, accessibilityID: "deckReviewLimit")
                    }
                } header: { Text(store.text("学习节奏")).foregroundStyle(AnkiTheme.muted) } footer: {
                    Text(store.text("每日额度可单独设置。预设选项由所有使用该预设的牌组共享；克隆预设后可独立调整排序。父牌组限制和日切时间沿用 Anki 规则。")).ankiFootnote()
                }
                Section {
                    Toggle("FSRS", isOn: Binding(
                        get: { store.deck(deckID)?.ankiOptions?["fsrs"].bool ?? false },
                        set: { store.saveCollectionOption(.bool($0), key: "fsrs", for: deckID) }
                    )).accessibilityIdentifier("fsrsEnabled")
                    orderPicker("新增卡片顺序", key: "newCardInsertOrder", choices: AnkiOrderChoices.insertion)
                        .accessibilityIdentifier("deckInsertionOrder")
                    orderPicker("新卡片收集顺序", key: "newCardGatherPriority", choices: AnkiOrderChoices.gather)
                        .accessibilityIdentifier("deckGatherOrder")
                    orderPicker("新卡片排序", key: "newCardSortOrder", choices: AnkiOrderChoices.newSort)
                        .accessibilityIdentifier("deckStudyOrder")
                    orderPicker("复习卡片排序", key: "reviewOrder", choices: AnkiOrderChoices.review)
                        .accessibilityIdentifier("deckReviewOrder")
                } header: { Text(store.text("显示顺序")).foregroundStyle(AnkiTheme.muted) } footer: {
                    Text(store.text("这些选项直接使用 Anki 的收集和排序规则。随机算法、学习卡片优先级、复习混排和同笔记卡片处理均由上游后端执行。")).ankiFootnote()
                }
            }
            .ankiForm()
            .navigationTitle(store.text("学习设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.text("完成")) { dismiss() }.accessibilityIdentifier("finishDeckStudySettings") } }
        }
    }

    private func orderPicker(_ title: String, key: String, choices: [AnkiOrderChoice]) -> some View {
        // Protobuf enum value zero is omitted from JSON. The first choice is its
        // upstream value, rather than an application-defined default.
        Picker(store.text(key: title), selection: Binding(
            get: { let value = store.preset(for: deckID)["config"][key].string; return value.isEmpty ? choices[0].value : value },
            set: { store.savePresetValue(.string($0), key: key, for: deckID) }
        )) {
            ForEach(choices) { Text(store.text(key: $0.label)).tag($0.value) }
        }
    }
}
