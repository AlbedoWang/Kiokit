import Foundation
import OpenAnkiCore

// A local verification harness for transport parity with the official Python
// backend. It forwards upstream requests and contains no application rules.
let backend = try AnkiBackend()
var adapter: AnkiCollection?
while let line = readLine() {
    do {
        let request = try JSONDecoder().decode(AnkiJSON.self, from: Data(line.utf8))
        let input = request["input"].isNull ? AnkiJSON.object([:]) : request["input"]
        let response: AnkiJSON
        if request["method"].string == "openanki.verify.OpenCollectionAdapter" {
            adapter = try AnkiCollection(directory: URL(fileURLWithPath: input["directory"].string))
            response = [:]
        } else if request["method"].string == "openanki.verify.RenderedCard" {
            guard let adapter else { throw NSError(domain: "AnkiProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "No verification collection."]) }
            response = try adapter.renderedCard(input["cardId"].int, browser: input["browser"].bool)
        } else if request["method"].string == "openanki.verify.TypeAnswer" {
            let typed = try AnkiTypedAnswer(backend: backend, question: input["question"].string,
                fields: input["fields"], values: input["values"], cardOrdinal: input["cardOrdinal"].int)
            response = ["question": .string(typed.question), "answer": .string(try typed.answer(input["answer"].string, provided: input["provided"].string))]
        } else if request["method"].string == "openanki.verify.AVFrontend" {
            let available = input["voices"].array.map { AnkiTTSVoice(identifier: $0["identifier"].string, name: $0["name"].string, language: $0["language"].string) }
            let match = AnkiAVFrontend.voice(for: AnkiAudioTag(input["tag"]), available: available, defaultRank: Int(input["defaultRank"].int))
            response = ["isAudio": .bool(AnkiAVFrontend.isAudioFile(input["filename"].string)),
                        "voice": match.map { ["identifier": .string($0.voice.identifier), "rank": .number(Double($0.rank))] } ?? .null]
        } else if request["method"].string == "openanki.verify.WebFrontend" {
            response = ["mime": AnkiWebFrontend.commonMimeType(for: input["path"].string).map(AnkiJSON.string) ?? .null,
                        "html": .string(try AnkiWebFrontend.trustedSvelteHTML(input["html"].string))]
        } else if request["method"].string == "openanki.verify.WebTheme" {
            response = .string(AnkiWebFrontend.themeUpdateJavaScript(nightMode: input["nightMode"].bool, macOSDarkMode: input["macOSDarkMode"].bool))
        } else if request["method"].string == "openanki.verify.ReviewTimer" {
            response = ["milliseconds": .integer(try AnkiReviewTimer(startedAt: input["startedAt"].double).timeTaken(at: input["now"].double, capped: input["capped"].bool, timeLimitMilliseconds: input["limit"].int))]
        } else {
            response = try (adapter?.backend ?? backend).call(request["method"].string, input)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var bytes = try encoder.encode(AnkiJSON.object(["value": response]))
        bytes.append(10)
        FileHandle.standardOutput.write(bytes)
    } catch {
        let error = error as? AnkiBackendError
        let result: AnkiJSON = ["error": ["message": .string(error?.message ?? "Transport error"), "kind": .string(error?.kind ?? "TRANSPORT")]]
        var bytes = try JSONEncoder().encode(result)
        bytes.append(10)
        FileHandle.standardOutput.write(bytes)
    }
}
