import Foundation

/// Typo-fix strictness — the module has its OWN level scale.
///
/// The typo screen used to show the VOICE scale ("As spoken" / "Tidy up" / "Tidy up and
/// rewrite") backed by the shared `textPolishLevel` key. That was two bugs at once:
///   · `ErrorFixer` did NOT READ that key at all — the prompt was hard-coded, so the switch on
///     the typo screen had no effect on typo fixing (a phantom setting);
///   · meanwhile it silently changed VOICE behavior, because the key was shared.
/// Plus the wording was about speech ("removes 'um' and repetitions") on a screen for text
/// the user had TYPED.
enum ErrorFixLevel: String, CaseIterable, Codable {
    /// Spelling only. Punctuation and paragraphs are left alone.
    case spelling
    /// Spelling and punctuation. The default.
    case punctuation
    /// Same plus light style edits and paragraph splitting. The only level where wording may
    /// change.
    case style

    static let `default`: ErrorFixLevel = .punctuation

    var title: String {
        switch self {
        case .spelling:    return "errorfix.level.spelling".loc
        case .punctuation: return "errorfix.level.punctuation".loc
        case .style:       return "errorfix.level.style".loc
        }
    }

    var subtitle: String {
        switch self {
        case .spelling:    return "errorfix.level.spelling.hint".loc
        case .punctuation: return "errorfix.level.punctuation.hint".loc
        case .style:       return "errorfix.level.style.hint".loc
        }
    }

    static var current: ErrorFixLevel {
        ErrorFixLevel(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.errorFixLevel) ?? "")
            ?? .default
    }

    /// System prompt for this level. It must match the label on screen: "label says one thing,
    /// prompt does another" is exactly why the user couldn't know what they'd get. The wording
    /// itself lives in `ErrorFixPrompt` — a pure type with no dependencies, included in the
    /// test package: a bug hid in the prompt text twice in a row, and the only way to catch it
    /// was a manual run in another app with a real model request.
    func systemPrompt(isFragment: Bool = false) -> String {
        ErrorFixPrompt.text(for: promptLevel, isFragment: isFragment)
    }

    private var promptLevel: ErrorFixPrompt.Level {
        switch self {
        case .spelling:    return .spelling
        case .punctuation: return .punctuation
        case .style:       return .style
        }
    }
}
