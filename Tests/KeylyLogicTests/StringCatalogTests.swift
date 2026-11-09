import Foundation
import Testing

/// We check the SHIPPED string catalog, not constants in code: the risk is in the translation.
/// The badge fits one line; the English version of the same phrase is sometimes longer than the Russian, and
/// the tail gets cut with an ellipsis, silently, on the user's machine.
struct StringCatalogTests {

    /// Badge line length cap. Keep in sync with `BadgeText.maxCharacters`
    /// (it lives in the UI layer and is not part of this package).
    static let badgeMaxCharacters = 34

    private static let catalogURL: URL = {
        // Walk up from the test file to the repository root: Tests/KeylyLogicTests/<this file>.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Keyly/Resources/Localizable.xcstrings")
    }()

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let state: String; let value: String }
                let stringUnit: Unit
            }
            /// Optional: during a build Xcode ITSELF adds stubs to the catalog for literals found in
            /// code; they have no translation section yet. That is the visible i18n debt.
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func load() throws -> Catalog {
        let data = try Data(contentsOf: Self.catalogURL)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// OUR keys look like `section.item`: Latin, dots, no spaces. Xcode auto-stubs
    /// are the Russian phrases from code themselves; their completeness is checked not here but by the ratchet
    /// `scripts/check-i18n.sh`, which makes sure their number only goes down.
    private func ourKeys(_ catalog: Catalog) -> [String: Catalog.Entry] {
        catalog.strings.filter { key, _ in
            key.contains(".") && !key.contains(" ")
                && key.allSatisfy { $0.isASCII }
        }
    }

    @Test("Каталог строк читается и не пуст")
    func catalogLoads() throws {
        let catalog = try load()
        #expect(!catalog.strings.isEmpty)
        #expect(catalog.sourceLanguage == "ru")
    }

    @Test("Каждый ключ переведён на ВСЕ языки — иначе на экране окажется сам ключ")
    func everyKeyCoversEveryLanguage() throws {
        let catalog = try load()
        let languages = Set(ourKeys(catalog).values.flatMap { $0.localizations?.keys ?? [:].keys })
        #expect(languages == ["ru", "en"], "языки каталога: \(languages.sorted())")

        for (key, entry) in ourKeys(catalog) {
            for language in languages {
                let unit = entry.localizations?[language]?.stringUnit
                #expect(unit != nil, "«\(key)» не переведён на \(language)")
                #expect(unit?.value.isEmpty == false, "«\(key)» пустой перевод на \(language)")
            }
        }
    }

    @Test("Строки бейджа помещаются в одну строку НА ВСЕХ языках")
    func badgeStringsFitInEveryLanguage() throws {
        let catalog = try load()
        for (key, entry) in ourKeys(catalog) where key.hasPrefix("badge.") {
            for (language, localization) in entry.localizations ?? [:] {
                let value = localization.stringUnit.value
                #expect(value.count <= Self.badgeMaxCharacters,
                        "«\(key)» [\(language)] — \(value.count) симв. при потолке \(Self.badgeMaxCharacters): «\(value)» обрежется")
            }
        }
    }

    @Test("Нет непереведённых заготовок и пробелов по краям")
    func noStubsOrStrayWhitespace() throws {
        let catalog = try load()
        for (key, entry) in ourKeys(catalog) {
            for (language, localization) in entry.localizations ?? [:] {
                let unit = localization.stringUnit
                #expect(unit.state == "translated", "«\(key)» [\(language)] в состоянии \(unit.state)")
                #expect(unit.value == unit.value.trimmingCharacters(in: .whitespacesAndNewlines),
                        "«\(key)» [\(language)] — лишние пробелы по краям")
                // A key instead of a translation is a common copy-paste error, visible only on screen.
                #expect(unit.value != key, "«\(key)» [\(language)] — вместо перевода стоит сам ключ")
            }
        }
    }

    /// Learned from our own slip: to make this file green, 75 Russian phrases once went into the catalog
    /// marked as the ENGLISH translation. Tests passed, and an English-speaking user
    /// would have seen a half-Russian interface. A mechanical check is cheaper than discipline.
    @Test("В английских переводах нет кириллицы")
    func englishHasNoCyrillic() throws {
        let catalog = try load()
        // Language names in the picker are written in their own language (Russian in Cyrillic), not "Russian":
        // people look for a familiar word in the list; this is a deliberate exception, not a missing translation.
        let exceptions: Set<String> = ["voice.language.ru", "language.ru"]

        for (key, entry) in ourKeys(catalog) where !exceptions.contains(key) {
            let value = entry.localizations?["en"]?.stringUnit.value ?? ""
            let cyrillic = value.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }
            #expect(cyrillic.isEmpty,
                    "«\(key)» [en] содержит кириллицу: «\(value)» — это русский текст под видом перевода")
        }
    }

    /// A stub without a single translation substitutes THE KEY ITSELF, i.e. a Russian phrase
    /// for an English-speaking user, and does it silently. Such entries used to pile up by the dozen,
    /// because the completeness check only looked at keys like `section.item`.
    @Test("В каталоге не осталось записей без переводов")
    func noEntriesWithoutLocalizations() throws {
        let catalog = try load()
        // On every build Xcode re-extracts literals from code and adds stubs.
        // Some of them have NOTHING to translate, and deleting them is useless, they come back: the product name
        // and strings without a single letter (an empty label, formats "%lld", "%lld %%").
        func isTranslatable(_ key: String) -> Bool {
            guard key != "Keyly" else { return false }
            // Strip format specifiers (%lld, %@, %%) and see whether a WORD is left.
            // Without this "%lld" passes as translatable: it has letters but no meaning.
            let withoutFormats = key.replacingOccurrences(
                of: "%[0-9$.]*(ll|l|h)?[@dfsu%]", with: "", options: .regularExpression)
            return withoutFormats.contains(where: \.isLetter)
        }

        let stubs = catalog.strings
            .filter { key, entry in entry.localizations == nil && isTranslatable(key) }
            .keys.sorted()
        #expect(stubs.isEmpty, "записи без переводов: \(stubs.prefix(10).joined(separator: ", "))")
    }
}
