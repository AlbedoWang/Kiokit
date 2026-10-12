import Foundation

/// Unmodified assets from the official Anki distribution; provenance and wheel
/// checksum are recorded in the resource directory's upstream.json.
public enum AnkiWebResources {
    public static var directory: URL { Bundle.module.url(forResource: "AnkiWeb", withExtension: nil)! }
}
