import Foundation

/// Strips secrets from strings BEFORE they reach the log.
///
/// Why a separate type instead of "just don't log keys": a key leaks not where it is logged
/// on purpose but IN TRANSIT. Gemini accepts the key as a query parameter
/// (`...:generateContent?key=AIza...`), and an `NSError` from URLSession carries
/// `NSErrorFailingURLKey` — so an innocent "log the error" call puts a live key into the
/// system log, which is readable via Console and ends up in sysdiagnose.
///
/// Pure logic without dependencies — covered by unit tests (`swift test`).
enum LogSanitizer {

    static let redacted = "‹скрыто›"

    /// Masks anything that looks like a secret. Apply to any string that came from outside:
    /// error descriptions, response bodies, URLs.
    static func sanitize(_ text: String) -> String {
        var out = text
        for rule in rules {
            out = rule.regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: rule.template
            )
        }
        return out
    }

    /// A short safe "fingerprint" of a key for diagnostics ("was the right key used"):
    /// the first 4 characters and the length. The key can't be recovered from it.
    static func fingerprint(_ secret: String) -> String {
        guard !secret.isEmpty else { return "‹пусто›" }
        let head = String(secret.prefix(4))
        return "\(head)…(\(secret.count))"
    }

    // MARK: - Rules

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static let rules: [Rule] = {
        // $1 keeps the identifying part — the log shows WHAT was hidden, but not the value.
        let patterns: [(String, String)] = [
            // Gemini: key in a URL query parameter.
            (#"([?&]key=)[^&\s"']+"#, "$1\(redacted)"),
            // Authorization header (OpenAI and most APIs).
            (#"(?i)(authorization:\s*bearer\s+)[^\s"']+"#, "$1\(redacted)"),
            (#"(?i)(x-api-key:\s*)[^\s"']+"#, "$1\(redacted)"),
            // Keys recognizable by shape, even outside a header (leaked into a response body/message).
            (#"\bsk-[A-Za-z0-9_\-]{8,}"#, redacted),
            (#"\bAIza[A-Za-z0-9_\-]{10,}"#, redacted),
        ]
        return patterns.compactMap { pattern, template in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return Rule(regex: re, template: template)
        }
    }()
}
