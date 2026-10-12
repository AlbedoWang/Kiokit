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
                    Label(store.text("无法读取本地牌组"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? store.text("原有文件已保留，请检查设备可用空间后重试。"))
                } actions: {
                    Button(store.text("重新读取")) { store.reload() }.buttonStyle(.borderedProminent)
                }
            } else {
                AppNavigationView(importing: $importing)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.ankiPackage, .ankiCollectionPackage, .openAnkiBackup, .commaSeparatedText, .tabSeparatedText, .plainText, .zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await store.importFile(url) } }
            case .failure(let error): store.errorMessage = store.errorText(error)
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
                        Text(store.text("正在导入牌组…")).font(.headline)
                        Text(store.text("读取卡片和离线媒体")).font(.caption).foregroundStyle(.secondary)
                    }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                }.accessibilityAddTraits(.isModal)
            }
        }
        .alert(store.text("操作未完成"), isPresented: Binding(get: { store.errorMessage != nil && !store.loadFailed }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(store.text("好"), role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert(store.text("导入完成"), isPresented: Binding(get: { store.importMessage != nil }, set: { if !$0 { store.importMessage = nil } })) {
            Button(store.text("好"), role: .cancel) { store.importMessage = nil }
        } message: { Text(store.importMessage ?? "") }
        .alert(store.text("恢复完整备份？"), isPresented: Binding(get: { store.pendingBackup != nil }, set: { if !$0 { store.cancelRestore() } })) {
            Button(store.text("取消"), role: .cancel) { store.cancelRestore() }
            Button(store.text("恢复备份"), role: .destructive) { store.restoreBackup() }
        } message: {
            Text(store.text("将替换当前牌组和学习进度。建议先在设置中导出当前备份。"))
        }
    }
}

#Preview { ContentView().environment(CollectionStore(directory: URL.temporaryDirectory.appendingPathComponent("OpenAnkiPreview"))) }
