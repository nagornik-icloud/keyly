import Foundation

/// Approximate price of a model call.
///
/// Why. The user picks a model from ten names that mean nothing to them, with no hint of how
/// "gpt-4o" differs from "gpt-4o-mini" in cost — and the difference is more than tenfold. A
/// caption under the name turns a list of slugs into a meaningful choice.
///
/// HONEST NUMBERS. This is an ESTIMATE, not a tariff. The provider sets prices, they change,
/// and the app doesn't fetch them. Therefore:
/// - the price is shown with "≈" and the caption explicitly calls it approximate;
/// - models whose price can't be stated confidently get `nil` — and NO caption at all.
///   A made-up number is worse than nothing here: people make money decisions based on it.
///
/// The numbers come from OpenAI's public price list, copied by hand. There's no automatic
/// check: when adding a model, either bring the number from the price list or leave `nil`.
enum ModelPricing {

    /// Reference request size for the "per call" figure: about a page of text in and the same
    /// out. Real calls are shorter or longer — hence the "≈".
    static let referenceInputTokens = 500.0
    static let referenceOutputTokens = 500.0

    /// Price per million tokens: (input, output).
    private static let perMillion: [String: (input: Double, output: Double)] = [
        "gpt-4o":        (2.50, 10.00),
        "gpt-4o-mini":   (0.15,  0.60),
        "gpt-4.1":       (2.00,  8.00),
        "gpt-4.1-mini":  (0.40,  1.60),
        "gpt-4.1-nano":  (0.10,  0.40),
        // gpt-5* and Gemini are deliberately absent: their prices can't be stated confidently.
    ]

    /// Transcription price per minute of audio.
    private static let perAudioMinute: [String: Double] = [
        "gpt-4o-transcribe":      0.006,
        "gpt-4o-mini-transcribe": 0.003,
        "whisper-1":              0.006,
    ]

    /// Ready AMOUNT per call, or `nil`. The UI layer supplies the catalog key — this type is in
    /// the test package, where `.loc` isn't available (same approach as `BareKeyWarning`).
    static func perCall(for model: String) -> String? {
        guard let p = perMillion[model] else { return nil }
        let usd = p.input / 1_000_000 * referenceInputTokens
                + p.output / 1_000_000 * referenceOutputTokens
        return format(usd)
    }

    /// Ready amount per minute of audio, or `nil`.
    static func perMinute(for model: String) -> String? {
        guard let usd = perAudioMinute[model] else { return nil }
        return format(usd)
    }

    /// Dollars with SIGNIFICANT precision: for cheap models two decimals give "$0.00", i.e.
    /// "free" — exactly the mistake the caption exists to prevent.
    static func format(_ usd: Double) -> String {
        if usd >= 0.01 { return String(format: "$%.2f", usd) }
        if usd >= 0.001 { return String(format: "$%.3f", usd) }
        return String(format: "$%.4f", usd)
    }
}
