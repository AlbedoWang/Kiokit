// Adapted from ankitects/anki 26.09.3, qt/aqt/filtered_deck.py and its UI file.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import SwiftUI
import OpenAnkiCore

/// Platform controls for the upstream filtered-deck request. Searches, ordering,
/// rebuilding, emptying, preview states, and rescheduling execute Anki code.
struct FilteredDeckSettingsView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    @State private var request: AnkiJSON?
    @State private var name = ""
    @State private var config: [String: AnkiJSON] = [:]
    @State private var terms: [AnkiJSON] = []
    @State private var labels: [(value: Int, title: String)] = []
    @State private var secondFilter = false
    @State private var allowEmpty = false

    // proto/anki/decks.proto::Deck.Filtered.SearchTerm.Order.
    private static let orders = ["OLDEST_REVIEWED_FIRST", "RANDOM", "INTERVALS_ASCENDING", "INTERVALS_DESCENDING", "LAPSES", "ADDED", "DUE", "REVERSE_ADDED", "RETRIEVABILITY_ASCENDING", "RETRIEVABILITY_DESCENDING", "RELATIVE_OVERDUENESS"]

    var body: some View {
        NavigationStack {
            Form {
                if request != nil && !terms.isEmpty {
                    Section {
                        TextField(store.text("牌组名称"), text: $name)
                        filterControls(index: 0)
                        Toggle(store.text("使用第二个筛选条件"), isOn: $secondFilter)
                        if secondFilter { filterControls(index: 1) }
                    } header: { Text(store.text("筛选牌组")).foregroundStyle(AnkiTheme.muted) }
                    Section {
                        Toggle(store.text("根据此牌组中的答案重新安排卡片"), isOn: Binding(
                            get: { config["reschedule"]?.bool ?? false },
                            set: { config["reschedule"] = .bool($0) }
                        )).accessibilityIdentifier("filteredReschedule")
                        Toggle(store.text("允许空牌组"), isOn: $allowEmpty)
                            .accessibilityIdentifier("filteredAllowEmpty")
                        if config["reschedule"]?.bool != true {
                            previewDelay("重来", key: "previewAgainSecs")
                            previewDelay("困难", key: "previewHardSecs")
                            previewDelay("良好", key: "previewGoodSecs")
                        }
                    } footer: { Text(store.text("筛选、排序、预览和重新安排复习均由 Anki 执行。清空牌组会按 Anki 规则将卡片放回原牌组。")).ankiFootnote() }
                    Section {
                        Button(store.text("重建牌组")) { save() }.accessibilityIdentifier("rebuildFilteredDeck")
                        Button(store.text("清空牌组")) { if store.emptyFilteredDeck(deckID) { dismiss() } }
                            .accessibilityIdentifier("emptyFilteredDeck")
                    }
                }
            }
            .ankiForm()
            .navigationTitle(store.text("学习设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.text("取消")) { dismiss() } } }
            .onAppear {
                guard request == nil, let value = store.filteredDeckOptions(for: deckID) else { return }
                request = value
                name = value["name"].string
                config = value["config"].object
                terms = value["config"]["searchTerms"].array
                secondFilter = terms.count > 1
                // Qt uses a 20-card random second filter when one is not stored.
                if terms.count == 1 { terms.append(["search": "", "limit": 20, "order": "RANDOM"]) }
                allowEmpty = value["allowEmpty"].bool
                labels = store.filteredOrderLabels()
            }
            .alert(store.text("操作未完成"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button(store.text("好"), role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    @ViewBuilder private func filterControls(index: Int) -> some View {
        if terms.indices.contains(index) {
            TextField(store.text("搜索条件"), text: Binding(
                get: { terms[index]["search"].string },
                set: { setTerm(index: index, key: "search", value: .string($0)) }
            )).autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier("filteredSearch\(index)")
            AnkiNumberField(title: store.text("卡片数上限"), value: Binding(
                get: { Int(terms[index]["limit"].int) },
                set: { setTerm(index: index, key: "limit", value: .integer(Int64($0))) }
            ), minimum: 1, accessibilityID: "filteredLimit\(index)", maximum: 99999)
            Picker(store.text("显示顺序"), selection: Binding(
                get: { orderValue(terms[index]) },
                set: { setTerm(index: index, key: "order", value: .integer(Int64($0))) }
            )) {
                ForEach(labels, id: \.value) { Text($0.title).tag($0.value) }
            }.accessibilityIdentifier("filteredOrder\(index)")
        }
    }

    private func previewDelay(_ title: String, key: String) -> some View {
        AnkiNumberField(title: store.text(key: title) + " · " + store.text("预览延迟（秒）"), value: Binding(
            get: { Int(config[key]?.int ?? 0) },
            set: { config[key] = .integer(Int64($0)) }
        ), minimum: 0, accessibilityID: key, maximum: 99999)
    }

    private func setTerm(index: Int, key: String, value: AnkiJSON) {
        var term = terms[index].object
        term[key] = value
        terms[index] = .object(term)
    }

    private func orderValue(_ term: AnkiJSON) -> Int {
        let order = term["order"]
        let value = order.string.isEmpty ? Int(order.int) : Self.orders.firstIndex(of: order.string) ?? 0
        // filtered_deck.py::_combo_row selects RANDOM for hidden/invalid orders.
        return labels.contains(where: { $0.value == value }) ? value : 1
    }

    private func save() {
        guard var value = request?.object else { return }
        var updated = config
        updated.removeValue(forKey: "delays")
        updated["searchTerms"] = .array(terms.prefix(secondFilter ? 2 : 1).map { term in
            var fields = term.object
            fields["order"] = .integer(Int64(orderValue(term)))
            return .object(fields)
        })
        value["config"] = .object(updated)
        value["name"] = .string(name)
        value["allowEmpty"] = .bool(allowEmpty)
        if store.saveFilteredDeck(.object(value)) { dismiss() }
    }
}
