import SwiftUI
import OpenAnkiCore

struct StatisticsView: View {
    @Environment(CollectionStore.self) private var store
    var isActive = true

    var body: some View {
        AnkiStatisticsWebView(statistics: store.statistics, deckID: store.selectedDeckID, localeIdentifier: store.uiLocale.identifier, isActive: isActive)
            .id(store.backendIdentity)
            .background(AnkiTheme.background)
            .navigationTitle(store.text("学习统计"))
            .navigationBarTitleDisplayMode(.inline)
    }
}
