// Browser command handling adapted from ankitects/anki 26.09.3, qt/aqt/stats.py.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import OpenAnkiCore

/// Platform host for Anki's unmodified SvelteKit statistics page. Data,
/// graph calculations, ranges, preferences, and translations stay upstream.
struct AnkiStatisticsWebView: UIViewRepresentable {
    @Environment(CollectionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let statistics: AnkiJSON
    let deckID: UUID?
    let localeIdentifier: String
    var isActive = true

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "openanki")
        configuration.userContentController.add(context.coordinator, name: "pycmd")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "ankiRPC")
        var bridge = AnkiReviewerWebView.bridge
        #if DEBUG
        bridge += """
        window.openAnkiStatisticsErrors = [];
        addEventListener('error', event => openAnkiStatisticsErrors.push(event.message));
        addEventListener('unhandledrejection', event => openAnkiStatisticsErrors.push(String(event.reason)));
        """
        #endif
        configuration.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.accessibilityIdentifier = "officialStatistics"
        context.coordinator.view = view
        context.coordinator.startDiagnostics()
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard isActive else {
            coordinator.timer?.invalidate()
            coordinator.timer = nil
            return
        }
        if coordinator.timer == nil { coordinator.startDiagnostics() }
        let dark = colorScheme == .dark
        guard coordinator.statistics != statistics || coordinator.deckID != deckID || coordinator.locale != localeIdentifier || coordinator.dark != dark else { return }
        coordinator.statistics = statistics
        coordinator.deckID = deckID
        coordinator.locale = localeIdentifier
        coordinator.dark = dark
        view.load(URLRequest(url: URL(string: "openanki://statistics/graphs" + (dark ? "#night" : ""))!))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.timer?.invalidate()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pycmd")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "ankiRPC", contentWorld: .page)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        let store: CollectionStore
        let backendIdentity: String
        weak var view: WKWebView?
        var statistics: AnkiJSON?
        var deckID: UUID?
        var locale: String?
        var dark = false
        var timer: Timer?
        #if DEBUG
        var lastBridgeCommand: String?
        #endif
        init(store: CollectionStore) { self.store = store; backendIdentity = store.backendIdentity }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            #if DEBUG
            lastBridgeCommand = message.body as? String
            #endif
            guard let command = message.body as? String, command.hasPrefix("browserSearch:") else { return }
            // qt/aqt/stats.py::_on_bridge_cmd passes the original graph query
            // to the browser. Native Anki search interprets that query.
            store.requestedBrowserSearch = String(command.dropFirst("browserSearch:".count))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            do {
                // A restored collection closes the previous frontend session,
                // even when its graph data happens to equal the new profile's.
                guard backendIdentity == store.backendIdentity else { throw CollectionError.invalid("无法读取牌组。") }
                guard let body = message.body as? [String: String], let path = body["path"], let encoded = body["data"], let data = Data(base64Encoded: encoded) else { throw CollectionError.invalid("无法读取牌组。") }
                replyHandler(try store.statisticsRequest(path: path, data: data).base64EncodedString(), nil)
            } catch { replyHandler(nil, store.errorText(error)) }
        }

        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            do {
                guard let url = task.request.url else { throw URLError(.badURL) }
                let root = AnkiWebResources.directory.appendingPathComponent("sveltekit")
                let path = url.path == "/graphs" ? "index.html" : String(url.path.dropFirst())
                let file = root.appendingPathComponent(path).standardizedFileURL
                guard file.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw URLError(.noPermissionsToReadFile) }
                var data = try Data(contentsOf: file)
                let mime = AnkiWebFrontend.commonMimeType(for: file.path) ?? UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                if path == "index.html" {
                    let html = try AnkiWebFrontend.trustedSvelteHTML(String(decoding: data, as: UTF8.self))
                    let style = "<style>\(AnkiStatisticsStyle.css(dark: dark))</style>"
                    let script = "<script>\(try AnkiStatisticsStyle.script(titles: store.statisticsChartTitles()))</script>"
                    data = Data(html.replacingOccurrences(of: "</head>", with: style + script + "</head>").utf8)
                }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Access-Control-Allow-Origin": "*"])!
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            } catch { task.didFailWithError(error) }
        }

        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if navigationAction.navigationType == .linkActivated, let url, ["http", "https"].contains(url.scheme ?? "") {
                // NewDeckStats uses set_open_links_externally; iOS supplies
                // the system browser for the same user-activated links.
                UIApplication.shared.open(url)
            }
            decisionHandler(url?.scheme == "openanki" && url?.host == "statistics" && url?.path == "/graphs" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { store.errorMessage = store.errorText(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { store.errorMessage = store.errorText(error) }

        func startDiagnostics() {
            #if DEBUG
            guard ProcessInfo.processInfo.environment["OPENANKI_STATISTICS_DIAGNOSTICS_FILE"] != nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.writeDiagnostics() }
            }
            #endif
        }

        private func writeDiagnostics() {
            #if DEBUG
            guard let path = ProcessInfo.processInfo.environment["OPENANKI_STATISTICS_DIAGNOSTICS_FILE"], let view else { return }
            view.evaluateJavaScript("""
            (() => {
            if (!document.body) return null;
            return JSON.stringify({text: document.body.innerText, errors: window.openAnkiStatisticsErrors ?? [],
                charts: document.querySelectorAll('[data-openanki-graph] svg').length,
                sections: Array.from(document.querySelectorAll('[data-openanki-graph]')).map(node => ({role: node.dataset.openankiGraph, title: node.querySelector('h1').textContent, radius: getComputedStyle(node).borderRadius, headingSize: getComputedStyle(node.querySelector('h1')).fontSize})),
                visibleTables: Array.from(document.querySelectorAll('table')).filter(node => node.getClientRects().length > 0).length,
                roundedBars: document.querySelectorAll('[data-openanki-graph] g[class^="bars"] rect[rx="6"]').length,
                tickSizes: Array.from(document.querySelectorAll('[data-openanki-graph] .tick text')).map(node => parseFloat(getComputedStyle(node).fontSize) * node.ownerSVGElement.getBoundingClientRect().width / node.ownerSVGElement.viewBox.baseVal.width),
                visibleOverlays: Array.from(document.querySelectorAll('[data-openanki-graph] .cumulative-overlay')).filter(node => getComputedStyle(node).display !== 'none').length,
                search: document.getElementById('statisticsSearchText')?.value ?? '', html: document.body.innerHTML});
            })()
            """) { [weak self] value, _ in
                guard let self, let value = value as? String, var result = (try? JSONDecoder().decode(AnkiJSON.self, from: Data(value.utf8)))?.object else { return }
                result["transport"] = self.store.statisticsDiagnostics
                result["bridgeCommand"] = .string(self.lastBridgeCommand ?? "")
                if let data = try? JSONEncoder().encode(AnkiJSON.object(result)) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
            }
            #endif
        }
    }
}
