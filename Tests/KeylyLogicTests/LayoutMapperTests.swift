import Testing
@testable import KeylyLogic

/// Layout conversion is the core of the main feature. The tests pin down not only "it works"
/// but also the LIMITS: where per-character guessing fundamentally cannot be right.
struct LayoutMapperTests {

    // MARK: - Basic conversion

    @Test("Русское слово, набранное на EN-раскладке, восстанавливается")
    func enTypedRussian() {
        #expect(LayoutMapper.convert("ghbdtn") == "привет")
        #expect(LayoutMapper.convert("Ghbdtn") == "Привет")
    }

    @Test("Английское слово, набранное на RU-раскладке, восстанавливается")
    func ruTypedEnglish() {
        #expect(LayoutMapper.convert("руддщ") == "hello")
        #expect(LayoutMapper.convert("Руддщ") == "Hello")
    }

    @Test("Символы вне таблиц проходят насквозь")
    func passthrough() {
        // Space, newline, emoji, digits are not altered.
        #expect(LayoutMapper.convert(" ") == " ")
        #expect(LayoutMapper.convert("\n") == "\n")
        #expect(LayoutMapper.convert("🙂") == "🙂")
        #expect(LayoutMapper.convert("") == "")
    }

    @Test("Перенос строки сохраняется внутри многострочного текста")
    func newlineSurvivesInsideText() {
        // Matters for layout switching: converting a SELECTED paragraph is a normal scenario,
        // and the presence of \n decides the transport (typing vs. paste).
        let converted = LayoutMapper.convert("ghbdtn\nrfr ltkf")
        #expect(converted == "привет\nкак дела")
        #expect(converted.contains("\n"))
    }

    // MARK: - Table integrity

    @Test("Таблицы одинаковой длины — иначе zip молча обрежет хвост")
    func tablesSameLength() {
        // The lists are built with zip: with different lengths some characters will NEVER
        // map, silently. The test catches this on any table edit.
        #expect(LayoutMapper.layout1.count == LayoutMapper.layout2.count)
    }

    @Test("Внутри одной таблицы нет повторов — иначе один символ затрёт другой в словаре")
    func noDuplicatesWithinTable() {
        #expect(Set(LayoutMapper.layout1).count == LayoutMapper.layout1.count,
                "повтор в layout1 — часть отображений потеряется")
        #expect(Set(LayoutMapper.layout2).count == LayoutMapper.layout2.count,
                "повтор в layout2 — часть отображений потеряется")
    }

    // MARK: - Method limit: ambiguous characters

    @Test("Повторная конвертация возвращает исходное — для всех символов, кроме известных восьми")
    func doubleConvertIsUndo() {
        // The user undoes a wrong conversion by pressing the hotkey again, so
        // convert(convert(x)) == x must hold. It holds everywhere EXCEPT the eight characters below.
        for ch in LayoutMapper.layout1 + LayoutMapper.layout2 where !Self.notUndoable.contains(ch) {
            let there = LayoutMapper.convert(String(ch))
            let back = LayoutMapper.convert(there)
            #expect(back == String(ch), "«\(ch)» → «\(there)» → «\(back)» — повторная конвертация не вернула исходное")
        }
    }

    @Test("Восемь символов не откатываются повторной конвертацией — предел метода, а не опечатка")
    func knownNotUndoable() {
        // Why: the image of these characters is itself a key of the EN->RU dictionary, which
        // is checked first. "@" -> "\"", but "\"" is also in the EN table -> the second pass
        // gives Cyrillic E (U+042D), not "@". From ONE character you cannot tell which layout it was
        // typed in: this is the limit of per-character guessing, not an implementation bug.
        //
        // The one-way conversion is CORRECT (@ really sits on the "\"" key).
        // What breaks is undo: the user presses the hotkey again and gets garbage.
        //
        // The real fix is DIRECTED conversion that knows the current layout
        // (the app knows it: switchKeyboardLayoutIfNeeded).
        // The test pins the current contract so that changing it is a conscious decision.
        #expect(LayoutMapper.convert("@") == "\"")
        #expect(LayoutMapper.convert("\"") == "Э")   // no way back from here
        #expect(LayoutMapper.convert("~") == "[")
        #expect(LayoutMapper.convert("[") == "х")
    }

    @Test("Набор необратимых символов не изменился незаметно")
    func notUndoableSetIsStable() {
        // A table edit may add a new irreversible character: the test will fail, and that will be
        // a conscious decision, not "somehow stopped reverting" half a year later.
        let computed = Set((LayoutMapper.layout1 + LayoutMapper.layout2).filter { ch in
            LayoutMapper.convert(LayoutMapper.convert(String(ch))) != String(ch)
        })
        #expect(computed == Self.notUndoable,
                "изменился набор необратимых символов: \(computed.sorted())")
    }

    /// Characters for which converting again does NOT return the original (see `knownNotUndoable`).
    private static let notUndoable: Set<Character> = ["`", "~", "@", "$", "%", "^", "&", "*"]
}
