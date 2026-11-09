import Foundation

/// Interface language (ru + en; picker — Settings → General).
///
/// Pure logic without Bundle/UI, so the language selection rules are covered by unit tests:
/// this is where it's easy to go wrong silently — a wrong language code doesn't crash, it
/// gives a Russian user an English interface.
enum AppLanguage: String, CaseIterable, Codable {
    /// As in the system — the default: a utility must not impose a language different from the system's.
    case system
    case ru
    case en

    /// Locale code for loading resources. `nil` for `.system` — use the system language order.
    var localeCode: String? {
        switch self {
        case .system: return nil
        case .ru:     return "ru"
        case .en:     return "en"
        }
    }

    /// Name in ITS OWN language: in a language list people look for a familiar word, not a
    /// translation (the Russian option shows its Russian name, not "Russian", even in an English UI).
    var nativeName: String {
        switch self {
        case .system: return "system" // labeled with a localized string, not hardcoded
        case .ru:     return "Русский"
        case .en:     return "English"
        }
    }

    /// Which language to actually apply when `.system` is selected.
    /// The OS gives the preference order; take the first supported one, otherwise English.
    static func resolve(_ selected: AppLanguage, systemPreferred: [String]) -> AppLanguage {
        guard selected == .system else { return selected }
        for tag in systemPreferred {
            // Tags come as "ru", "ru-RU", "en-GB" — compare by the base language.
            let base = tag.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if let match = AppLanguage(rawValue: base), match != .system { return match }
        }
        return .en
    }
}
