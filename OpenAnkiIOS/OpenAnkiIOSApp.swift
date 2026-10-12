//
//  OpenAnkiIOSApp.swift
//  OpenAnkiIOS
//
//  Created by 健 on 10/11/26.
//

import SwiftUI
import OpenAnkiCore

@main
struct OpenAnkiIOSApp: App {
    @State private var store: CollectionStore

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
                .tint(AnkiTheme.tint)
                .preferredColorScheme(store.settings.appearance == "light" ? .light : store.settings.appearance == "dark" ? .dark : nil)
        }
    }
}
