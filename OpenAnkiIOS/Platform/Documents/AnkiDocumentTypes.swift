import UniformTypeIdentifiers

extension UTType {
    static let ankiPackage = UTType(importedAs: "net.anki.apkg", conformingTo: .zip)
    static let ankiCollectionPackage = UTType(importedAs: "net.anki.colpkg", conformingTo: .zip)
    static let openAnkiBackup = UTType(exportedAs: "app.openanki.backup", conformingTo: .zip)
}
