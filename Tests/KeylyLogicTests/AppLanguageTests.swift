import Testing
@testable import KeylyLogic

/// Language selection fails SILENTLY: a wrong code does not crash, it gives a Russian
/// user an English interface. That is why the resolution rules are covered by tests.
struct AppLanguageTests {

    @Test("Явно выбранный язык не переопределяется системой")
    func explicitChoiceWins() {
        #expect(AppLanguage.resolve(.ru, systemPreferred: ["en-US", "de"]) == .ru)
        #expect(AppLanguage.resolve(.en, systemPreferred: ["ru-RU"]) == .en)
    }

    @Test("«Как в системе» берёт первый ПОДДЕРЖИВАЕМЫЙ язык из системного порядка")
    func systemPicksFirstSupported() {
        #expect(AppLanguage.resolve(.system, systemPreferred: ["ru-RU", "en-US"]) == .ru)
        #expect(AppLanguage.resolve(.system, systemPreferred: ["en-GB", "ru"]) == .en)
        // Unsupported languages are skipped instead of dropping the choice to the default right away.
        #expect(AppLanguage.resolve(.system, systemPreferred: ["de-DE", "fr", "ru"]) == .ru)
    }

    @Test("Регион в теге не мешает — сравнение по базовому языку")
    func regionTagsAreHandled() {
        // The system returns "ru-RU", "en-GB", sometimes "ru_RU", and mixed case.
        #expect(AppLanguage.resolve(.system, systemPreferred: ["ru-RU"]) == .ru)
        #expect(AppLanguage.resolve(.system, systemPreferred: ["RU"]) == .ru)
        #expect(AppLanguage.resolve(.system, systemPreferred: ["En-us"]) == .en)
    }

    @Test("Ни одного поддерживаемого языка — английский, а не пустой интерфейс")
    func fallsBackToEnglish() {
        #expect(AppLanguage.resolve(.system, systemPreferred: ["de", "fr", "zh-Hans"]) == .en)
        #expect(AppLanguage.resolve(.system, systemPreferred: []) == .en)
    }

    @Test("resolve никогда не возвращает .system — иначе загрузка бандла зациклится на nil-коде")
    func neverReturnsSystem() {
        for preferred in [["ru"], ["en"], ["de"], [], ["system"]] {
            #expect(AppLanguage.resolve(.system, systemPreferred: preferred) != .system)
        }
    }

    @Test("У .system нет кода локали, у остальных есть")
    func localeCodes() {
        #expect(AppLanguage.system.localeCode == nil)
        #expect(AppLanguage.ru.localeCode == "ru")
        #expect(AppLanguage.en.localeCode == "en")
    }

    @Test("Названия языков — на своём языке, не переводом")
    func nativeNames() {
        // In a language list people look for a FAMILIAR word: the language's own name (Russian in Cyrillic), not "Russian".
        #expect(AppLanguage.ru.nativeName == "Русский")
        #expect(AppLanguage.en.nativeName == "English")
    }
}
