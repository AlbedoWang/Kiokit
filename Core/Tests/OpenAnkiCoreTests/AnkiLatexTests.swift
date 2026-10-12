import Foundation
import XCTest
@testable import OpenAnkiCore

final class AnkiLatexTests: XCTestCase {
    private func collection() throws -> AnkiCollection {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let collection = try AnkiCollection(directory: root)
        addTeardownBlock { try? collection.close(); try? FileManager.default.removeItem(at: root) }
        return collection
    }

    private func basic(_ collection: AnkiCollection) throws -> AnkiJSON {
        let type = try collection.backend.call("anki.notes.DefaultsForAdding")["notetypeId"].int
        return try collection.noteType(type)
    }

    func testImportedLatexMediaAndDisabledGenerationFollowUpstreamExtraction() throws {
        let collection = try collection()
        let text = "Before [$]x^2[/$] after [latex]y[/latex]"
        let model = try basic(collection)
        try collection.backend.call("anki.config.SetConfigBool", ["key": "RENDER_LATEX", "value": false])
        for svg in [false, true] {
            let extracted = try collection.backend.call("anki.card_rendering.ExtractLatex", ["text": .string(text), "svg": .bool(svg)])
            let warning = try collection.backend.call("anki.i18n.TranslateString", ["moduleIndex": 26, "messageIndex": 35])["val"].string
            XCTAssertEqual(try AnkiLatexRenderer.render(text, svg: svg, collection: collection, noteType: { model }), extracted["text"].string + warning)
            for item in extracted["latex"].array {
                try collection.backend.call("anki.media.AddMediaFile", ["desiredName": item["filename"], "data": .string(Data("imported fixture image".utf8).base64EncodedString())])
            }
            XCTAssertEqual(try AnkiLatexRenderer.render(text, svg: svg, collection: collection, noteType: { model }), extracted["text"].string)
        }
    }

    #if os(macOS)
    func testNativeDesktopCommandsGenerateTheUpstreamNamedPngAndSvg() throws {
        guard FileManager.default.isExecutableFile(atPath: "/Library/TeX/texbin/latex"), FileManager.default.isExecutableFile(atPath: "/Library/TeX/texbin/dvipng"), FileManager.default.isExecutableFile(atPath: "/Library/TeX/texbin/dvisvgm") else {
            throw XCTSkip("Install the TeX executables used by desktop Anki to verify generation.")
        }
        let collection = try collection()
        let model = try basic(collection)
        try collection.backend.call("anki.config.SetConfigBool", ["key": "RENDER_LATEX", "value": true])
        for svg in [false, true] {
            let text = "[$]x^2 + 1[/$]"
            let extracted = try collection.backend.call("anki.card_rendering.ExtractLatex", ["text": .string(text), "svg": .bool(svg)])
            XCTAssertEqual(try AnkiLatexRenderer.render(text, svg: svg, collection: collection, noteType: { model }), extracted["text"].string)
            let item = try XCTUnwrap(extracted["latex"].array.first)
            let image = try Data(contentsOf: collection.mediaURL.appendingPathComponent(item["filename"].string))
            XCTAssertGreaterThan(image.count, 100)
            if svg { XCTAssertTrue(String(decoding: image, as: UTF8.self).contains("<svg")) }
            else { XCTAssertEqual(Array(image.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10]) }
        }
    }
    #endif
}
