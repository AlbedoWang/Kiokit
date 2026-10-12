import Foundation
import ZIPFoundation

public struct ImportedCollection: Sendable {
    public var snapshot: CollectionSnapshot
    public var stagingDirectory: URL?
    public var warnings: [String]
    public var isBackup: Bool

    public init(snapshot: CollectionSnapshot, stagingDirectory: URL? = nil, warnings: [String] = [], isBackup: Bool = false) {
        self.snapshot = snapshot
        self.stagingDirectory = stagingDirectory
        self.warnings = warnings
        self.isBackup = isBackup
    }

    public func cleanup() {
        if let stagingDirectory { try? FileManager.default.removeItem(at: stagingDirectory) }
    }
}

public struct CollectionRepository: Sendable {
    public let directory: URL
    public var collectionURL: URL { directory.appendingPathComponent("collection.json") }
    public var mediaURL: URL { directory.appendingPathComponent("Media", isDirectory: true) }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> CollectionSnapshot? {
        guard FileManager.default.fileExists(atPath: collectionURL.path) else { return nil }
        let snapshot = try JSONDecoder().decode(CollectionSnapshot.self, from: Data(contentsOf: collectionURL))
        try snapshot.validate()
        return snapshot
    }

    public func save(_ snapshot: CollectionSnapshot) throws {
        try snapshot.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: collectionURL, options: .atomic)
    }

    /// Media is installed before committing the snapshot. A failed commit removes
    /// any newly installed folders and leaves the prior collection untouched.
    public func commit(_ imported: ImportedCollection, snapshot: CollectionSnapshot) throws {
        try snapshot.validate()
        let manager = FileManager.default
        var installed: [URL] = []
        do {
            if let staging = imported.stagingDirectory {
                let source = staging.appendingPathComponent("Media", isDirectory: true)
                if manager.fileExists(atPath: source.path) {
                    try manager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
                    for folder in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                        guard CollectionSnapshot.safeComponent(folder.lastPathComponent) else { throw CollectionError.invalid("媒体路径无效。") }
                        let target = mediaURL.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                        if !manager.fileExists(atPath: target.path) {
                            try manager.copyItem(at: folder, to: target)
                            installed.append(target)
                        }
                    }
                }
            }
            if imported.isBackup, manager.fileExists(atPath: collectionURL.path) {
                try Data(contentsOf: collectionURL).write(to: directory.appendingPathComponent("collection.previous.json"), options: .atomic)
            }
            try save(snapshot)
        } catch {
            for url in installed { try? manager.removeItem(at: url) }
            throw error
        }
    }

    public func backup(_ snapshot: CollectionSnapshot) throws -> Data {
        try snapshot.validate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".openanki")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        let data = try JSONEncoder().encode(snapshot)
        try archive.addEntry(with: "collection.json", type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
            data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
        }
        for folder in Set(snapshot.cards.compactMap(\.mediaFolder)).sorted() {
            let source = mediaURL.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw CollectionError.invalid("媒体文件夹缺失，无法生成完整备份：\(folder)")
            }
            for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
                guard !file.lastPathComponent.hasPrefix(".openanki-render-") else { continue }
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                try archive.addEntry(with: "Media/\(folder)/\(file.lastPathComponent)", fileURL: file, compressionMethod: .deflate)
            }
        }
        return try Data(contentsOf: url)
    }

    public static func merging(_ imported: CollectionSnapshot, into current: CollectionSnapshot) -> (snapshot: CollectionSnapshot, added: Int, skipped: Int) {
        var result = current
        var deckMap: [UUID: UUID] = [:]
        for deck in imported.decks {
            if let existing = result.decks.first(where: { $0.name == deck.name }) {
                deckMap[deck.id] = existing.id
            } else {
                var newDeck = deck
                if result.decks.contains(where: { $0.id == newDeck.id }) { newDeck.id = UUID() }
                deckMap[deck.id] = newDeck.id
                result.decks.append(newDeck)
            }
        }
        var ids = Set(result.cards.map(\.id))
        var sourceKeys = Set(result.cards.compactMap(\.sourceKey))
        var added = 0
        var skipped = 0
        for var card in imported.cards {
            if ids.contains(card.id) || card.sourceKey.map({ sourceKeys.contains($0) }) == true {
                skipped += 1
                continue
            }
            card.deckID = deckMap[card.deckID] ?? card.deckID
            result.cards.append(card)
            ids.insert(card.id)
            if let key = card.sourceKey { sourceKeys.insert(key) }
            added += 1
        }
        return (result, added, skipped)
    }
}
