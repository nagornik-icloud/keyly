import Foundation

/// Text processing level after transcription/extraction.
///
/// One vocabulary for the whole app: voice and typo fixing do the same thing to text, and they
/// used to have TWO different sets of settings with labels that didn't match the prompts they
/// actually called. The user couldn't know what they'd get.
///
/// A separate file from `TextPolisher`: the level itself is a pure enum with no runtime, and
/// unit tests include it together with `TextPolishPrompt` by path, without pulling in
/// `UserDefaults`, badges and networking.
enum TextPolishLevel: String, CaseIterable, Codable {
    /// Verbatim, no model call.
    case verbatim
    /// Spelling, punctuation, brand names and anglicisms, paragraphs. The words stay the same.
    case tidy
    /// Same plus removing "um", repetitions and slips; speech is turned into written text.
    /// Wording may change — the only level where the text gets rewritten.
    case rewrite

    /// Whether a network request is needed. `verbatim` is free and instant — all processing is
    /// skipped, including the key check.
    var requiresLLM: Bool { self != .verbatim }

    /// "Verbatim" is the only level that needs NO key, costs nothing and doesn't change the
    /// user's words. A `.tidy` default combined with local voice mode silently sent the
    /// transcript to the cloud while the mode's label said "works offline and without a key" —
    /// the app broke its own promise.
    static let `default`: TextPolishLevel = .verbatim
}
