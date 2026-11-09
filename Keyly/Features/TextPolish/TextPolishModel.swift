import Foundation

/// Which model processes the transcript. A PURE type with no store and no networking.
///
/// Extracted from `VoiceToTextManager`: the fix "processing goes to the selected key's provider"
/// relied on two decisions — route by provider and model substitution — and neither was checked
/// by anything but reading the code. A manual run here costs a paid call, so the decision is
/// separated from the call: the request spends money, but the mistake can happen before it.
enum TextPolishModel {

    /// Model for the processing CHAT request.
    ///
    /// A transcription model must not end up here: it takes audio, not a dialog, and processing
    /// with it fails with a "Couldn't tidy up" badge instead of paragraphs. The voice picker once
    /// offered exactly such models, and that choice may still be in the user's settings — so
    /// substitution is needed on EVERY read, not only during migration.
    ///
    /// `fallback` is the default chat model of the CURRENT provider. Substituting the OpenAI
    /// default for a Gemini key would just trade one failure for another.
    static func resolve(picked: String, transcriptionModelIDs: Set<String>, fallback: String) -> String {
        let trimmed = picked.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return transcriptionModelIDs.contains(trimmed) ? fallback : trimmed
    }
}
