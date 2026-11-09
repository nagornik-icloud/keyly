import Foundation

/// Checking the key FORMAT before the network call.
///
/// Why before the network: a tail cut off while copying gets the same 401 from the provider as
/// someone else's key, and the user goes off to fix the wrong thing. The format is visible right
/// away, without a request.
///
/// The rules are deliberately WEAK — only what providers have guaranteed for years (prefix and
/// minimum length). A strict mask would go stale before it paid off and would start rejecting
/// working keys.
enum APIKeyFormat {

    enum Verdict: Equatable {
        case ok
        /// The key is empty or consists of whitespace.
        case empty
        /// Wrong prefix — almost always a key from another provider.
        case wrongPrefix(expected: String)
        /// The prefix is right, but the key is shorter than any real one — cut off while copying.
        case tooShort
    }

    /// The provider as a VALUE, not the type from the store: `APIProvider` lives inside `APIKeyStore`
    /// and drags in `UserDefaults` and the main actor — that can't be linked into the test package,
    /// and the format must be checked precisely by a test.
    enum Kind: String, CaseIterable {
        case openai
        case gemini
    }

    static func check(_ raw: String, provider: Kind) -> Verdict {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }

        switch provider {
        case .openai:
            // All OpenAI keys start with "sk-" (including sk-proj-, sk-svcacct-).
            guard value.hasPrefix("sk-") else { return .wrongPrefix(expected: "sk-") }
            return value.count >= 20 ? .ok : .tooShort
        case .gemini:
            // Google AI Studio keys start with "AIza" and have a fixed length of 39 characters.
            guard value.hasPrefix("AIza") else { return .wrongPrefix(expected: "AIza") }
            return value.count >= 30 ? .ok : .tooShort
        }
    }

    /// Whether we are confident enough to REFUSE before the network.
    ///
    /// Only what can't work under any conditions is blocked: an empty key and a key shorter than
    /// any real one. A mismatched prefix is only a HINT: providers introduce new formats, and we
    /// have no right to declare a working key invalid and deny the user the chance to check it.
    ///
    /// This was learned the hard way: a "prefix is mandatory" rule marked a working key as
    /// broken and disabled the network check for it — worse than before.
    static func blocksNetworkCheck(_ verdict: Verdict) -> Bool {
        switch verdict {
        case .empty, .tooShort: return true
        case .ok, .wrongPrefix: return false
        }
    }

    static func messageKey(for verdict: Verdict) -> (key: String, argument: String)? {
        switch verdict {
        case .ok:                       return nil
        case .empty:                    return ("keys.format.empty", "")
        case .wrongPrefix(let expected): return ("keys.format.wrongPrefix", expected)
        case .tooShort:                 return ("keys.format.tooShort", "")
        }
    }
}
