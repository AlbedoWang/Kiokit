import Foundation

public enum TextDeckImporter {
    public static func load(data: Data, name: String) throws -> ImportedCollection {
        guard data.count <= 32 * 1024 * 1024, var text = String(data: data, encoding: .utf8) else {
            throw CollectionError.invalid("请使用小于 32 MB 的 UTF-8 文本文件。")
        }
        text = text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var html = false
        var deckName = name
        var forcedDelimiter: Character?
        while text.hasPrefix("#") {
            let line = String(text.prefix(while: { $0 != "\n" }))
            if line.lowercased().hasPrefix("#html:") { html = line.lowercased().contains("true") }
            if line.lowercased().hasPrefix("#deck:") { deckName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            if line.lowercased().hasPrefix("#separator:") {
                switch line.dropFirst(11).lowercased() {
                case "tab": forcedDelimiter = "\t"
                case "comma": forcedDelimiter = ","
                case "semicolon": forcedDelimiter = ";"
                case "pipe": forcedDelimiter = "|"
                default: break
                }
            }
            text = String(text.dropFirst(min(text.count, line.count + 1)))
        }
        let firstLine = text.prefix(while: { $0 != "\n" })
        let delimiter = forcedDelimiter ?? (firstLine.contains("\t") ? "\t" : ",")
        var rows = try parse(text, delimiter: delimiter)
        if let first = rows.first, first.count >= 2,
           ["front", "正面", "question"].contains(first[0].lowercased()),
           ["back", "背面", "answer"].contains(first[1].lowercased()) { rows.removeFirst() }
        let deck = Deck(name: deckName.isEmpty ? "导入牌组" : deckName)
        var cards: [Flashcard] = []
        for (index, row) in rows.enumerated() where !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            guard row.count >= 2, !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !row[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CollectionError.invalid("第 \(index + 1) 条记录缺少正面或背面；文本格式应为「正面、背面、标签（可选）」。")
            }
            cards.append(Flashcard(deckID: deck.id, front: row[0], back: row[1], tags: row.count > 2 ? row[2].split(whereSeparator: \.isWhitespace).map(String.init) : [], isHTML: html))
        }
        guard !cards.isEmpty else { throw CollectionError.invalid("文件中没有可导入的卡片。") }
        return ImportedCollection(snapshot: CollectionSnapshot(decks: [deck], cards: cards))
    }

    private static func parse(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if quoted && index + 1 < chars.count && chars[index + 1] == "\"" {
                    cell.append("\"")
                    index += 1
                } else if quoted || cell.isEmpty { quoted.toggle() }
                else { cell.append(char) }
            } else if char == delimiter && !quoted {
                row.append(cell)
                cell = ""
            } else if char == "\n" && !quoted {
                row.append(cell)
                rows.append(row)
                guard rows.count <= 100_000 else { throw CollectionError.invalid("文本超过 100,000 条记录。") }
                row = []
                cell = ""
            } else { cell.append(char) }
            index += 1
        }
        guard !quoted else { throw CollectionError.invalid("文本包含未闭合的引号。") }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}
