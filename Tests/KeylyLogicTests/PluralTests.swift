import Testing
@testable import KeylyLogic

/// Plural forms for numbers. The BOUNDARIES are tested, because that is what breaks:
/// 11–14 take the third form even though they end in 1–4, and "11" taking the form for 1
/// is the most common mistake of a hand-written implementation.
@Suite("Склонение: границы, а не типовые случаи")
struct PluralTests {

    private let ru = ("исправление", "исправления", "исправлений")
    private let en = ("fix", "fixes")

    @Test("Русский: одна форма на 1, 21, 101 — но НЕ на 11")
    func russianOne() {
        for n in [1, 21, 101, 1_001] {
            #expect(Plural.ru(n, ru.0, ru.1, ru.2) == "исправление", "n = \(n)")
        }
        #expect(Plural.ru(11, ru.0, ru.1, ru.2) == "исправлений",
                "11 оканчивается на 1, но идёт по третьей форме — классический промах")
    }

    @Test("Русский: вторая форма на 2–4, 22–24 — но НЕ на 12–14")
    func russianFew() {
        for n in [2, 3, 4, 22, 34, 104, 992] {   // 992 -> 92 -> "2" -> second form
            #expect(Plural.ru(n, ru.0, ru.1, ru.2) == "исправления", "n = \(n)")
        }
        for n in [12, 13, 14, 112] {
            #expect(Plural.ru(n, ru.0, ru.1, ru.2) == "исправлений", "n = \(n)")
        }
    }

    @Test("Русский: третья форма на 0, 5–9 и на всё остальное")
    func russianMany() {
        for n in [0, 5, 9, 25, 100, 995] {
            #expect(Plural.ru(n, ru.0, ru.1, ru.2) == "исправлений", "n = \(n)")
        }
    }

    @Test("Английский: единственное только на ровно 1")
    func english() {
        #expect(Plural.en(1, en.0, en.1) == "fix")
        for n in [0, 2, 11, 21, 100] {
            #expect(Plural.en(n, en.0, en.1) == "fixes", "n = \(n)")
        }
    }

    @Test("Отрицательные не ломают правило")
    func negatives() {
        #expect(Plural.ru(-1, ru.0, ru.1, ru.2) == "исправление")
        #expect(Plural.ru(-11, ru.0, ru.1, ru.2) == "исправлений")
        #expect(Plural.en(-1, en.0, en.1) == "fix")
    }

    @Test("Выбор формы по языку интерфейса")
    func byLanguage() {
        #expect(Plural.form(2, language: .ru, ru: ru, en: en) == "исправления")
        #expect(Plural.form(2, language: .en, ru: ru, en: en) == "fixes")
    }
}
