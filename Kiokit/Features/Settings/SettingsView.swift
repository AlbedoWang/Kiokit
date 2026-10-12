import SwiftUI
import KiokitCore

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
                    KiokitMark(size: 32).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Kiokit").font(AnkiTheme.editorial(25))
                        Text(store.text("留一点时间，给长久的记忆。"))
                            .font(.caption).foregroundStyle(AnkiTheme.muted)
                    }
                }.padding(.vertical, 10)
            }
            Section {
                Picker(store.text("显示模式"), selection: Binding(get: { store.settings.appearance }, set: { value in var settings = store.settings; settings.appearance = value; store.saveSettings(settings) })) {
                    Text(store.text("跟随系统")).tag("system")
                    Text(store.text("浅色")).tag("light")
                    Text(store.text("深色")).tag("dark")
                }
                .accessibilityIdentifier("interfaceAppearance")
            } header: { Text(store.text("外观")).foregroundStyle(AnkiTheme.muted) }
            Section {
                Picker(store.text("语言"), selection: Binding(get: { store.settings.interfaceLanguage ?? "system" }, set: { value in
                    var settings = store.settings
                    settings.interfaceLanguage = value == "system" ? nil : value
                    store.saveSettings(settings)
                })) {
                    Text(store.text("跟随系统")).tag("system")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                }
                .accessibilityIdentifier("interfaceLanguage")
            } header: {
                Text(store.text("界面语言")).foregroundStyle(AnkiTheme.muted)
            } footer: {
                Text(store.text("默认匹配手机语言。支持简体中文和英文，其他系统语言显示英文。此设置不会翻译牌组或卡片内容。")).ankiFootnote()
            }
            Section {
                AnkiNumberField(title: store.text("默认每日复习上限"), value: Binding(get: { store.settings.dailyGoal }, set: { value in
                    var settings = store.settings
                    settings.dailyGoal = value
                    store.saveSettings(settings)
                }), minimum: 0, accessibilityID: "dailyReviewGoal")
                AnkiNumberField(title: store.text("默认每日新卡片"), value: Binding(get: { store.settings.newCardsPerDay }, set: { value in
                    var settings = store.settings
                    settings.newCardsPerDay = value
                    store.saveSettings(settings)
                }), minimum: 0, accessibilityID: "defaultNewCardLimit")
            } header: { Text(store.text("学习节奏")).foregroundStyle(AnkiTheme.muted) } footer: {
                Text(store.text("这些设置修改 Anki 的默认预设。牌组可使用其他预设或单独的每日额度；复习上限、父牌组额度与日切时间均由 Anki 管理。")).ankiFootnote()
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(store.text("播放音量"), systemImage: "speaker.wave.2")
                    PlaybackVolumeView().frame(height: 30)
                        .accessibilityLabel(store.text("播放音量"))
                }.padding(.vertical, 4)
                Toggle(store.text("自动播放音频"), isOn: Binding(get: { store.settings.autoPlayAudio ?? true }, set: { value in
                    var settings = store.settings
                    settings.autoPlayAudio = value
                    store.saveSettings(settings)
                }))
            } header: { Text(store.text("朗读")).foregroundStyle(AnkiTheme.muted) } footer: {
                Text(store.text("修改默认预设的音频设置。录音和 TTS 内容由 Anki 模板决定；TTS 使用模板指定的语言与设备语音。")).ankiFootnote()
            }
            Section {
                Button { importing = true } label: { Label(store.text("导入牌组或恢复备份"), systemImage: "square.and.arrow.down") }
                Button {
                    preparingBackup = true
                    Task {
                        defer { preparingBackup = false }
                        do { document = BackupDocument(data: try await store.backupData()); exporting = true }
                        catch { store.errorMessage = store.text("导出失败。\n\(store.errorText(error))") }
                    }
                } label: {
                    HStack {
                        Label(store.text("导出完整备份"), systemImage: "square.and.arrow.up")
                        Spacer()
                        if preparingBackup { ProgressView() }
                    }
                }.disabled(preparingBackup).accessibilityIdentifier("exportBackup")
            } header: { Text(store.text("牌组与备份")).foregroundStyle(AnkiTheme.muted) } footer: {
                Text(store.text("使用 Anki 官方导入与备份格式：.apkg、UTF-8 CSV/TSV 和 .colpkg。完整备份包含笔记、牌组设置、复习记录和媒体。")).ankiFootnote()
            }
            Section {
                Label(store.text("离线使用，无需账号"), systemImage: "wifi.slash")
                HStack { Text(store.text("版本")); Spacer(); Text("1.0").foregroundStyle(AnkiTheme.muted) }
                NavigationLink(store.text("导入与复习说明")) { ImportHelpView() }
                NavigationLink(store.text("许可证与致谢")) { LicensesView() }
                    .accessibilityIdentifier("licenses")
            } header: { Text(store.text("关于")).foregroundStyle(AnkiTheme.muted) } footer: {
                Text(store.text("Kiokit 使用 Anki 官方后端，版本 26.09.3。调度、队列、导入、模板和统计直接调用上游实现。")).ankiFootnote()
                    .accessibilityIdentifier("settingsAboutFootnote")
            }
        }
        .ankiForm()
        .contentMargins(.bottom, 24, for: .scrollContent)
        .navigationTitle(store.text("设置"))
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .ankiCollectionPackage, defaultFilename: "Kiokit-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success: exported = true
            case .failure(let error): store.errorMessage = store.errorText(error)
            }
        }
        .alert(store.text("备份已保存"), isPresented: $exported) { Button(store.text("好"), role: .cancel) {} } message: { Text(store.text("可以导入 .colpkg 文件，在本应用或 Anki 中恢复完整学习数据。")) }
    }
}
