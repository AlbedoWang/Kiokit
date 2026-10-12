import Foundation

/// Original license texts bundled for offline display, separate from Anki's
/// immutable frontend assets so resource verification remains meaningful.
public enum KiokitLicenses {
    public static let sourceURL = URL(string: "https://github.com/AlbedoWang/Kiokit")!
    public static let upstreamURL = URL(string: "https://github.com/ankitects/anki")!
    public static var directory: URL { Bundle.module.url(forResource: "Licenses", withExtension: nil)! }
}
