// Adapted from ankitects/anki 26.09.3, qt/aqt/reviewer.py:
// typeAnsQuestionFilter, typeAnsAnswerFilter, _contentForCloze.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

/// Anki's reviewer input handling. Cloze extraction and answer comparison are
/// performed by the upstream backend, including Unicode/combining behavior.
public final class AnkiTypedAnswer {
    private static let pattern = try! NSRegularExpression(pattern: #"\[\[type:(.+?)\]\]"#)
    private let backend: AnkiBackend
    private var correct: String?
    private var combining = true
    private var font = ""
    private var size: Int64 = 0
    public let question: String
    public let cardOrdinal: Int64

    public init(backend: AnkiBackend, question: String, fields: AnkiJSON, values: AnkiJSON, cardOrdinal: Int64) throws {
        self.backend = backend
        self.cardOrdinal = cardOrdinal
        guard let match = Self.pattern.firstMatch(in: question, range: NSRange(question.startIndex..., in: question)),
              let range = Range(match.range(at: 1), in: question) else {
            self.question = question
            return
        }
        var field = String(question[range])
        var clozeOrdinal: Int64?
        if field.hasPrefix("cloze:") {
            clozeOrdinal = cardOrdinal + 1
            field = String(field.split(separator: ":", omittingEmptySubsequences: false)[1])
        }
        if field.hasPrefix("nc:") {
            combining = false
            field = String(field.split(separator: ":", omittingEmptySubsequences: false)[1])
        }
        for (index, definition) in fields.array.enumerated() where definition["name"].string == field {
            correct = values.array[index].string
            if let clozeOrdinal {
                let extracted = try backend.call("anki.card_rendering.ExtractClozeForTyping", ["text": .string(correct!), "ordinal": .integer(clozeOrdinal)])["val"].string
                correct = extracted.isEmpty ? nil : extracted
            }
            font = definition["config"]["fontName"].string
            size = definition["config"]["fontSize"].int
            break
        }
        if correct == nil {
            // IDs come from upstream generated/_fluent.py at the pinned revision.
            let warning = try backend.call("anki.i18n.TranslateString", [
                "moduleIndex": 33, "messageIndex": .integer(clozeOrdinal == nil ? 45 : 34),
                "args": clozeOrdinal == nil ? ["val": ["str": .string(field)]] : [:],
            ])["val"].string
            self.question = Self.replace(in: question, with: warning)
        } else if correct!.isEmpty {
            self.question = Self.replace(in: question, with: "")
        } else {
            self.question = Self.replace(in: question, with: """

            <center>
            <input type=text id=typeans onkeypress="_typeAnsPress();"
               style="font-family: '\(font)'; font-size: \(size)px;">
            </center>

            """)
        }
    }

    public func answer(_ html: String, provided: String) throws -> String {
        guard let correct, !correct.isEmpty else { return Self.replace(in: html, with: "") }
        let stripped = html.replacingOccurrences(of: "<hr id=answer>", with: "")
        let hadHR = stripped.count != html.count
        let output = try backend.call("anki.card_rendering.CompareAnswer", ["expected": .string(correct), "provided": .string(provided), "combining": .bool(combining)])["val"].string
        let replacement = (hadHR ? "<hr id=answer>" : "") + "\n<div style=\"font-family: '\(font)'; font-size: \(size)px\">\(output)</div>"
        if hadHR && Self.pattern.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) == nil { return html }
        return Self.replace(in: stripped, with: replacement)
    }

    private static func replace(in text: String, with replacement: String) -> String {
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}
