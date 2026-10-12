// Adapted from ankitects/anki 26.09.3, qt/aqt/mediasrv.py and webview.py.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

/// Shared frontend resource rules. Unknown MIME types are resolved by the
/// platform, as upstream falls back to its operating system's MIME database.
public enum AnkiWebFrontend {
    private static let mimeTypes = [
        "css": "text/css", "js": "application/javascript", "mjs": "application/javascript",
        "html": "text/html", "htm": "text/html", "svg": "image/svg+xml", "png": "image/png",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
        "ico": "image/x-icon", "json": "application/json", "woff": "font/woff", "woff2": "font/woff2",
        "ttf": "font/ttf", "otf": "font/otf", "mp3": "audio/mpeg", "mp4": "video/mp4",
        "webm": "video/webm", "ogg": "audio/ogg", "pdf": "application/pdf", "txt": "text/plain",
    ]
    private static let svelteCSP = try! NSRegularExpression(pattern: #"<meta http-equiv="content-security-policy" content="script-src 'self' ('sha256-[A-Za-z0-9+/=]+')">"#)

    public static func commonMimeType(for path: String) -> String? {
        mimeTypes[(path as NSString).pathExtension.lowercased()]
    }

    /// Trusted SvelteKit pages use mediasrv.py::_strip_csp_meta before the
    /// platform supplies its content policy. Bundled files remain unmodified.
    public static func trustedSvelteHTML(_ html: String) throws -> String {
        guard svelteCSP.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil else {
            throw AnkiBackendError(message: "CSP meta tag not found in SvelteKit index page", kind: "TRANSPORT")
        }
        return svelteCSP.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
    }

    /// qt/aqt/webview.py::on_theme_did_change. iOS provides the theme state;
    /// the upstream document and legacy body classes are preserved.
    public static func themeUpdateJavaScript(nightMode: Bool, macOSDarkMode: Bool = false) -> String {
        """

        (function() {
            const doc = document.documentElement;
            const body = document.body.classList;
            if (\(nightMode ? 1 : 0)) {
                doc.dataset.bsTheme = "dark";
                doc.classList.add("night-mode");
                body.add("night_mode");
                body.add("nightMode");
                \(macOSDarkMode ? "body.add('macos-dark-mode');" : "")
            } else {
                doc.dataset.bsTheme = "light";
                doc.classList.remove("night-mode");
                body.remove("night_mode");
                body.remove("nightMode");
                body.remove("macos-dark-mode");
            }
        })();

        """
    }
}
