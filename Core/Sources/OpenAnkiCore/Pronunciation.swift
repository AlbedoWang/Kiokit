import Foundation

public struct Pronunciation: Codable, Hashable, Sendable {
    public var language: String
    public var word: String
    public var examples: [String]

    public init(language: String, word: String, examples: [String] = []) {
        self.language = language
        self.word = word
        self.examples = examples
    }

    public static func japanese(fields: [String: String]) -> Pronunciation? {
        guard let kana = fields["假名"], !kana.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let word = speechText(kana)
        guard !word.isEmpty else { return nil }
        let exampleText = TemplateRenderer.plainText(fields["例句"] ?? "")
        let examples = exampleText.components(separatedBy: "△")
            .flatMap { $0.components(separatedBy: .newlines) }
            .compactMap { line -> String? in
                // N4 stores Japanese / Chinese translation on the same line.
                let japanese = speechText(line.components(separatedBy: "/").first ?? "")
                return japanese.isEmpty ? nil : japanese
            }
        return Pronunciation(language: "ja-JP", word: word, examples: examples)
    }

    private static func speechText(_ html: String) -> String {
        TemplateRenderer.plainText(html)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CardAudio {
    private static let pattern = #"\[sound:([^\]]+)\]"#

    public static func filenames(in html: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            guard let range = Range($0.range(at: 1), in: html) else { return nil }
            let name = String(html[range])
            guard CollectionSnapshot.safeComponent(name), seen.insert(name).inserted else { return nil }
            return name
        }
    }

    public static func removingSoundMarkers(from html: String) -> String {
        html.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
