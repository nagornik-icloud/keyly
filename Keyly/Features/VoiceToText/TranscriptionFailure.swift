import Foundation

/// What a failed transcription request means for the next attempt.
enum TranscriptionFailure: Equatable {
    /// Network or server trouble — worth repeating, and other keys may work.
    case transient
    /// This key is refused (invalid, no access) — skip to the next key, don't repeat.
    case keySpecific
    /// The request itself is wrong (format, size, model) — every key would fail the same
    /// way, so stop instead of sending the audio around.
    case badRequest

    static func classify(_ error: Error) -> TranscriptionFailure {
        if error is URLError { return .transient }
        switch (error as NSError).code {
        case 401, 403: return .keySpecific
        case 400, 404, 413, 422: return .badRequest
        default: return .transient          // 408, 429, 5xx, malformed responses
        }
    }
}
