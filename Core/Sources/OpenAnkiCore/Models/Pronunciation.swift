import Foundation

/// Read-only decoding of pronunciation metadata in old OpenAnki JSON archives.
/// New collections obtain audio and TTS tags from Anki's template renderer.
public struct Pronunciation: Codable, Hashable, Sendable {
    public var language: String
    public var word: String
    public var examples: [String]

    public init(language: String, word: String, examples: [String] = []) {
        self.language = language
        self.word = word
        self.examples = examples
    }
}
