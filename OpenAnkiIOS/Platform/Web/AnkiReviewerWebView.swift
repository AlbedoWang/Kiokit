import SwiftUI
import WebKit
import UniformTypeIdentifiers
import OpenAnkiCore

/// WebKit platform bindings for the unmodified official reviewer. A local URL
/// scheme serves bundled assets and collection media without an HTTP listener.
struct AnkiReviewerWebView: UIViewRepresentable {
    @Environment(CollectionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let card: Flashcard
    let answer: Bool
    let mediaURL: URL
    let reviewing: Bool
    let onShowAnswer: (() -> Void)?
    let playAudio: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "openanki")
        configuration.userContentController.add(context.coordinator, name: "pycmd")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "ankiRPC")
        var bridge = Self.bridge
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPENANKI_REVIEWER_DIAGNOSTICS_FILE"] != nil {
            bridge += "\ndocument.addEventListener('click', () => requestAnimationFrame(() => bridgeCommand('renderDiagnostics')));"
        }
        #endif
        configuration.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.clipsToBounds = true
        view.scrollView.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.playAudio = playAudio
        coordinator.onShowAnswer = onShowAnswer
        coordinator.requestedAnswer = answer
        let dark = colorScheme == .dark
        guard coordinator.cardID != card.id else {
            if coordinator.dark != dark {
                coordinator.dark = dark
                coordinator.bodyClass = "card card\(coordinator.typed!.cardOrdinal + 1) isMac" + (dark ? " nightMode night_mode" : "")
                if coordinator.ready { coordinator.updateTheme(view) }
            }
            if reviewing && coordinator.textGeneration != store.reviewTextGeneration {
                // Like reviewer.py::card.load(), use the current native
                // projection; SwiftUI may still be passing the preceding value.
                guard let current = store.currentCard, current.id == card.id else { return }
                do { try coordinator.redraw(view, card: current) }
                catch { store.errorMessage = store.errorText(error) }
            }
            coordinator.showRequestedSide(view)
            return
        }
        do {
            coordinator.cardID = card.id
            coordinator.generation = store.reviewGeneration
            coordinator.reviewing = reviewing
            coordinator.textGeneration = store.reviewTextGeneration
            coordinator.mediaURL = mediaURL
            coordinator.typed = try store.typedAnswer(for: card)
            coordinator.question = coordinator.typed!.question
            coordinator.answer = try store.prepareCardTextForDisplay(card.back)
            coordinator.prefetchAnswer = try store.escapeMediaFilenames(card.back)
            coordinator.mutation = reviewing ? store.stateMutationJavaScript : nil
            coordinator.dark = dark
            coordinator.bodyClass = "card card\(coordinator.typed!.cardOrdinal + 1) isMac" + (dark ? " nightMode night_mode" : "")
            coordinator.ready = false
            coordinator.answerShown = false
            coordinator.document = """
            <!doctype html><html class="\(dark ? "night-mode" : "")" data-bs-theme="\(dark ? "dark" : "light")"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' openanki:; img-src openanki: data:; media-src openanki: data:; style-src 'unsafe-inline' openanki:; font-src openanki: data:; connect-src openanki:; form-action 'none'">
            <link rel="stylesheet" href="/_anki/css/reviewer.css">
            <style>:root { color-scheme: \(dark ? "dark" : "light"); --canvas: transparent; --fg: inherit; }
            body { margin: 0; padding: 24px 4px; font: 24px Georgia, -apple-system, serif; text-align: center; line-height: 1.65; }
            </style><style id="card-style">\(card.css)</style></head><body>
            <div id="_mark" hidden>&#x2605;</div><div id="_flag" hidden>&#x2691;</div>
            <div id="qa" dir="auto"></div><script src="/_anki/js/reviewer.js"></script>
            </body></html>
            """
            view.load(URLRequest(url: URL(string: "openanki://reviewer/review.html")!))
        } catch { store.errorMessage = store.errorText(error) }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pycmd")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "ankiRPC", contentWorld: .page)
    }

    // Native transport only. Anki's protobuf requests/responses are preserved;
    // all state transformations remain in upstream ts/reviewer/answering.ts.
    static let bridge = """
    window.pycmd = window.bridgeCommand = (command) => window.webkit.messageHandlers.pycmd.postMessage(command);
    const originalFetch = window.fetch.bind(window);
    window.fetch = async (input, options = {}) => {
        const url = new URL(typeof input === 'string' ? input : input.url, location.href);
        if (url.pathname.startsWith('/_anki/') && options.method === 'POST') {
            const bytes = new Uint8Array(options.body ?? []);
            let raw = ''; for (const byte of bytes) raw += String.fromCharCode(byte);
            const result = await window.webkit.messageHandlers.ankiRPC.postMessage({path: url.pathname, data: btoa(raw)});
            const decoded = Uint8Array.from(atob(result), c => c.charCodeAt(0));
            return new Response(decoded, {status: 200, headers: {'Content-Type': 'application/binary'}});
        }
        return originalFetch(input, options);
    };
    """

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKURLSchemeHandler, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        let store: CollectionStore
        var cardID: UUID?
        var generation = 0
        var reviewing = false
        private var isCurrentReviewer: Bool { cardID == store.currentCard?.id && generation == store.reviewGeneration }
        var textGeneration = 0
        var mediaURL: URL?
        var document = ""
        let documentIdentity = UUID().uuidString
        var typed: AnkiTypedAnswer?
        var question = ""
        var answer = ""
        var prefetchAnswer = ""
        var bodyClass = ""
        var dark = false
        var mutation: String?
        var ready = false
        var requestedAnswer = false
        var answerShown = false
        var playAudio: ((String) -> Void)?
        var onShowAnswer: (() -> Void)?

        init(store: CollectionStore) { self.store = store }

        private func js(_ value: String) -> String {
            String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateTheme(webView)
            runStateMutation(webView)
            showQuestion(webView)
        }

        func updateTheme(_ view: WKWebView) {
            view.evaluateJavaScript(AnkiWebFrontend.themeUpdateJavaScript(nightMode: dark) + "\ndocument.documentElement.style.colorScheme = '\(dark ? "dark" : "light")';") { _, error in
                if let error { self.store.errorMessage = error.localizedDescription }
                self.diagnostics(view)
            }
        }

        private func showQuestion(_ webView: WKWebView) {
            let source = """
            _showQuestion(\(js(question)), \(js(prefetchAnswer)), \(js(bodyClass)));
            _queueAction(() => { bridgeCommand('reviewerReady'); requestAnimationFrame(() => requestAnimationFrame(() => bridgeCommand('renderDiagnostics'))); });
            """
            webView.evaluateJavaScript(source) { _, error in
                if let error { self.store.errorMessage = error.localizedDescription }
            }
        }

        private func runStateMutation(_ webView: WKWebView) {
            if let mutation {
                // WKWebView cannot marshal a Promise as an evaluation result.
                // An undefined result keeps that transport limitation from
                // being mistaken for a syntax/evaluation failure. The official
                // statesMutated command still completes the async operation.
                webView.evaluateJavaScript(mutation + "\nvoid(0);") { _, error in
                    // reviewer.py::_run_state_mutation_hook releases the
                    // answer buttons when evaluation fails (e.g. syntax).
                    if error != nil { self.store.reviewerStatesMutated() }
                }
            }
        }

        /// qt/aqt/reviewer.py::_redraw_current_card preserves the displayed side
        /// and scheduling states. Only question redraws rerun the mutation hook.
        func redraw(_ view: WKWebView, card: Flashcard) throws {
            textGeneration = store.reviewTextGeneration
            answer = try store.prepareCardTextForDisplay(card.back)
            prefetchAnswer = try store.escapeMediaFilenames(card.back)
            view.evaluateJavaScript("document.getElementById('card-style').textContent = \(js(card.css));")
            if requestedAnswer {
                answerShown = false
            } else {
                typed = try store.typedAnswer(for: card)
                question = typed!.question
                ready = false
                store.reviewerWillRedrawQuestion()
                runStateMutation(view)
                showQuestion(view)
            }
        }

        func showRequestedSide(_ view: WKWebView) {
            guard ready, requestedAnswer, !answerShown else { return }
            answerShown = true
            view.evaluateJavaScript("getTypedAnswer();") { value, error in
                do {
                    if let error { throw error }
                    guard let typed = self.typed else { return }
                    let html = try typed.answer(self.answer, provided: value as? String ?? "")
                    view.evaluateJavaScript("_showAnswer(\(self.js(html)), \(self.js(self.bodyClass))); _queueAction(() => requestAnimationFrame(() => bridgeCommand('renderDiagnostics')));") { _, error in
                        if let error { self.store.errorMessage = error.localizedDescription }
                    }
                } catch { self.store.errorMessage = self.store.errorText(error) }
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let command = message.body as? String else { return }
            guard !reviewing || isCurrentReviewer else { return }
            switch command {
            case "reviewerReady":
                ready = true
                if let view = message.webView { showRequestedSide(view) }
            case "statesMutated":
                if isCurrentReviewer { store.reviewerStatesMutated() }
                if let view = message.webView { diagnostics(view) }
            case "renderDiagnostics":
                if let view = message.webView { diagnostics(view) }
            case "ans": onShowAnswer?()
            default: if command.hasPrefix("play:") { playAudio?(command) }
            }
        }

        private func diagnostics(_ view: WKWebView) {
            #if DEBUG
            guard let path = ProcessInfo.processInfo.environment["OPENANKI_REVIEWER_DIAGNOSTICS_FILE"] else { return }
            if let side = ProcessInfo.processInfo.environment["OPENANKI_REVIEWER_DIAGNOSTICS_SIDE"],
               side != (requestedAnswer ? "answer" : "question") { return }
            let source = """
            (() => {
                const canvas = document.getElementById('image-occlusion-canvas');
                let maskPixels = 0;
                if (canvas && canvas.width && canvas.height) {
                    const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
                    for (let i = 3; i < pixels.length; i += 4) if (pixels[i]) maskPixels++;
                }
                return JSON.stringify({html: document.getElementById('qa').innerHTML,
                    documentClasses: document.documentElement.className, bodyClasses: document.body.className, theme: document.documentElement.dataset.bsTheme,
                    images: Array.from(document.querySelectorAll('#qa img')).map(image => ({src: image.getAttribute('src'), complete: image.complete, width: image.naturalWidth, height: image.naturalHeight})),
                    mathJaxCount: document.querySelectorAll('mjx-container').length,
                    canvasWidth: canvas?.width ?? 0, canvasHeight: canvas?.height ?? 0, maskPixels,
                    typedAnswer: getTypedAnswer(), reviewerLoaded: typeof anki.mutateNextCardStates === 'function'});
            })()
            """
            view.evaluateJavaScript(source) { result, _ in
                guard let string = result as? String, let data = string.data(using: .utf8),
                      var json = (try? JSONDecoder().decode(AnkiJSON.self, from: data))?.object else { return }
                json["queued"] = self.cardID == self.store.currentCard?.id ? self.store.reviewerDiagnostics : .null
                json["side"] = .string(self.answerShown ? "answer" : "question")
                json["documentIdentity"] = .string(self.documentIdentity)
                json["statesMutated"] = .bool(self.store.statesMutated)
                if let encoded = try? JSONEncoder().encode(AnkiJSON.object(json)) {
                    try? encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
                }
            }
            #endif
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            do {
                guard let body = message.body as? [String: String], let path = body["path"],
                      let encoded = body["data"], let data = Data(base64Encoded: encoded) else {
                    throw CollectionError.invalid("无法读取牌组。")
                }
                if path != "/_anki/i18nResources" && !isCurrentReviewer { throw CollectionError.invalid("无法读取牌组。") }
                replyHandler(try store.reviewerRequest(path: path, data: data).base64EncodedString(), nil)
            } catch { replyHandler(nil, store.errorText(error)) }
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            do {
                guard let url = urlSchemeTask.request.url else { throw URLError(.badURL) }
                let data: Data
                let mime: String
                if url.path == "/review.html" {
                    data = Data(document.utf8); mime = "text/html"
                } else {
                    let root: URL
                    let relative: String
                    if url.path.hasPrefix("/_anki/") {
                        root = AnkiWebResources.directory; relative = String(url.path.dropFirst("/_anki/".count))
                    } else {
                        guard let mediaURL else { throw URLError(.fileDoesNotExist) }
                        root = mediaURL; relative = String(url.path.dropFirst())
                    }
                    let file = root.appendingPathComponent(relative).standardizedFileURL
                    guard file.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw URLError(.noPermissionsToReadFile) }
                    data = try Data(contentsOf: file)
                    mime = AnkiWebFrontend.commonMimeType(for: file.path) ?? UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                }
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch { urlSchemeTask.didFailWithError(error) }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .other && navigationAction.request.url?.absoluteString == "openanki://reviewer/review.html" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            store.errorMessage = message
            completionHandler()
        }
    }
}
