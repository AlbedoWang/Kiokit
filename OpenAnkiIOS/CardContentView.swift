import SwiftUI
import WebKit
import OpenAnkiCore

struct CardContentView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(CardAudioController.self) private var audio
    let card: Flashcard
    let answer: Bool
    var autoPlayAudio = false

    private var owner: String { "\(card.id)-\(answer)" }
    private var mediaURL: URL? { card.mediaFolder.map { store.repository.mediaURL.appendingPathComponent($0, isDirectory: true) } }
    private var hasAudio: Bool { card.pronunciation != nil || !CardAudio.filenames(in: card.front + card.back).isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            content
            if hasAudio { audioControls }
        }
        .onAppear {
            if autoPlayAudio && !answer && hasAudio && (store.settings.autoPlayAudio ?? true) {
                audio.readWord(card: card, mediaURL: mediaURL, owner: owner)
            }
        }
        .onDisappear { audio.stop(owner: owner) }
    }

    private var audioControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button { audio.readWord(card: card, mediaURL: mediaURL, owner: owner) } label: {
                    Label(store.text("朗读单词"), systemImage: "speaker.wave.2")
                }.accessibilityIdentifier("readWord")
                if answer, let pronunciation = card.pronunciation, !pronunciation.examples.isEmpty {
                    Button { audio.readExamples(pronunciation, owner: owner) } label: {
                        Label(store.text("朗读例句"), systemImage: "text.bubble")
                    }.accessibilityIdentifier("readExamples")
                }
                if audio.owner == owner && audio.isPlaying {
                    Button { audio.stop(owner: owner) } label: { Image(systemName: "stop.circle") }
                        .accessibilityLabel(store.text("停止朗读")).accessibilityIdentifier("stopAudio")
                }
            }.font(.footnote).buttonStyle(.plain).foregroundStyle(AnkiTheme.tint)
            if audio.owner == owner {
                if let error = audio.error {
                    Text(store.text(error)).font(.caption).foregroundStyle(.secondary)
                } else if let source = audio.source {
                    Text(store.text(source)).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("playbackSource")
                }
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if card.isHTML {
            OfflineCardWebView(html: CardAudio.removingSoundMarkers(from: answer ? card.back : card.front), css: card.css,
                               mediaURL: mediaURL)
                .frame(minHeight: 220)
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    if answer {
                        Text(card.front).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Rectangle().fill(AnkiTheme.tint.opacity(0.15)).frame(width: 46, height: 2)
                    }
                    Text(answer ? card.back : card.front)
                        .font(.system(size: answer ? 24 : 29, weight: .regular, design: .serif))
                        .foregroundStyle(AnkiTheme.ink)
                        .multilineTextAlignment(.center).lineSpacing(8)
                        .textSelection(.enabled).frame(maxWidth: .infinity)
                        .accessibilityIdentifier(answer ? "answerContent" : "questionContent")
                }.padding(.vertical, 32).padding(.horizontal, 4)
            }.defaultScrollAnchor(.center)
        }
    }
}

private struct OfflineCardWebView: UIViewRepresentable {
    @Environment(CollectionStore.self) private var store
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
        body { margin: 0; padding: 24px 4px; font: 24px Georgia, -apple-system, serif; text-align: center; line-height: 1.65; overflow-wrap: anywhere; }
        img, video { max-width: 100%; height: auto; } audio { width: 100%; margin: 16px 0; }
        .cloze { color: \(dark ? "#e69b7e" : "#a64f33"); font-weight: 600; } .type-hint { color: #97958d; font-size: 16px; }
        hr { border: 0; border-top: 1px solid #8884; margin: 24px 0; }
        \(css)
        html, body, .card { background: transparent !important; color: \(dark ? "#f9f9f7" : "#131313") !important; }
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
            webView.loadHTMLString(store.text("<p>无法显示卡片：\(TemplateRenderer.escape(store.errorText(error)))</p>"), baseURL: nil)
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
