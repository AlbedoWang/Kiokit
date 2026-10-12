import XCTest
@testable import KiokitCore

final class AnkiAVTests: XCTestCase {
    func testNativeTtsParametersAndOrderedMediaTagsSurviveThePresentationAdapter() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let collection = try AnkiCollection(directory: directory)
        defer { try? collection.close(); try? FileManager.default.removeItem(at: directory) }
        let native = try collection.backend.call("anki.card_rendering.ExtractAvTags", [
            "text": "[sound:directory/original clip.mp4][anki:tts lang=ja_JP voices=Apple_Kyoko,Apple_Otoya speed=1.2 foo=bar]日本語[/anki:tts][sound:after.wav]",
            "questionSide": true,
        ])
        let tags = native["avTags"].array.map(AnkiAudioTag.init)
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(tags[0].filename, "original clip.mp4")
        XCTAssertEqual(tags[1].language, "ja_JP")
        XCTAssertEqual(tags[1].voices, ["Apple_Kyoko", "Apple_Otoya"])
        XCTAssertEqual(tags[1].text, "日本語")
        XCTAssertEqual(tags[1].speed, 1.2, accuracy: 0.0001)
        XCTAssertEqual(tags[1].otherArguments, ["foo=bar"])
        XCTAssertEqual(tags[2].filename, "after.wav")
    }
}
