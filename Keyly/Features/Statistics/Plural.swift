import Foundation

/// Noun plural form for a number.
///
/// Pure logic without Foundation localization on purpose: `stringsdict` solves the same task,
/// but it can't be unit-tested at the boundaries — and the boundaries are what break. A wrong
/// form ("1 fixes", or Russian "992" with the wrong ending) reads as machine-assembled text and
/// undermines trust in the numbers next to it.
enum Plural {

    /// Russian rules: 1 → first form, 2–4 → second, 0 and 5+ → third.
    /// The 11–14 exception is required: they take the third form even though they end in 1–4.
    static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100
        if (11...14).contains(a) { return many }
        switch a % 10 {
        case 1:      return one
        case 2...4:  return few
        default:     return many
        }
    }

    /// English rules: everything except exactly 1 is plural.
    static func en(_ n: Int, _ one: String, _ many: String) -> String {
        abs(n) == 1 ? one : many
    }

    /// Form for the given language. The language comes as a PARAMETER, not from a singleton:
    /// otherwise the type is no longer pure and can't be tested at the boundaries — and the
    /// boundaries (11, 14, 21, 111) are what break.
    ///
    /// The language must be ALREADY RESOLVED (`.ru` / `.en`), not `.system`. This used to be
    /// `language == .en ? …`, and `.system` silently went to the Russian branch: on an English
    /// system the whole UI was English while the counters under the header were Russian.
    static func form(_ n: Int, language: AppLanguage,
                     ru forms: (String, String, String), en pair: (String, String)) -> String {
        language == .ru ? ru(n, forms.0, forms.1, forms.2) : en(n, pair.0, pair.1)
    }
}
