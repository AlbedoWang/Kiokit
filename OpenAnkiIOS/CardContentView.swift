import SwiftUI
import WebKit
import OpenAnkiCore

struct CardContentView: View {
    @Environment(CollectionStore.self) private var store
    let card: Flashcard
    let answer: Bool

    var body: some View {
        if card.isHTML {
            OfflineCardWebView(html: answer ? card.back : card.front, css: card.css,
                               mediaURL: card.mediaFolder.map { store.repository.mediaURL.appendingPathComponent($0, isDirectory: true) })
                .frame(minHeight: 220)
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    if answer {
                        Text(card.front).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Rectangle().fill(AnkiTheme.tint.opacity(0.15)).frame(width: 46, height: 2)
                    }
                    Text(answer ? card.back : card.front)
                        .font(.system(size: answer ? 24 : 29, weight: answer ? .regular : .medium, design: .rounded))
                        .multilineTextAlignment(.center).lineSpacing(8)
                        .textSelection(.enabled).frame(maxWidth: .infinity)
                        .accessibilityIdentifier(answer ? "answerContent" : "questionContent")
                }.padding(.vertical, 32).padding(.horizontal, 4)
            }.defaultScrollAnchor(.center)
        }
    }
}

private struct OfflineCardWebView: UIViewRepresentable {
    let html: String
    let css: String
    let mediaURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let dark = colorScheme == .dark
        let base = mediaURL.map { "<base href='\(TemplateRenderer.escape($0.absoluteString))/'>" } ?? ""
        let document = """
        <!doctype html><html><head><meta charset='utf-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <meta http-equiv='Content-Security-Policy' content="default-src 'none'; img-src file: data:; media-src file: data:; style-src 'unsafe-inline' file:; font-src file: data:; base-uri file:; form-action 'none'">
        \(base)
        <style>
        :root { color-scheme: \(dark ? "dark" : "light"); }
        body { margin: 0; padding: 24px 4px; font: 24px -apple-system, sans-serif; text-align: center; line-height: 1.65; overflow-wrap: anywhere; }
        img, video { max-width: 100%; height: auto; } audio { width: 100%; margin: 16px 0; }
        .cloze { color: #459b88; font-weight: 600; } .type-hint { color: #888; font-size: 16px; }
        hr { border: 0; border-top: 1px solid #8884; margin: 24px 0; }
        \(css)
        html, body, .card { background: transparent !important; color: \(dark ? "#f2f2f2" : "#252a28") !important; }
        </style></head><body class='card'>\(TemplateRenderer.htmlWithAudio(html))</body></html>
        """
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        do {
            let directory = mediaURL ?? URL.cachesDirectory.appendingPathComponent("OpenAnkiRendered", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = context.coordinator.pageURL ?? directory.appendingPathComponent(".openanki-render-" + UUID().uuidString + ".html")
            context.coordinator.pageURL = url
            try document.write(to: url, atomically: true, encoding: .utf8)
            webView.loadFileURL(url, allowingReadAccessTo: directory)
        } catch {
            webView.loadHTMLString("<p>无法显示卡片：\(TemplateRenderer.escape(error.localizedDescription))</p>", baseURL: nil)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        if let url = coordinator.pageURL { try? FileManager.default.removeItem(at: url) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastDocument: String?
        var pageURL: URL?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Cards remain offline, and cannot open links or navigate to other files.
            let isRenderedPage = navigationAction.request.url?.isFileURL == true && navigationAction.request.url?.lastPathComponent == pageURL?.lastPathComponent
            decisionHandler(navigationAction.navigationType == .other && isRenderedPage ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("Offline card failed to load: \(error.localizedDescription)")
            #endif
        }
    }
}
