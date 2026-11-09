import Testing
@testable import KeylyLogic

/// Directed conversion fixes two real defects: ambiguity of
/// per-character guessing and cycling the system layout "round robin".
struct LayoutDirectionTests {

    // MARK: - Directed conversion is ALWAYS reversible

    @Test("Направленная конвертация точно обратима для ВСЕХ символов таблицы")
    func directedConversionIsExactlyReversible() {
        // The main reason the directed path exists: with per-character guessing
        // 8 characters do not revert on a second press. Here there must be none.
        for ch in LayoutMapper.layout1 {
            let ru = LayoutMapper.convert(String(ch), from: .en)
            let back = LayoutMapper.convert(ru, from: .ru)
            #expect(back == String(ch), "EN «\(ch)» → «\(ru)» → «\(back)» — не обратимо")
        }
        for ch in LayoutMapper.layout2 {
            let en = LayoutMapper.convert(String(ch), from: .ru)
            let back = LayoutMapper.convert(en, from: .en)
            #expect(back == String(ch), "RU «\(ch)» → «\(en)» → «\(back)» — не обратимо")
        }
    }

    @Test("Восемь проблемных символов теперь откатываются — то, что не умел старый путь")
    func fixesPreviouslyBrokenCharacters() {
        for ch in ["`", "~", "@", "$", "%", "^", "&", "*"] {
            let there = LayoutMapper.convert(ch, from: .en)
            let back = LayoutMapper.convert(there, from: .ru)
            #expect(back == ch, "«\(ch)» → «\(there)» → «\(back)» — старый дефект не закрыт")
            // For contrast: the old guessing path still gets these characters wrong.
            #expect(LayoutMapper.convert(LayoutMapper.convert(ch)) != ch)
        }
    }

    @Test("Направление уважается: одна и та же строка даёт разный результат")
    func directionMatters() {
        // "q" exists only in the EN table, its Cyrillic counterpart (U+0439) only in RU, but each side must
        // apply EXACTLY its own dictionary without peeking into the other.
        #expect(LayoutMapper.convert("q", from: .en) == "й")
        #expect(LayoutMapper.convert("q", from: .ru) == "q", "RU-проход не должен трогать латиницу")
        #expect(LayoutMapper.convert("й", from: .ru) == "q")
        #expect(LayoutMapper.convert("й", from: .en) == "й", "EN-проход не должен трогать кириллицу")
    }

    @Test("Целые фразы конвертируются направленно")
    func wholePhrases() {
        #expect(LayoutMapper.convert("ghbdtn", from: .en) == "привет")
        #expect(LayoutMapper.convert("руддщ", from: .ru) == "hello")
        #expect(LayoutMapper.convert("ghbdtn\nrfr ltkf", from: .en) == "привет\nкак дела")
    }

    // MARK: - Direction is determined from the text, not from the system layout

    @Test("Раскладка определяется по самому тексту")
    func detectsLayoutFromText() {
        #expect(LayoutMapper.detectLayout(of: "ghbdtn") == .en)
        #expect(LayoutMapper.detectLayout(of: "привет") == .ru)
        #expect(LayoutMapper.detectLayout(of: "Ghbdtn") == .en)
        #expect(LayoutMapper.detectLayout(of: "Ёлка") == .ru, "Ё/ё вне основного диапазона — частая дыра")
    }

    @Test("Без букв направление неизвестно — угадывать нельзя")
    func noLettersMeansUnknown() {
        #expect(LayoutMapper.detectLayout(of: "1234") == nil)
        #expect(LayoutMapper.detectLayout(of: "@#$%") == nil)
        #expect(LayoutMapper.detectLayout(of: "") == nil)
        #expect(LayoutMapper.detectLayout(of: "   \n") == nil)
    }

    @Test("В смешанном тексте решает большинство букв")
    func mixedTextUsesMajority() {
        #expect(LayoutMapper.detectLayout(of: "привет hi") == .ru)
        #expect(LayoutMapper.detectLayout(of: "hello да") == .en)
        #expect(LayoutMapper.detectLayout(of: "ab бв") == nil, "поровну — направление неизвестно")
    }

    @Test("Ручное переключение раскладки перед хоткеем НЕ ломает направление")
    func manualLayoutSwitchDoesNotInvertDirection() {
        // A real scenario: the user typed "ghbdtn" in EN, noticed
        // the mistake, FIRST switched the layout to RU themselves, and only then pressed the hotkey.
        // The first implementation read the CURRENT layout (already RU) -> convert(from: .ru) on
        // Latin text does nothing, the word stayed unfixed, and the user's manual switch
        // was reverted. Detection from the text does not depend on this.
        let typed = "ghbdtn"
        let detected = LayoutMapper.detectLayout(of: typed)
        #expect(detected == .en, "текст латинский — раскладка набора EN, что бы ни стояло в системе")
        #expect(LayoutMapper.convert(typed, from: detected!) == "привет")
    }

    @Test("Определение согласовано с конвертацией: результат читается как противоположная раскладка")
    func detectionAgreesWithConversion() {
        for (text, expected) in [("ghbdtn", LayoutMapper.Layout.ru), ("руддщ", .en)] {
            let from = LayoutMapper.detectLayout(of: text)
            #expect(from != nil)
            let converted = LayoutMapper.convert(text, from: from!)
            #expect(LayoutMapper.detectLayout(of: converted) == expected,
                    "«\(text)» → «\(converted)»: результат должен опознаваться как \(expected)")
        }
    }

    // MARK: - Layout pair

    @Test("Канонические US + Russian выбираются, даже когда установлено много раскладок")
    func picksCanonicalPair() {
        let pair = KeyboardLayoutPair.autoDetect(from: [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.Russian",
            "com.apple.keylayout.Ukrainian",
            "com.apple.CharacterPaletteIM",
        ])
        #expect(pair?.enSourceID == "com.apple.keylayout.US")
        #expect(pair?.ruSourceID == "com.apple.keylayout.Russian")
    }

    @Test("Третья раскладка не попадает в пару — именно из-за неё круговое переключение и врало")
    func thirdLayoutNeverEntersPair() {
        let pair = KeyboardLayoutPair.autoDetect(from: [
            "com.apple.keylayout.US", "com.apple.keylayout.Ukrainian", "com.apple.keylayout.Russian",
        ])
        #expect(pair?.enSourceID != "com.apple.keylayout.Ukrainian")
        #expect(pair?.ruSourceID != "com.apple.keylayout.Ukrainian")
    }

    @Test("Нестандартные варианты подхватываются: ABC вместо US, RussianWin вместо Russian")
    func picksVariants() {
        let pair = KeyboardLayoutPair.autoDetect(from: [
            "com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin",
        ])
        #expect(pair?.enSourceID == "com.apple.keylayout.ABC")
        #expect(pair?.ruSourceID == "com.apple.keylayout.RussianWin")
    }

    @Test("Без одной из сторон пары нет — фича должна молчать, а не переключать наугад")
    func noPairWhenSideMissing() {
        #expect(KeyboardLayoutPair.autoDetect(from: ["com.apple.keylayout.US"]) == nil)
        #expect(KeyboardLayoutPair.autoDetect(from: ["com.apple.keylayout.Russian"]) == nil)
        #expect(KeyboardLayoutPair.autoDetect(from: []) == nil)
    }

    @Test("Русская раскладка не опознаётся как английская — «Russian» содержит «us»")
    func russianIsNotMistakenForEnglish() {
        // Regression test for a real bug: a loose case-insensitive search for the "US" marker
        // found it inside "r-US-sian", and the Russian layout became the "English" side
        // of the pair; conversion direction would flip for everyone who
        // does not have the US layout installed. Only the last component of the id may be compared.
        let onlyRussian = KeyboardLayoutPair.autoDetect(from: ["com.apple.keylayout.Russian"])
        #expect(onlyRussian == nil, "русская раскладка подставилась вместо английской")

        // And in the mixed case the sides are not confused either.
        let pair = KeyboardLayoutPair.autoDetect(from: [
            "com.apple.keylayout.Russian", "com.apple.keylayout.ABC",
        ])
        #expect(pair?.ruSourceID == "com.apple.keylayout.Russian")
        #expect(pair?.enSourceID == "com.apple.keylayout.ABC")
    }

    @Test("Выбор пары детерминирован — не «прыгает» между запусками")
    func detectionIsDeterministic() {
        let ids = ["com.apple.keylayout.British", "com.apple.keylayout.ABC",
                   "com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian"]
        let first = KeyboardLayoutPair.autoDetect(from: ids)
        for _ in 0..<5 {
            #expect(KeyboardLayoutPair.autoDetect(from: ids) == first)
        }
        // Canonical Russian takes priority over RussianWin.
        #expect(first?.ruSourceID == "com.apple.keylayout.Russian")
    }

    @Test("Пара из ДВУХ ОДИНАКОВЫХ сторон невозможна — иначе переключение тихо ломается")
    func rejectsIdenticalSides() {
        // If the sides were equal, `layout(for:)` would always answer .en (the matching case
        // is checked first), and `opposite(of:)` would return the same layout: switching
        // would stop working without a single error in the UI.
        #expect(KeyboardLayoutPair(enSourceID: "same.id", ruSourceID: "same.id") == nil)
        #expect(KeyboardLayoutPair(enSourceID: "", ruSourceID: "ru.id") == nil, "пустая сторона — не пара")
        #expect(KeyboardLayoutPair(enSourceID: "en.id", ruSourceID: "") == nil)
        #expect(KeyboardLayoutPair(enSourceID: "en.id", ruSourceID: "ru.id") != nil)
    }

    @Test("Сторона определяется по id, чужая раскладка даёт nil")
    func resolvesSide() {
        let pair = KeyboardLayoutPair(enSourceID: "en.id", ruSourceID: "ru.id")!
        #expect(pair.layout(for: "en.id") == .en)
        #expect(pair.layout(for: "ru.id") == .ru)
        #expect(pair.layout(for: "ua.id") == nil, "чужой источник не должен притворяться нашим")
    }

    @Test("Противоположная сторона — то, на что переключаем систему")
    func oppositeSide() {
        let pair = KeyboardLayoutPair(enSourceID: "en.id", ruSourceID: "ru.id")!
        #expect(pair.opposite(of: .en) == "ru.id")
        #expect(pair.opposite(of: .ru) == "en.id")
    }
}
