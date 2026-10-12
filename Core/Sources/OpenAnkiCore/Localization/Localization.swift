import Foundation

public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> InterfaceLanguage {
        guard self == .system else { return self }
        let first = (preferredLanguages.first ?? "en").replacingOccurrences(of: "_", with: "-").lowercased()
        let parts = first.split(separator: "-").map(String.init)
        if parts.first == "zh" {
            // An explicit script takes precedence over the device's region.
            if parts.contains("hans") { return .simplifiedChinese }
            if !parts.contains("hant"), !parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) {
                return .simplifiedChinese
            }
        }
        return .english
    }

    public func locale(preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        Locale(identifier: resolved(preferredLanguages: preferredLanguages) == .simplifiedChinese ? "zh-Hans-CN" : "en-US")
    }
}

/// Localizes app messages and the built-in guide without translating user deck
/// text. Interpolated values, including filenames, use string placeholders.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public let key: String
    public let arguments: [String]

    public init(key: String, arguments: [String] = []) {
        self.key = key
        self.arguments = arguments
    }

    public init(stringLiteral value: String) { self.init(key: value) }
    public init(stringInterpolation: StringInterpolation) {
        self.init(key: stringInterpolation.key, arguments: stringInterpolation.arguments)
    }

    public func localized(locale: Locale = InterfaceLanguage.system.locale()) -> String {
        let language = InterfaceLanguage.system.resolved(preferredLanguages: [locale.identifier]).rawValue
        let resourceLanguage = Bundle.module.localizations.first { $0.lowercased() == language.lowercased() } ?? "en"
        let bundle = Bundle.module.path(forResource: resourceLanguage, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.module
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments.map { $0 as CVarArg })
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            arguments.append(String(describing: value))
        }
    }
}
