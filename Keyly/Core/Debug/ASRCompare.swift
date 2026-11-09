#if DEBUG
import Foundation

/// Benchmark of the local model against the cloud ("prototype → measure Russian → decide").
///
/// Works on REAL dictation: turn on the flag, dictate as usual, and every dictation logs a
/// "cloud / local" pair with timings. A synthetic benchmark is useless here — the model card
/// already gives WER on other datasets, while the decision is about THIS mic, THIS diction
/// and THESE words (terms, names, English words mixed with Russian).
///
/// Enabled with `KEYLY_ASR_COMPARE=1` (Xcode → scheme → Run → Arguments → Environment).
/// DEBUG only: local recognition runs AFTER the cloud result is inserted and doesn't affect
/// dictation speed.
@MainActor
enum ASRCompare {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["KEYLY_ASR_COMPARE"] == "1"
    }

    /// Runs the same file through the local model and prints the comparison.
    /// Called AFTER the cloud result has been inserted — so the benchmark doesn't delay the
    /// user or distort the impression of speed.
    static func compare(cloudText: String, audioURL: URL) {
        guard isEnabled else { return }
        // Copy the file: the regular path deletes the recording right after recognition.
        // KEEP the extension (recording is .m4a): `AVAudioFile` picks the parser by extension,
        // not by content, and won't open AAC bytes named .wav. The benchmark would then silently
        // fail on EVERY dictation and look like "the model failed" — the prototype would yield
        // zero measurements and the opposite conclusion.
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyly-asr-compare-\(UUID().uuidString)")
            .appendingPathExtension(audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension)
        do {
            try FileManager.default.copyItem(at: audioURL, to: copy)
        } catch {
            Log.warn(.voice, "ASRCompare: не удалось скопировать запись — замер пропущен")
            return
        }

        Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: copy) }
            guard let local = await LocalTranscriber.shared.transcribe(url: copy) else {
                Log.warn(.voice, "ASRCompare: локальная модель не дала результата")
                return
            }
            report(cloud: cloudText, local: local)
        }
    }

    private static func report(cloud: String, local: LocalTranscriber.Transcript) {
        // Texts are printed IN FULL on purpose: this is a debug mode behind an explicit flag, and
        // without the texts there's nothing to compare. Release builds don't contain this code at
        // all (#if DEBUG), and the sanitizer can't help — the texts are the subject of the benchmark.
        let lines = """

        ┌─ ЗАМЕР РАСПОЗНАВАНИЯ ──────────────────────────────
        │ облако:   \(cloud)
        │ локально: \(local.text)
        │
        │ совпадение слов: \(String(format: "%.0f%%", agreement(cloud, local.text) * 100))
        │ длительность:    \(String(format: "%.1f", local.audioDuration)) с
        │ локально заняло: \(String(format: "%.1f", local.processingTime)) с \
        (×\(String(format: "%.1f", local.realtimeFactor)) от реального времени)
        │ уверенность:     \(String(format: "%.2f", local.confidence))
        └────────────────────────────────────────────────────
        """
        Log.info(.voice, lines)
    }

    /// Rough share of matching words — not WER, just a hint whether the engines "look the same
    /// way". The real assessment is by eye: what matters is not the percentage but WHAT exactly
    /// diverged (terms, names, endings).
    static func agreement(_ a: String, _ b: String) -> Double {
        let wordsA = normalizedWords(a)
        let wordsB = normalizedWords(b)
        guard !wordsA.isEmpty else { return wordsB.isEmpty ? 1 : 0 }
        let common = Set(wordsA).intersection(Set(wordsB)).count
        return Double(common) / Double(Set(wordsA).count)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
#endif
