import Foundation
import CSQLite
import ZIPFoundation
import libzstd

public enum DeckImporter {
    public static func load(url: URL) throws -> ImportedCollection {
        switch url.pathExtension.lowercased() {
        case "apkg": return try AnkiPackageImporter.load(url: url)
        case "openanki", "zip": return try loadBackup(url: url)
        case "json":
            let snapshot = try JSONDecoder().decode(CollectionSnapshot.self, from: Data(contentsOf: url))
            try snapshot.validate()
            guard snapshot.cards.allSatisfy({ $0.mediaFolder == nil }) else { throw CollectionError.invalid("带媒体的备份请使用 .openanki 文件恢复。") }
            return ImportedCollection(snapshot: snapshot, isBackup: true)
        case "csv", "tsv", "txt":
            return try TextDeckImporter.load(data: Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
        default: throw CollectionError.invalid("请选择 .apkg 牌组、CSV/TSV 文本或 .openanki 备份。")
        }
    }

    private static func loadBackup(url: URL) throws -> ImportedCollection {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["collection.json"] else { throw CollectionError.invalid("此文件不是 OpenAnki 备份。") }
        let snapshot = try JSONDecoder().decode(CollectionSnapshot.self, from: archive.readData(entry))
        try snapshot.validate()
        let staging = try makeStagingDirectory()
        do {
            let folders = Set(snapshot.cards.compactMap(\.mediaFolder))
            var total = 0
            for entry in archive where entry.type == .file && entry.path.hasPrefix("Media/") {
                let components = entry.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard components.count == 3, components[0] == "Media", components.dropFirst().allSatisfy(CollectionSnapshot.safeComponent) else {
                    throw CollectionError.invalid("备份包含无效的媒体路径。")
                }
                guard folders.contains(components[1]) else { continue }
                let data = try archive.readData(entry, limit: 64 * 1024 * 1024)
                total += data.count
                guard total <= 1_073_741_824 else { throw CollectionError.invalid("媒体总大小超过 1 GB。") }
                let target = staging.appendingPathComponent(entry.path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
            }
            for folder in folders {
                try FileManager.default.createDirectory(at: staging.appendingPathComponent("Media/\(folder)"), withIntermediateDirectories: true)
            }
            return ImportedCollection(snapshot: snapshot, stagingDirectory: staging, isBackup: true)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}

private func makeStagingDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenAnki-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension Archive {
    func readData(_ entry: Entry, limit: Int = 256 * 1024 * 1024) throws -> Data {
        guard entry.uncompressedSize <= limit else { throw CollectionError.invalid("牌组中的文件过大。") }
        var data = Data()
        _ = try extract(entry) { chunk in
            guard data.count + chunk.count <= limit else { throw CollectionError.invalid("文件超过大小限制。") }
            data.append(chunk)
        }
        return data
    }
}

private enum Zstandard {
    static func decode(_ data: Data, limit: Int = 256 * 1024 * 1024) throws -> Data {
        guard let stream = ZSTD_createDStream() else { throw CollectionError.invalid("无法创建解压器。") }
        defer { ZSTD_freeDStream(stream) }
        guard ZSTD_isError(ZSTD_initDStream(stream)) == 0 else { throw CollectionError.invalid("无法初始化解压器。") }
        return try data.withUnsafeBytes { raw in
            var input = ZSTD_inBuffer(src: raw.baseAddress, size: raw.count, pos: 0)
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var remaining = 1
            while input.pos < input.size || remaining != 0 {
                let prior = input.pos
                let produced: Int = try buffer.withUnsafeMutableBytes { outputBytes in
                    var output = ZSTD_outBuffer(dst: outputBytes.baseAddress, size: outputBytes.count, pos: 0)
                    remaining = ZSTD_decompressStream(stream, &output, &input)
                    guard ZSTD_isError(remaining) == 0 else { throw CollectionError.invalid("Zstandard 压缩数据已损坏。") }
                    return output.pos
                }
                guard result.count + produced <= limit else { throw CollectionError.invalid("解压后的文件过大。") }
                result.append(contentsOf: buffer.prefix(produced))
                guard input.pos > prior || produced > 0 else { throw CollectionError.invalid("压缩数据不完整。") }
            }
            guard remaining == 0 else { throw CollectionError.invalid("压缩数据不完整。") }
            return result
        }
    }
}

/// Reads the small subset of protobuf fields used by Anki's file format.
/// Unknown fields are skipped; malformed wire data is rejected.
private struct ProtoField {
    var number: Int
    var integer: UInt64?
    var bytes: Data?
}

private enum Protobuf {
    static func fields(_ data: Data) throws -> [ProtoField] {
        let bytes = [UInt8](data)
        var position = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for shift in stride(from: 0, to: 70, by: 7) {
                guard position < bytes.count else { throw CollectionError.invalid("Protobuf 数据不完整。") }
                let byte = bytes[position]
                position += 1
                if shift == 63 && byte > 1 { throw CollectionError.invalid("Protobuf 数值溢出。") }
                result |= UInt64(byte & 0x7f) << shift
                if byte < 128 { return result }
            }
            throw CollectionError.invalid("Protobuf 数值无效。")
        }
        var result: [ProtoField] = []
        while position < bytes.count {
            let key = try varint()
            guard key >> 3 > 0 else { throw CollectionError.invalid("Protobuf 字段无效。") }
            var field = ProtoField(number: Int(key >> 3))
            switch key & 7 {
            case 0: field.integer = try varint()
            case 1: position += 8
            case 2:
                let length = try varint()
                guard length <= bytes.count - position else { throw CollectionError.invalid("Protobuf 长度无效。") }
                field.bytes = Data(bytes[position..<(position + Int(length))])
                position += Int(length)
            case 5: position += 4
            default: throw CollectionError.invalid("不支持的 Protobuf 编码。")
            }
            guard position <= bytes.count else { throw CollectionError.invalid("Protobuf 数据不完整。") }
            result.append(field)
        }
        return result
    }

    static func string(_ fields: [ProtoField], _ number: Int) -> String {
        fields.first(where: { $0.number == number })?.bytes.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

private final class SQLiteReader {
    private var database: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            database = nil
            throw CollectionError.invalid("无法读取牌组数据库。")
        }
    }

    deinit { sqlite3_close(database) }

    func rows(_ sql: String, each: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CollectionError.invalid("牌组数据库结构不受支持：\(String(cString: sqlite3_errmsg(database)))")
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw CollectionError.invalid("牌组数据库已损坏。") }
            try each(statement)
        }
    }

    static func text(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }

    static func blob(_ row: OpaquePointer, _ column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(row, column) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(row, column)))
    }
}

private struct NoteModel {
    var fields: [String] = []
    var templates: [Int: (front: String, back: String)] = [:]
    var css: String = ""
    var isCloze = false
    var unsupported = false
}

public enum AnkiPackageImporter {
    public static func load(url: URL) throws -> ImportedCollection {
        let archive = try Archive(url: url, accessMode: .read)
        let modern = archive["collection.anki21b"] != nil
        if let meta = archive["meta"] {
            let version = try Protobuf.fields(archive.readData(meta)).first(where: { $0.number == 1 })?.integer
            guard version == 3 else { throw CollectionError.invalid("此 Anki 牌组版本暂不受支持。") }
        }
        let filename = modern ? "collection.anki21b" : (archive["collection.anki21"] != nil ? "collection.anki21" : "collection.anki2")
        guard let entry = archive[filename] else { throw CollectionError.invalid("文件中没有 Anki 牌组数据库。") }
        let staging = try makeStagingDirectory()
        do {
            var data = try archive.readData(entry)
            if modern { data = try Zstandard.decode(data) }
            let databaseURL = staging.appendingPathComponent("import.sqlite")
            try data.write(to: databaseURL)
            let database = try SQLiteReader(url: databaseURL)
            var deckNames: [Int64: String] = [:]
            var models: [Int64: NoteModel] = [:]
            var schema = 0
            try database.rows("SELECT ver FROM col LIMIT 1") { schema = Int(sqlite3_column_int($0, 0)) }
            if schema >= 15 {
                guard schema <= 18 else { throw CollectionError.invalid("此 Anki 数据库版本暂不受支持。") }
                try database.rows("SELECT id, name FROM decks") {
                    deckNames[sqlite3_column_int64($0, 0)] = SQLiteReader.text($0, 1).replacingOccurrences(of: "\u{1f}", with: "::")
                }
                try database.rows("SELECT id, name, config FROM notetypes") { row in
                    let config = try Protobuf.fields(SQLiteReader.blob(row, 2))
                    var model = NoteModel()
                    model.css = Protobuf.string(config, 3)
                    model.isCloze = config.first(where: { $0.number == 1 })?.integer == 1
                    model.unsupported = config.first(where: { $0.number == 9 })?.integer == 6
                    models[sqlite3_column_int64(row, 0)] = model
                }
                try database.rows("SELECT ntid, ord, name FROM fields ORDER BY ntid, ord") { row in
                    models[sqlite3_column_int64(row, 0)]?.fields.append(SQLiteReader.text(row, 2))
                }
                try database.rows("SELECT ntid, ord, config FROM templates") { row in
                    let config = try Protobuf.fields(SQLiteReader.blob(row, 2))
                    models[sqlite3_column_int64(row, 0)]?.templates[Int(sqlite3_column_int(row, 1))] = (Protobuf.string(config, 1), Protobuf.string(config, 2))
                }
            } else {
                try database.rows("SELECT decks, models FROM col LIMIT 1") { row in
                    guard let decks = try JSONSerialization.jsonObject(with: Data(SQLiteReader.text(row, 0).utf8)) as? [String: [String: Any]],
                          let rawModels = try JSONSerialization.jsonObject(with: Data(SQLiteReader.text(row, 1).utf8)) as? [String: [String: Any]] else {
                        throw CollectionError.invalid("牌组模板数据无效。")
                    }
                    for (key, value) in decks {
                        if let id = Int64(key) { deckNames[id] = value["name"] as? String ?? "导入牌组" }
                    }
                    for (key, value) in rawModels {
                        guard let id = Int64(key) else { continue }
                        var model = NoteModel()
                        model.css = value["css"] as? String ?? ""
                        model.isCloze = (value["type"] as? Int) == 1
                        model.unsupported = (value["name"] as? String ?? "").lowercased().contains("image occlusion")
                        model.fields = (value["flds"] as? [[String: Any]] ?? []).sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }.map { $0["name"] as? String ?? "" }
                        for template in value["tmpls"] as? [[String: Any]] ?? [] {
                            model.templates[template["ord"] as? Int ?? 0] = (template["qfmt"] as? String ?? "", template["afmt"] as? String ?? "")
                        }
                        models[id] = model
                    }
                }
            }
            var snapshot = CollectionSnapshot()
            var deckMap: [Int64: UUID] = [:]
            let folder = UUID().uuidString
            var skipped = 0
            var hasCustomScript = false
            try database.rows("SELECT c.did, c.ord, n.guid, n.mid, n.flds, n.tags, c.queue FROM cards c JOIN notes n ON n.id = c.nid ORDER BY c.id") { row in
                guard snapshot.cards.count < 100_000 else { throw CollectionError.invalid("单个牌组包超过 100,000 张卡片。") }
                let sourceDeck = sqlite3_column_int64(row, 0)
                let ordinal = Int(sqlite3_column_int(row, 1))
                let modelID = sqlite3_column_int64(row, 3)
                guard let model = models[modelID], !model.unsupported,
                      let template = model.templates[model.isCloze ? 0 : ordinal] else { skipped += 1; return }
                if deckMap[sourceDeck] == nil {
                    let deck = Deck(name: deckNames[sourceDeck] ?? "导入牌组", colorIndex: snapshot.decks.count % 5)
                    snapshot.decks.append(deck)
                    deckMap[sourceDeck] = deck.id
                }
                let values = SQLiteReader.text(row, 4).components(separatedBy: "\u{1f}")
                var fields = Dictionary(zip(model.fields, values), uniquingKeysWith: { _, last in last })
                fields["Deck"] = deckNames[sourceDeck] ?? "导入牌组"
                fields["Subdeck"] = fields["Deck"]?.components(separatedBy: "::").last ?? ""
                fields["Tags"] = SQLiteReader.text(row, 5)
                fields["Card"] = "\(ordinal + 1)"
                let front = TemplateRenderer.render(template.front, fields: fields, ordinal: ordinal, answer: false)
                let back = TemplateRenderer.render(template.back, fields: fields, ordinal: ordinal, answer: true, frontSide: TemplateRenderer.render(template.front, fields: fields, ordinal: ordinal, answer: true))
                hasCustomScript = hasCustomScript || (front + back).lowercased().contains("<script")
                var card = Flashcard(deckID: deckMap[sourceDeck]!, front: front, back: back,
                                     tags: SQLiteReader.text(row, 5).split(whereSeparator: \.isWhitespace).map(String.init),
                                     isHTML: true, css: model.css, mediaFolder: folder,
                                     sourceKey: "anki:\(SQLiteReader.text(row, 2)):\(ordinal)")
                card.isSuspended = sqlite3_column_int(row, 6) == -1
                card.pronunciation = Pronunciation.japanese(fields: fields)
                snapshot.cards.append(card)
            }
            guard !snapshot.cards.isEmpty else { throw CollectionError.invalid(skipped > 0 ? "牌组中仅包含暂不支持的卡片模板（如图像遮挡）。" : "牌组中没有卡片。") }
            let destination = staging.appendingPathComponent("Media/\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var mediaNames: [(String, String)] = []
            if let media = archive["media"] {
                var mediaData = try archive.readData(media, limit: 32 * 1024 * 1024)
                if modern {
                    mediaData = try Zstandard.decode(mediaData, limit: 32 * 1024 * 1024)
                    let entries = try Protobuf.fields(mediaData).filter { $0.number == 1 }
                    for (index, field) in entries.enumerated() {
                        guard let bytes = field.bytes else { continue }
                        let fields = try Protobuf.fields(bytes)
                        mediaNames.append((String(index), Protobuf.string(fields, 1)))
                    }
                } else {
                    guard let map = try JSONSerialization.jsonObject(with: mediaData) as? [String: String] else { throw CollectionError.invalid("媒体列表无效。") }
                    mediaNames = map.map { ($0.key, $0.value) }
                }
            }
            guard mediaNames.count <= 20_000 else { throw CollectionError.invalid("媒体文件数量超过 20,000。") }
            var total = 0
            for (key, name) in mediaNames {
                guard Int(key) != nil, CollectionSnapshot.safeComponent(name), let file = archive[key] else {
                    throw CollectionError.invalid("媒体列表包含无效路径或缺失文件。")
                }
                var media = try archive.readData(file, limit: 64 * 1024 * 1024)
                if modern { media = try Zstandard.decode(media, limit: 64 * 1024 * 1024) }
                total += media.count
                guard total <= 1_073_741_824 else { throw CollectionError.invalid("媒体总大小超过 1 GB。") }
                try media.write(to: destination.appendingPathComponent(name))
            }
            var warnings: [LocalizedMessage] = []
            if skipped > 0 { warnings.append("跳过 \(skipped) 张不支持的模板卡片（如图像遮挡）。") }
            if hasCustomScript { warnings.append("自定义模板的 JavaScript 不会执行，相关交互可能无法显示。") }
            try snapshot.validate()
            return ImportedCollection(snapshot: snapshot, stagingDirectory: staging, warnings: warnings)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
