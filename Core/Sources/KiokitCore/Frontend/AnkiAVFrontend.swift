// Adapted from ankitects/anki 26.09.3, qt/aqt/sound.py, qt/aqt/tts.py,
// and pylib/anki/template.py::av_tag_to_native.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

public struct AnkiTTSVoice: Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let language: String
    public init(identifier: String, name: String, language: String) { self.identifier = identifier; self.name = name; self.language = language }
}

public struct AnkiTTSVoiceMatch: Sendable {
    public let voice: AnkiTTSVoice
    public let rank: Int
}

/// Frontend classification and voice matching copied from Anki. Native media
/// decoders and device voice enumeration are platform bindings.
public enum AnkiAVFrontend {
    private static let audioExtensions: Set<String> = ["3gp", "flac", "m4a", "mp3", "oga", "ogg", "opus", "spx", "wav"]

    public static func isAudioFile(_ filename: String) -> Bool {
        audioExtensions.contains(String(filename.split(separator: ".", omittingEmptySubsequences: false).last ?? "").lowercased())
    }

    /// Anki's Python frontend applies os.path.basename to extracted sound tags.
    /// Splitting only '/' preserves POSIX behavior, including a trailing slash.
    public static func normalizedTag(_ value: AnkiJSON) -> AnkiJSON {
        guard !value["soundOrVideo"].isNull else { return value }
        var tag = value.object
        tag["soundOrVideo"] = .string(String(value["soundOrVideo"].string.split(separator: "/", omittingEmptySubsequences: false).last ?? ""))
        return .object(tag)
    }

    public static func voice(for tag: AnkiAudioTag, available: [AnkiTTSVoice], defaultRank: Int = 0) -> AnkiTTSVoiceMatch? {
        guard let language = tag.language else { return nil }
        var rank = defaultRank
        for requested in tag.voices {
            for voice in available where voice.name == requested && voice.language == language {
                return AnkiTTSVoiceMatch(voice: voice, rank: rank)
            }
            rank -= 1
        }
        for voice in available where voice.language == language {
            if voice.language == "en_US" && voice.name.hasPrefix("Apple_Samantha") {
                return AnkiTTSVoiceMatch(voice: voice, rank: -50)
            }
        }
        for voice in available where voice.language == language { return AnkiTTSVoiceMatch(voice: voice, rank: -100) }
        return nil
    }
}
