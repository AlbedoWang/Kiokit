// Adapted from ankitects/anki 26.09.3:
// pylib/anki/sound.py::AV_REF_RE, strip_av_refs
// qt/aqt/sound.py::av_refs_to_play_icons
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

/// Faithful translations of Anki's frontend audio-reference handling. The
/// platform web view provides the pycmd bridge to the native audio player.
public enum AnkiFrontend {
    private static let references = try! NSRegularExpression(pattern: #"\[anki:(play:(.):(\d+))\]"#)

    public static func stripAudioReferences(_ text: String) -> String {
        references.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    public static func audioReferencesToPlayIcons(_ text: String) -> String {
        let replacement = """

        <a class="replay-button soundLink" href=# onclick="pycmd('$1'); return false;" draggable="false">
            <svg class="playImage" viewBox="0 0 64 64" version="1.1">
                <circle cx="32" cy="32" r="29" />
                <path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z" />
            </svg>
        </a>
        """
        return references.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
