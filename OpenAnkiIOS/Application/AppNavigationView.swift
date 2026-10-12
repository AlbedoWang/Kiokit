import SwiftUI
import OpenAnkiCore

private enum AppSection: String, CaseIterable, Identifiable {
    case decks, cards, statistics, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .decks: "牌组"
        case .cards: "卡片"
        case .statistics: "统计"
        case .settings: "设置"
        }
    }
    var symbol: String {
        switch self {
        case .decks: "rectangle.stack"
        case .cards: "rectangle.on.rectangle"
        case .statistics: "chart.bar"
        case .settings: "slider.horizontal.3"
        }
    }
    var accessibilityID: String { "tab" + rawValue.capitalized }
}

struct AppNavigationView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var importing: Bool
    @State private var selection: AppSection = .decks
    @State private var deckPath: [UUID] = []
    @State private var sidebarExpanded = false
    @State private var visited: Set<AppSection> = [.decks]

    var body: some View {
        HStack(spacing: 0) {
            if sizeClass == .regular { sidebar }
            pages.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AnkiTheme.background)
        .foregroundStyle(AnkiTheme.ink)
        .onChange(of: store.requestedBrowserSearch) { _, query in
            if query != nil { selection = .cards }
        }
        .onChange(of: selection) { previous, current in
            visited.insert(previous)
            visited.insert(current)
        }
    }

    private var pages: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Group {
                    if section != selection && !visited.contains(section) {
                        Color.clear
                    } else if section == .decks {
                        NavigationStack(path: $deckPath) {
                            DecksView(importing: $importing)
                                .navigationDestination(for: UUID.self) { DeckDetailView(deckID: $0) }
                        }
                    } else {
                        NavigationStack {
                            switch section {
                            case .cards: CardBrowserView(isActive: section == selection)
                            case .statistics: StatisticsView(isActive: section == selection)
                            case .settings: SettingsView(importing: $importing)
                            case .decks: EmptyView()
                            }
                        }
                    }
                }
                .toolbarBackground(AnkiTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar(sizeClass == .regular ? .hidden : .visible, for: .tabBar)
                .tabItem {
                    Label(store.text(key: section.title), systemImage: section.symbol)
                        .accessibilityIdentifier(section.accessibilityID)
                }
                .tag(section)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: sidebarExpanded ? .leading : .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    OpenAnkiMark(size: 23)
                    if sidebarExpanded { Text("OpenAnki").font(AnkiTheme.editorial(24)) }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { sidebarExpanded.toggle() }
                } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 17)).frame(width: 26, height: 30)
                        .foregroundStyle(AnkiTheme.muted)
                }.buttonStyle(.plain)
                    .accessibilityLabel(sidebarExpanded ? store.text("收起侧栏") : store.text("展开侧栏"))
                    .accessibilityIdentifier("toggleSidebar")
            }.padding(.horizontal, sidebarExpanded ? 10 : 0).padding(.top, 12)
            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    Button { selection = section } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.symbol).font(.system(size: 17))
                            if sidebarExpanded {
                                Text(store.text(key: section.title)).font(.system(size: 15, weight: selection == section ? .medium : .regular))
                                Spacer()
                            }
                        }
                        .padding(12).foregroundStyle(AnkiTheme.ink)
                        .background(selection == section ? AnkiTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityLabel(store.text(key: section.title)).accessibilityIdentifier(section.accessibilityID)
                }
            }
            if sidebarExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.text("你的牌组")).font(.caption).foregroundStyle(AnkiTheme.muted).padding(.horizontal, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(store.decks) { deck in
                                Button {
                                    selection = .decks
                                    deckPath = [deck.id]
                                } label: {
                                    Text(deck.name).font(.system(size: 13)).lineLimit(1)
                                        .foregroundStyle(AnkiTheme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 20)
            HStack(spacing: 9) {
                Image(systemName: "book.closed").font(.system(size: 16))
                if sidebarExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.text("每天一点")).font(.system(size: 13, weight: .medium))
                        Text(store.text("离线学习，随时回来。")).font(.system(size: 11)).foregroundStyle(AnkiTheme.muted)
                    }
                }
            }.padding(.horizontal, 10).padding(.bottom, 12)
        }
        .padding(sidebarExpanded ? 14 : 10).frame(width: sidebarExpanded ? 218 : 66)
        .background(AnkiTheme.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(AnkiTheme.border).frame(width: 0.5) }
    }
}
