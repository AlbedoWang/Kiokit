import SwiftUI
import OpenAnkiCore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(CollectionStore.self) private var store
    @State private var importing = false
    @State private var didImportTestFixture = false

    var body: some View {
        Group {
            if store.loadFailed {
                ContentUnavailableView {
                    Label("无法读取本地牌组", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "原有文件已保留，请检查设备可用空间后重试。")
                } actions: {
                    Button("重新读取") { store.reload() }.buttonStyle(.borderedProminent)
                }
            } else {
                TabView {
                    NavigationStack { DecksView(importing: $importing) }
                        .tabItem { Label("牌组", systemImage: "rectangle.stack") }
                    NavigationStack { CardBrowserView() }
                        .tabItem { Label("卡片", systemImage: "rectangle.on.rectangle") }
                    NavigationStack { StatisticsView() }
                        .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
                    NavigationStack { SettingsView(importing: $importing) }
                        .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.ankiPackage, .openAnkiBackup, .commaSeparatedText, .tabSeparatedText, .plainText, .json, .zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await store.importFile(url) } }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in Task { await store.importFile(url) } }
        .task {
            #if DEBUG
            if !didImportTestFixture, let path = ProcessInfo.processInfo.environment["OPENANKI_IMPORT_FILE"] {
                didImportTestFixture = true
                await store.importFile(URL(fileURLWithPath: path))
            }
            #endif
        }
        .overlay {
            if store.isImporting {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large)
                        Text("正在导入牌组…").font(.headline)
                        Text("读取卡片和离线媒体").font(.caption).foregroundStyle(.secondary)
                    }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                }.accessibilityAddTraits(.isModal)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil && !store.loadFailed }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert("导入完成", isPresented: Binding(get: { store.importMessage != nil }, set: { if !$0 { store.importMessage = nil } })) {
            Button("好", role: .cancel) { store.importMessage = nil }
        } message: { Text(store.importMessage ?? "") }
        .alert("恢复完整备份？", isPresented: Binding(get: { store.pendingBackup != nil }, set: { if !$0 { store.cancelRestore() } })) {
            Button("取消", role: .cancel) { store.cancelRestore() }
            Button("恢复备份", role: .destructive) { store.restoreBackup() }
        } message: {
            Text("将替换当前所有牌组和学习进度。备份包含 \(store.pendingBackup?.snapshot.decks.count ?? 0) 个牌组、\(store.pendingBackup?.snapshot.cards.count ?? 0) 张卡片。建议先在设置中导出当前备份。")
        }
    }
}

extension UTType {
    static let ankiPackage = UTType(importedAs: "net.anki.apkg", conformingTo: .zip)
    static let openAnkiBackup = UTType(exportedAs: "app.openanki.backup", conformingTo: .zip)
}

#Preview { ContentView().environment(CollectionStore(directory: URL.temporaryDirectory.appendingPathComponent("OpenAnkiPreview"))) }
