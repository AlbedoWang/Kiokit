//
//  OpenAnkiIOSApp.swift
//  OpenAnkiIOS
//
//  Created by Jian on October 11, 2026.
//

import SwiftUI
import OpenAnkiCore

@main
struct OpenAnkiIOSApp: App {
    @State private var store: CollectionStore
    @State private var audio = CardAudioController()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        var directory: URL?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            directory = URL.applicationSupportDirectory.appendingPathComponent("OpenAnkiUITests", isDirectory: true)
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
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { audio.stop() }
                }
        }
    }
}
