import Combine
import SwiftUI

/// Interface language at runtime (picker in Settings → General).
///
/// **Switching WITHOUT a restart.** Apple's standard path (`AppleLanguages` in UserDefaults)
/// requires a restart, and for a menu bar utility "please restart the app" in settings is a
/// poor answer: it lives for weeks and holds state. So strings are taken from the bundle of
/// the SELECTED language on every call, and `@Published` makes SwiftUI redraw immediately.
///
/// Language selection rules live in `AppLanguage` (pure logic, covered by tests) — here it's
/// only resource access and storage.
@MainActor
final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    private static let storageKey = "interfaceLanguage"

    @Published private(set) var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            bundle = Self.resolveBundle(for: language)
            Log.info(.app, "Язык интерфейса: \(language.rawValue)")
        }
    }

    /// Bundle of the selected language. `Bundle.main` if the needed `.lproj` is missing — then the
    /// regular system fallback kicks in instead of an empty UI.
    private var bundle: Bundle

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        // Default — "as in the system". Until the string migration was finished this was Russian:
        // on an English system the translated sections would become English while untranslated
        // ones stayed Russian, and a mixed UI is worse than either pure one. The ratchet
        // `scripts/check-i18n.sh` shows 0 hardcoded strings in the UI — the condition is met.
        //
        // `KEYLY_QA_LANG` overrides the language for capturing states: otherwise an English screen
        // can only be checked by switching the setting by hand, i.e. NOT checked.
        let forced = ProcessInfo.processInfo.environment["KEYLY_QA_LANG"]
            .flatMap(AppLanguage.init(rawValue:))
        let initial = forced ?? stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = initial
        bundle = Self.resolveBundle(for: initial)
    }

    /// Resolved language: `.system` turned into a concrete one from system settings.
    /// Needed by everyone who CHOOSES a string form themselves (number pluralization) rather than
    /// taking a ready one from the catalog: for them `.system` is not a value but an open question.
    var effective: AppLanguage {
        AppLanguage.resolve(language, systemPreferred: Locale.preferredLanguages)
    }

    func set(_ newLanguage: AppLanguage) {
        language = newLanguage
    }

    /// Localized string by key. `key` also serves as the fallback: if there's no translation, the
    /// key shows on screen — noticeable at once, unlike an empty string.
    func string(_ key: String, table: String? = nil) -> String {
        bundle.localizedString(forKey: key, value: key, table: table)
    }

    private static func resolveBundle(for language: AppLanguage) -> Bundle {
        let effective = AppLanguage.resolve(language, systemPreferred: Locale.preferredLanguages)
        guard let code = effective.localeCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path)
        else { return .main }
        return localized
    }
}

/// String access from views. The short form is deliberate: a long call doesn't stick, and
/// authors go back to hardcoding.
///
/// `"settings.general".loc` — a string in the language chosen by the USER, not the system.
extension String {
    @MainActor var loc: String { LanguageManager.shared.string(self) }

    /// With substitution: `"voice.recorded".loc(3)`.
    @MainActor func loc(_ arguments: CVarArg...) -> String {
        String(format: LanguageManager.shared.string(self), arguments: arguments)
    }
}
