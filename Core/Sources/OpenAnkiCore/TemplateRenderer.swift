import Foundation

public enum TemplateRenderer {
    public static func render(_ template: String, fields: [String: String], ordinal: Int, answer: Bool, frontSide: String = "") -> String {
        var result = template
        // Process conditional sections before substituting fields.
        let section = try! NSRegularExpression(pattern: #"\{\{([#^])([^{}]+)\}\}([\s\S]*?)\{\{/\2\}\}"#)
        for _ in 0..<32 {
            let matches = section.matches(in: result, range: NSRange(result.startIndex..., in: result))
            if matches.isEmpty { break }
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let kindRange = Range(match.range(at: 1), in: result),
                      let nameRange = Range(match.range(at: 2), in: result),
                      let bodyRange = Range(match.range(at: 3), in: result) else { continue }
                let name = String(result[nameRange]).trimmingCharacters(in: .whitespaces)
                let populated = !(fields[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let include = result[kindRange] == "#" ? populated : !populated
                result.replaceSubrange(range, with: include ? String(result[bodyRange]) : "")
            }
        }
        let token = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
        for match in token.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result), let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange]).trimmingCharacters(in: .whitespaces)
            let parts = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let name = parts.last ?? key
            var value = key == "FrontSide" ? frontSide : (fields[name] ?? "")
            for filter in parts.dropLast().reversed() {
                switch filter {
                case "cloze": value = cloze(value, ordinal: ordinal, answer: answer)
                case "text": value = escape(plainText(value))
                case "type": value = answer ? value : "<span class='type-hint'>在心中输入答案</span>"
                case "furigana": value = furigana(value)
                case "hint": value = "<details><summary>显示「\(escape(name))」提示</summary>\(value)</details>"
                default: break
                }
            }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    public static func cloze(_ value: String, ordinal: Int, answer: Bool) -> String {
        var result = value
        let regex = try! NSRegularExpression(pattern: #"\{\{c(\d+)::([\s\S]*?)\}\}"#)
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result), let number = Range(match.range(at: 1), in: result), let content = Range(match.range(at: 2), in: result) else { continue }
            let pieces = String(result[content]).components(separatedBy: "::")
            let text = pieces[0]
            let active = Int(result[number]) == ordinal + 1
            let replacement: String
            if active {
                replacement = answer ? "<span class='cloze'>\(text)</span>" : "<span class='cloze'>[\(pieces.count > 1 ? pieces[1] : "…")]</span>"
            } else {
                replacement = text
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    public static func furigana(_ value: String) -> String {
        var result = value
        let regex = try! NSRegularExpression(pattern: #"([^\s<>\[\]]+)\[([^\[\]]+)\]"#)
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result),
                  let base = Range(match.range(at: 1), in: result),
                  let reading = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(range, with: "<ruby>\(result[base])<rt>\(result[reading])</rt></ruby>")
        }
        return result
    }

    public static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:div|p|li)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[sound:[^\]]+\]"#, with: "[音频]", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func htmlWithAudio(_ html: String) -> String {
        var result = html
        let regex = try! NSRegularExpression(pattern: #"\[sound:([^\]]+)\]"#)
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result), let nameRange = Range(match.range(at: 1), in: result) else { continue }
            let name = String(result[nameRange])
            guard CollectionSnapshot.safeComponent(name) else { result.replaceSubrange(range, with: ""); continue }
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            result.replaceSubrange(range, with: "<audio controls preload='metadata' src='\(escape(encoded))'></audio>")
        }
        return result
    }
}
