import Foundation

/// When the key was last checked.
///
/// Without a time, an "ok" label looks like an eternal truth: the key may have been revoked
/// yesterday while the screen has shown a green "ok" since last month. "ok · 3 days ago" answers
/// the user's real question — "is this still true?".
enum KeyCheckLog {

    private static let storageKey = "apiKeys.lastCheck"

    static func record(keyId: UUID, at date: Date) {
        var map = stored()
        map[keyId.uuidString] = date.timeIntervalSince1970
        UserDefaults.standard.set(map, forKey: storageKey)
    }

    static func lastCheck(keyId: UUID) -> Date? {
        guard let seconds = stored()[keyId.uuidString] else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func forget(keyId: UUID) {
        var map = stored()
        map.removeValue(forKey: keyId.uuidString)
        UserDefaults.standard.set(map, forKey: storageKey)
    }

    private static func stored() -> [String: TimeInterval] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: TimeInterval] ?? [:]
    }

    /// One minute is the "just now" threshold. Anything fresher gets rounded to zero by the system
    /// formatter and printed as "in 0 sec.": a check that happened a moment AGO was announced as
    /// a future one. On screen it looked like debug output rather than an answer to "is this
    /// still true".
    static let justNowThreshold: TimeInterval = 60

    /// "3 days ago". Relative time, not a date: the user cares about how FRESH the check is,
    /// not the calendar day it happened on.
    static func humanized(_ date: Date, now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(date)) < justNowThreshold {
            return "keys.checked.justNow".loc
        }
        let formatter = RelativeDateTimeFormatter()
        // Locale follows the UI LANGUAGE, not the system: the language is chosen separately in
        // the app, and on a Russian screen the status came out in English as "in 0 sec." —
        // a single island of a foreign language in a translated line.
        formatter.locale = Locale(identifier: LanguageManager.shared.effective.localeCode ?? "en")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
