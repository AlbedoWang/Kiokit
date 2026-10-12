import Foundation

/// JSON transport for upstream protobuf messages. Int64 protobuf fields remain
/// strings on the wire, as required by the canonical protobuf JSON encoding.
public enum AnkiJSON: Codable, Hashable, Sendable {
    case object([String: AnkiJSON]), array([AnkiJSON]), string(String)
    case integer(Int64), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let result = try? value.decode(Bool.self) { self = .bool(result) }
        else if let result = try? value.decode(Int64.self) { self = .integer(result) }
        else if let result = try? value.decode(Double.self) { self = .number(result) }
        else if let result = try? value.decode(String.self) { self = .string(result) }
        else if let result = try? value.decode([AnkiJSON].self) { self = .array(result) }
        else { self = .object(try value.decode([String: AnkiJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let result): try value.encode(result)
        case .array(let result): try value.encode(result)
        case .string(let result): try value.encode(result)
        case .integer(let result): try value.encode(result)
        case .number(let result): try value.encode(result)
        case .bool(let result): try value.encode(result)
        case .null: try value.encodeNil()
        }
    }

    public subscript(_ key: String) -> AnkiJSON { object[key] ?? .null }
    public var object: [String: AnkiJSON] { if case .object(let value) = self { value } else { [:] } }
    public var array: [AnkiJSON] { if case .array(let value) = self { value } else { [] } }
    public var string: String { if case .string(let value) = self { value } else { "" } }
    public var int: Int64 {
        switch self {
        case .integer(let value): value
        case .string(let value): Int64(value) ?? 0
        case .number(let value): Int64(value)
        default: 0
        }
    }
    public var double: Double {
        switch self {
        case .number(let value): value
        case .integer(let value): Double(value)
        case .string(let value): Double(value) ?? 0
        default: 0
        }
    }
    public var bool: Bool { if case .bool(let value) = self { value } else { false } }
    public var isNull: Bool { self == .null }
    public static func id(_ value: Int64) -> AnkiJSON { .string(String(value)) }
}

extension AnkiJSON: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension AnkiJSON: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .integer(value) }
}
extension AnkiJSON: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension AnkiJSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnkiJSON)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
}
extension AnkiJSON: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnkiJSON...) { self = .array(elements) }
}
