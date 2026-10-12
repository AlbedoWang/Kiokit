import Foundation
import ZIPFoundation

/// Reads the retired application's own archive format solely for migration.
/// Anki packages and current collection backups never pass through this reader.
public enum LegacyBackupReader {
    public static func convertedPackage(from url: URL) throws -> URL {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["collection.json"] else { throw CollectionError.invalid("此文件不包含旧版 OpenAnki 备份。") }
        var json = Data()
        _ = try archive.extract(entry, consumer: { json.append($0) })
        let snapshot = try JSONDecoder().decode(CollectionSnapshot.self, from: json)
        try snapshot.validate()
        let root = URL.temporaryDirectory.appendingPathComponent("OpenAnkiLegacyBackup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("Media", isDirectory: true)
        for entry in archive where entry.path.hasPrefix("Media/") && entry.type == .file {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard components.count == 3, components[0] == "Media",
                  CollectionSnapshot.safeComponent(components[1]), CollectionSnapshot.safeComponent(components[2]) else {
                throw CollectionError.invalid("媒体路径无效。")
            }
            let folder = media.appendingPathComponent(components[1], isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: folder.appendingPathComponent(components[2]))
        }
        return try LegacyCollectionMigration.convert(snapshot, media: media, originalJSON: json)
    }
}
