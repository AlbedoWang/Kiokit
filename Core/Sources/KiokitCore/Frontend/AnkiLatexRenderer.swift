// Adapted from ankitects/anki 26.09.3, pylib/anki/latex.py.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

/// Uses upstream extraction, filenames, preferences, commands, and error text.
/// iOS cannot spawn the desktop TeX tools; imported rendered images still work.
public enum AnkiLatexRenderer {
    public static func render(_ html: String, svg: Bool, collection: AnkiCollection, noteType: () throws -> AnkiJSON) throws -> String {
        let extracted = try collection.backend.call("anki.card_rendering.ExtractLatex", ["text": .string(html), "svg": .bool(svg), "expandClozes": false])
        var text = extracted["text"].string
        guard !extracted["latex"].array.isEmpty else { return text }
        let model = try noteType()["config"]
        let generate = try collection.backend.call("anki.config.GetConfigBool", ["key": "RENDER_LATEX"])["val"].bool
        var errors: [String] = []
        for latex in extracted["latex"].array {
            if FileManager.default.fileExists(atPath: collection.mediaURL.appendingPathComponent(latex["filename"].string).path) { continue }
            if !generate {
                errors.append(try translate(collection.backend, module: 26, message: 35))
                break
            }
            if let error = try saveImage(latex, model: model, svg: svg, collection: collection) { errors.append(error) }
        }
        text += errors.joined(separator: "\n")
        return text
    }

    private static func saveImage(_ extracted: AnkiJSON, model: AnkiJSON, svg: Bool, collection: AnkiCollection) throws -> String? {
        try collection.withLatexWorkspace { directory in
            try saveImage(_extracted: extracted, model: model, svg: svg, collection: collection, directory: directory)
        }
    }

    private static func saveImage(_extracted extracted: AnkiJSON, model: AnkiJSON, svg: Bool, collection: AnkiCollection, directory: URL) throws -> String? {
        let tex = directory.appendingPathComponent("tmp.tex")
        let content = model["latexPre"].string + "\n" + extracted["latexBody"].string + "\n" + model["latexPost"].string
        try content.write(to: tex, atomically: true, encoding: .utf8)
        let logURL = directory.appendingPathComponent("latex_log.txt")
        _ = FileManager.default.createFile(atPath: logURL.path, contents: Data())
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let image = directory.appendingPathComponent(svg ? "tmp.svg" : "tmp.png")
        if FileManager.default.fileExists(atPath: image.path) { try FileManager.default.removeItem(at: image) }
        let commands = svg
            ? [["latex", "-interaction=nonstopmode", "tmp.tex"], ["dvisvgm", "--no-fonts", "--exact", "-Z", "2", "tmp.dvi", "-o", "tmp.svg"]]
            : [["latex", "-interaction=nonstopmode", "tmp.tex"], ["dvipng", "-bg", "Transparent", "-D", "200", "-T", "tight", "tmp.dvi", "-o", "tmp.png"]]
        for command in commands where run(command, directory: directory, log: log) != 0 {
            let backend = collection.backend
            var error = try translate(backend, module: 22, message: 0, value: command[0]) + "<br>"
            error += try translate(backend, module: 22, message: 3, value: tex.path) + "<br>"
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            if output.isEmpty { error += try translate(backend, module: 22, message: 4) }
            else { error += "<small><pre>" + escape(output) + "</pre></small>" }
            return error
        }
        let data = try Data(contentsOf: image)
        try collection.backend.call("anki.media.AddMediaFile", ["desiredName": extracted["filename"], "data": .string(data.base64EncodedString())])
        try FileManager.default.removeItem(at: image)
        return nil
    }

    /// Platform equivalent of anki.utils.call; a missing executable returns -1.
    private static func run(_ arguments: [String], directory: URL, log: FileHandle) -> Int32 {
        #if os(macOS)
        var environment = ProcessInfo.processInfo.environment
        let path = (environment["PATH"] ?? "") + ":/usr/texbin:/Library/TeX/texbin"
        environment["PATH"] = path
        guard let executable = path.split(separator: ":").map({ URL(fileURLWithPath: String($0)).appendingPathComponent(arguments[0]) }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return -1 }
        let process = Process()
        process.executableURL = executable
        process.arguments = Array(arguments.dropFirst())
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardOutput = log
        process.standardError = log
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus }
        catch { return -1 }
        #else
        return -1
        #endif
    }

    private static func translate(_ backend: AnkiBackend, module: Int64, message: Int64, value: String? = nil) throws -> String {
        // Translation IDs from upstream generated/_fluent.py at the pinned SHA.
        try backend.call("anki.i18n.TranslateString", ["moduleIndex": .integer(module), "messageIndex": .integer(message),
            "args": value.map { ["val": ["str": .string($0)]] } ?? [:]])["val"].string
    }

    /// Python html.escape(), with its default quote=True, for the TeX log.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#x27;")
    }
}
