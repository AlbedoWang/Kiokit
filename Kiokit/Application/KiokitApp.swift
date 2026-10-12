import SwiftUI
import KiokitCore

@main
struct KiokitApp: App {
    @State private var store: CollectionStore
    @State private var audio = CardAudioController()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        var directory: URL?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            directory = URL.applicationSupportDirectory.appendingPathComponent("KiokitUITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-test-data"), let directory {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        #endif
        _store = State(initialValue: CollectionStore(directory: directory))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(audio)
                .environment(\.locale, store.uiLocale)
                .tint(AnkiTheme.tint)
                .preferredColorScheme(store.settings.appearance == "light" ? .light : store.settings.appearance == "dark" ? .dark : nil)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    audio.setApplicationActive(phase == .active)
                    if phase == .active { store.refreshStudyDay() }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) }
                        catch { return }
                        store.refreshStudyDay()
                    }
                }
        }
    }
}
