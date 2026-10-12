import Foundation
import AnkiBackendFFI

public struct AnkiBackendError: LocalizedError, Sendable {
    public let message: String
    public let kind: String
    public var errorDescription: String? { message }
}

/// Platform bindings only. Every named operation executes the official backend
/// at the revision recorded in Backend/upstream.json; no domain fallback exists.
public final class AnkiBackend: @unchecked Sendable {
    public static let upstreamVersion = "26.09.3"
    public static let upstreamCommit = "29bb700b951e3f0c0cb69b77c0180fc1fe33e6ba"
    private let handle: UnsafeMutableRawPointer
    private let lock = NSRecursiveLock()

    public init(preferredLanguages: [String] = ["en"]) throws {
        let input: AnkiJSON = ["preferredLangs": .array(preferredLanguages.map(AnkiJSON.string))]
        let data = try JSONEncoder().encode(input)
        let pointer = data.withUnsafeBytes { bytes in
            openanki_backend_create(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
        }
        guard let pointer else { throw AnkiBackendError(message: "Unable to initialize the Anki backend.", kind: "INITIALIZATION") }
        handle = pointer
    }

    deinit { openanki_backend_destroy(handle) }

    @discardableResult
    public func call(_ name: String, _ input: AnkiJSON = [:]) throws -> AnkiJSON {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(input)
        var pointer: UnsafeMutablePointer<UInt8>?
        var length = 0
        name.withCString { name in
            data.withUnsafeBytes { bytes in
                openanki_backend_call(handle, name, bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &pointer, &length)
            }
        }
        guard let pointer else { throw AnkiBackendError(message: "The Anki backend returned no response.", kind: "TRANSPORT") }
        defer { openanki_backend_free(pointer, length) }
        let result = try JSONDecoder().decode(AnkiJSON.self, from: Data(bytes: pointer, count: length))
        if !result["error"].isNull {
            // INVALID_INPUT is enum value zero and is omitted in canonical JSON.
            let kind = result["error"]["kind"].isNull ? "INVALID_INPUT" : result["error"]["kind"].string
            throw AnkiBackendError(message: result["error"]["message"].string, kind: kind)
        }
        return result["value"]
    }

    /// Uses Anki's own database proxy for read-only UI projections and migration.
    public func query(_ sql: String, arguments: [AnkiJSON] = []) throws -> [[AnkiJSON]] {
        try call("anki.db", ["kind": "query", "sql": .string(sql), "args": .array(arguments), "first_row_only": false]).array.map(\.array)
    }

    /// Encodes official frontend messages for Anki's unmodified reviewer.js.
    public func encodeProtobuf(_ type: String, value: AnkiJSON) throws -> Data {
        let response = try call("anki.transport.EncodeMessage", ["type": .string(type), "value": value])
        guard let data = Data(base64Encoded: response["data"].string) else {
            throw AnkiBackendError(message: "Invalid protobuf transport response.", kind: "TRANSPORT")
        }
        return data
    }

    public func decodeProtobuf(_ type: String, data: Data) throws -> AnkiJSON {
        try call("anki.transport.DecodeMessage", ["type": .string(type), "data": .string(data.base64EncodedString())])
    }
}
