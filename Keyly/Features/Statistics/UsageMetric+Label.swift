import Foundation

/// Counter labels with plural forms by number.
///
/// They live here, not in the UI or the string catalog, for two reasons. The Russian form has
/// three variants by number (1 / 2–4 / 5+), English has two; `.xcstrings` can express this with
/// variations, but then one label ends up split between the catalog and the form-picking code.
/// Second: the label belongs to the METRIC, not to a screen — both Overview and the menu bar
/// show counters, and they need one source.
extension UsageMetric {

    /// Three Russian forms: 1 / 2–4 / 5+.
    var russianForms: (String, String, String) {
        switch self {
        case .errorsFixed:
            return ("исправление", "исправления", "исправлений")
        case .dictatedWords:
            return ("слово надиктовано", "слова надиктовано", "слов надиктовано")
        case .layoutSwitches:
            return ("переключение раскладки", "переключения раскладки", "переключений раскладки")
        case .snippetsInserted:
            return ("вставка сниппета", "вставки сниппета", "вставок сниппетов")
        }
    }

    /// Two English forms: singular / plural.
    var englishForms: (String, String) {
        switch self {
        case .errorsFixed:      return ("fix", "fixes")
        case .dictatedWords:    return ("word dictated", "words dictated")
        case .layoutSwitches:   return ("layout switch", "layout switches")
        case .snippetsInserted: return ("snippet insert", "snippet inserts")
        }
    }

    /// Ready label for a number: `.errorsFixed.label(for: 2, language: .ru)` → the Russian "few" form.
    func label(for count: Int, language: AppLanguage) -> String {
        Plural.form(count, language: language, ru: russianForms, en: englishForms)
    }
}
