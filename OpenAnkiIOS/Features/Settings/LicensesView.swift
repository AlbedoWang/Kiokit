import SwiftUI
import UIKit
import OpenAnkiCore

/// Offline copyright/license notices and links to corresponding source,
/// following the upstream About dialog's license and attribution entry points.
struct LicensesView: View {
    @Environment(CollectionStore.self) private var store

    var body: some View {
        List {
            Section {
                Text("OpenAnkiIOS · AGPL-3.0-or-later")
                Text(store.text("不提供担保。完整条款见许可证。"))
                    .font(.subheadline).foregroundStyle(AnkiTheme.muted)
                Link(store.text("项目源代码"), destination: OpenAnkiLicenses.sourceURL)
                Link(store.text("上游 Anki"), destination: OpenAnkiLicenses.upstreamURL)
            }
            Section(store.text("许可证与致谢")) {
                document("OpenAnkiIOS (AGPL-3.0)", path: "OpenAnki-LICENSE.txt")
                document("OpenAnkiIOS — Copyright & notices", path: "NOTICE.md")
                document("Anki 26.09.3 — License", path: "Anki/LICENSE")
                document("Anki — Contributors", path: "Anki/CONTRIBUTORS")
                document("ZIPFoundation (MIT)", path: "ZIPFoundation-LICENSE.txt")
                document("Rust dependencies", path: "RustDependencies.txt")
                document("Web dependencies", path: "WebDependencies.txt")
            }
        }
        .ankiForm()
        .navigationTitle(store.text("许可证与致谢"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func document(_ title: String, path: String) -> some View {
        NavigationLink(title) { LicenseDocumentView(title: title, path: path) }
    }
}

private struct LicenseDocumentView: View {
    @Environment(CollectionStore.self) private var store
    let title: String
    let path: String
    @State private var text: String?

    var body: some View {
        Group {
            if let text { LicenseTextView(text: text) }
            else { ProgressView() }
        }
        .background(AnkiTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) {
            let url = OpenAnkiLicenses.directory.appendingPathComponent(path)
            do { text = try await Task.detached { try String(contentsOf: url, encoding: .utf8) }.value }
            catch { text = store.text("无法读取许可证。"); store.errorMessage = store.errorText(error) }
        }
    }
}

private struct LicenseTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 24, right: 16)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
