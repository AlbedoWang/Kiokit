import SwiftUI
import OpenAnkiCore
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.openAnkiBackup] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(CollectionStore.self) private var store
    @Binding var importing: Bool
    @State private var exporting = false
    @State private var preparingBackup = false
    @State private var document: BackupDocument?
    @State private var exported = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(.white)
                        .frame(width: 56, height: 56).background(AnkiTheme.tint.gradient, in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("OpenAnki").font(.title3.bold())
                        Text("留一点时间，给长久的记忆。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 10)
            }
            Section {
                Stepper(value: Binding(get: { store.settings.dailyGoal }, set: { value in var settings = store.settings; settings.dailyGoal = value; store.saveSettings(settings) }), in: 5...500, step: 5) {
                    HStack {
                        Text("每日目标")
                        Spacer()
                        Text("\(store.settings.dailyGoal) 次").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: Binding(get: { store.settings.newCardsPerDay }, set: { value in var settings = store.settings; settings.newCardsPerDay = value; store.saveSettings(settings) }), in: 0...200, step: 5) {
                    HStack {
                        Text("每日新卡片")
                        Spacer()
                        Text("\(store.settings.newCardsPerDay) 张").foregroundStyle(.secondary)
                    }
                }
            } header: { Text("学习节奏") } footer: {
                Text("每日目标统计评分次数，不限制复习。新卡片额度由全部牌组共享，每天按设备日期重置；已开始学习的卡片继续按时复习。")
            }
            Section("外观") {
                Picker("显示模式", selection: Binding(get: { store.settings.appearance }, set: { value in var settings = store.settings; settings.appearance = value; store.saveSettings(settings) })) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            }
            Section {
                Button { importing = true } label: { Label("导入牌组或恢复备份", systemImage: "square.and.arrow.down") }
                Button {
                    preparingBackup = true
                    Task {
                        defer { preparingBackup = false }
                        do { document = BackupDocument(data: try await store.backupData()); exporting = true }
                        catch { store.errorMessage = "导出失败。\n\(error.localizedDescription)" }
                    }
                } label: {
                    HStack {
                        Label("导出完整备份", systemImage: "square.and.arrow.up")
                        Spacer()
                        if preparingBackup { ProgressView() }
                    }
                }.disabled(preparingBackup).accessibilityIdentifier("exportBackup")
            } header: { Text("牌组与备份") } footer: {
                Text("支持 .apkg、UTF-8 CSV/TSV 和 .openanki。完整备份包含牌组、复习进度、设置和媒体，建议定期保存到「文件」。")
            }
            Section {
                Label("离线使用，无需账号", systemImage: "wifi.slash")
                HStack { Text("版本"); Spacer(); Text("1.0").foregroundStyle(.secondary) }
                NavigationLink("导入与复习说明") { ImportHelpView() }
            } header: { Text("关于") } footer: {
                Text("OpenAnki 是独立的离线闪卡应用。复习使用本地 SM-2 风格算法，导入 Anki 牌组时会重新开始学习。")
            }
        }
        .navigationTitle("设置")
        .fileExporter(isPresented: $exporting, document: document, contentType: .openAnkiBackup, defaultFilename: "OpenAnki-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success: exported = true
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .alert("备份已保存", isPresented: $exported) { Button("好", role: .cancel) {} } message: { Text("可以随时导入 .openanki 文件，恢复牌组和学习进度。") }
    }
}

private struct ImportHelpView: View {
    var body: some View {
        List {
            Section("从桌面 Anki 导入") {
                Text("1. 在 Anki 桌面版选择牌组，导出为 .apkg。\n2. 通过 AirDrop 或其他方式将文件保存到 iPhone / iPad 的「文件」。\n3. 在 OpenAnki 点击导入，选择该文件。")
                Text("支持旧版 .anki2 / .anki21 和新版 .anki21b 包，支持常见正反面、反向、填空、模板样式及离线图片和音频。")
                Text("相同 Anki 笔记的相同卡片会去重。牌组名称相同时会合并；导入保留暂停状态，复习进度从头开始。")
            }
            Section("文本导入") {
                Text("UTF-8 编码，前两列为正面和背面，第三列为可选标签。CSV 支持带引号的逗号和换行；TSV 使用制表符分隔。可识别 Anki 的 #separator、#html 和 #deck 文件头。")
            }
            Section("如何复习") {
                Text("先回想，再显示答案。根据回忆情况选择重来、困难、良好或简单。按钮上显示下次复习间隔，可撤销最近一次评分。")
                Text("新卡片选择良好会在 10 分钟后再练习，随后良好进入每天复习。重来在 1 分钟后练习，简单直接进入较长间隔。到期的学习卡片优先出现。")
            }
            Section("备份与支持范围") {
                Text(".openanki 是包含完整学习数据和媒体的备份，恢复时会替换当前牌组。恢复前请先导出当前备份。")
                Text("暂不支持图像遮挡、自定义 JavaScript 交互、依赖 MathJax 的公式和外部网络资源。复杂自定义模板可能需要在桌面版改为普通卡片。导入仅建立本应用的卡片，不会修改原 .apkg 文件。")
            }
        }.font(.subheadline).navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
    }
}
