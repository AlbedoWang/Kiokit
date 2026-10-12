import SwiftUI
import WebKit
import KiokitCore

/// Separate WebKit document for Anki's unmodified bottom-bar timer. Like Qt's
/// ReviewerBottomBar, its globals never share the card template's namespace.
struct AnkiReviewTimerWebView: UIViewRepresentable {
    @Environment(CollectionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let card: Flashcard
    let answer: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "openanki")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "reviewTimer"
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.maxTime = card.ankiDeckConfiguration?["maxTaken"].int ?? 0
        coordinator.requestedAnswer = answer
        coordinator.stopOnAnswer = card.ankiDeckConfiguration?["stopTimerOnAnswer"].bool ?? false
        coordinator.statesMutated = store.statesMutated
        let dark = colorScheme == .dark
        if coordinator.generation != store.reviewGeneration {
            coordinator.generation = store.reviewGeneration
            coordinator.textGeneration = store.reviewTextGeneration
            coordinator.dark = dark
            coordinator.ready = false
            coordinator.answerShown = false
            coordinator.document = """
            <!doctype html><html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src openanki:; style-src 'unsafe-inline';">
            <style>body { margin: 0; color: \(dark ? "#a8a69e" : "#7b7974"); font: 14px -apple-system, sans-serif; text-align: right; }</style>
            </head><body><div id="middle" hidden></div><span id="time" role="timer"></span>
            <script src="/_anki/js/reviewer-bottom.js"></script></body></html>
            """
            view.load(URLRequest(url: URL(string: "openanki://review-timer/timer.html")!))
        } else if coordinator.ready {
            if coordinator.dark != dark {
                coordinator.dark = dark
                view.evaluateJavaScript("document.body.style.color = '\(dark ? "#a8a69e" : "#7b7974")';")
            }
            if coordinator.textGeneration != store.reviewTextGeneration {
                coordinator.textGeneration = store.reviewTextGeneration
                coordinator.update(view, redraw: true)
            } else {
                coordinator.update(view, redraw: false)
            }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.diagnosticsTimer?.invalidate()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
        var document = ""
        var generation = -1
        var textGeneration = -1
        var dark = false
        var maxTime: Int64 = 0
        var requestedAnswer = false
        var answerShown = false
        var stopOnAnswer = false
        var statesMutated = true
        var ready = false
        var diagnosticsTimer: Timer?

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            view.evaluateJavaScript("showQuestion('', \(maxTime));")
            update(view, redraw: false)
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["OPENANKI_TIMER_DIAGNOSTICS_FILE"] {
                diagnosticsTimer?.invalidate()
                diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak view] _ in
                    Task { @MainActor [weak view] in
                        view?.evaluateJavaScript("JSON.stringify({text: document.getElementById('time').textContent, time, maxTime, timerStopped})") { value, _ in
                            if let value = value as? String { try? Data(value.utf8).write(to: URL(fileURLWithPath: path), options: .atomic) }
                        }
                    }
                }
            }
            #endif
        }

        func update(_ view: WKWebView, redraw: Bool) {
            // qt/aqt/reviewer.py::_showEaseButtons waits for state mutation
            // before invoking the bottom bar's showAnswer/stopTimerOnAnswer.
            if requestedAnswer {
                guard statesMutated, !answerShown || redraw else { return }
                view.evaluateJavaScript("showAnswer('', \(stopOnAnswer ? "true" : "false"));")
                answerShown = true
            } else if answerShown || redraw {
                view.evaluateJavaScript("showQuestion('', \(maxTime));")
                answerShown = false
            }
        }

        func webView(_ view: WKWebView, start task: WKURLSchemeTask) {
            do {
                guard let url = task.request.url else { throw URLError(.badURL) }
                let data: Data
                let mime: String
                if url.path == "/timer.html" { data = Data(document.utf8); mime = "text/html" }
                else if url.path == "/_anki/js/reviewer-bottom.js" {
                    data = try Data(contentsOf: AnkiWebResources.directory.appendingPathComponent("js/reviewer-bottom.js"))
                    mime = "application/javascript"
                } else { throw URLError(.fileDoesNotExist) }
                task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
                task.didReceive(data)
                task.didFinish()
            } catch { task.didFailWithError(error) }
        }

        func webView(_ view: WKWebView, stop task: WKURLSchemeTask) {}
        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.absoluteString == "openanki://review-timer/timer.html" ? .allow : .cancel)
        }
    }
}
