// Adapted from ankitects/anki 26.09.3, pylib/anki/cards.py::time_taken.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

/// The platform supplies time.time() equivalents. Anki's elapsed-time and
/// optional display cap are preserved; the backend caps submitted answers.
public struct AnkiReviewTimer: Sendable {
    public let startedAt: TimeInterval
    public init(startedAt: TimeInterval) { self.startedAt = startedAt }

    public func timeTaken(at now: TimeInterval, capped: Bool = true, timeLimitMilliseconds: Int64) throws -> Int64 {
        // Python int() truncates toward zero. Protobuf transport validates the
        // resulting integer; there is no replacement lower/upper clamp here.
        guard let total = Int64(exactly: ((now - startedAt) * 1000).rounded(.towardZero)) else {
            throw AnkiBackendError(message: "Invalid elapsed review time.", kind: "INVALID_INPUT")
        }
        return capped ? min(total, timeLimitMilliseconds) : total
    }
}
