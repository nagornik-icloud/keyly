import Testing
import AppKit
import Carbon.HIToolbox
@testable import KeylyLogic

/// System combinations are rejected.
@Suite struct SystemHotKeysTests {

    @Test func блокируетВыходИЗакрытиеОкна() {
        #expect(SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command]))
        #expect(SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command]))
    }

    @Test func блокируетПереключениеИSpotlight() {
        #expect(SystemHotKeys.isReserved(keyCode: UInt16(kVK_Tab), modifiers: [.command]))
        #expect(SystemHotKeys.isReserved(keyCode: UInt16(kVK_Space), modifiers: [.command]))
    }

    @Test func блокируетНастройкиИСкрытие() {
        #expect(SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_Comma), modifiers: [.command]))
        #expect(SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_H), modifiers: [.command]))
    }

    /// An added modifier makes the combination DIFFERENT: ⌥⌘Q does not belong to the system,
    /// and forbidding it would take free combinations away from the user for no reason.
    @Test func лишнийМодификаторСнимаетЗапрет() {
        #expect(!SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command, .option]))
        #expect(!SystemHotKeys.isReserved(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift]))
    }

    /// Product defaults must not fall under its own ban, otherwise the very first
    /// launch would greet the user with "combination is taken by the system".
    @Test func дефолтыПродуктаНеЗапрещены() {
        #expect(!SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_L), modifiers: [.command, .option]))
        #expect(!SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_E), modifiers: [.command, .option]))
        #expect(!SystemHotKeys.isReserved(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .option]))
    }

    @Test func функциональнаяКлавишаНеСистемная() {
        #expect(!SystemHotKeys.isReserved(keyCode: UInt16(kVK_F13), modifiers: []))
    }
}

/// Found in a real run: one physical key arrives with two codes.
@Suite struct KeyCodeEquivalentsTests {

    /// A voice hotkey was recorded as code 176 (media F5 on the built-in keyboard),
    /// while the same key on an external keyboard sends 96, and recording did not start at all.
    @Test func медиаИСтандартныйКодF5ЭтоОднаКлавиша() {
        #expect(KeyCodeEquivalents.same(176, 96))
        #expect(KeyCodeEquivalents.same(96, 176))
    }

    @Test func весьРядF3F6Парный() {
        #expect(KeyCodeEquivalents.same(160, 99))
        #expect(KeyCodeEquivalents.same(177, 118))
        #expect(KeyCodeEquivalents.same(178, 97))
    }

    /// Different keys are not considered equivalent, otherwise F5 would fire on F6.
    @Test func разныеКлавишиНеПутаются() {
        #expect(!KeyCodeEquivalents.same(176, 178))
        #expect(!KeyCodeEquivalents.same(96, 97))
        #expect(!KeyCodeEquivalents.same(50, 96))
    }

    @Test func саСобойВсегдаСовпадает() {
        #expect(KeyCodeEquivalents.same(122, 122))
    }

    // The test checking that both codes are returned for registration was removed together with `KeyCodeEquivalents.all(for:)`.
    //
    // It guarded the hypothesis "Carbon must be fed both codes", but codes with an
    // equivalent never reach Carbon: they are all media keys, i.e. `isSystemKey`, and
    // `HotKeyManager` routes them to the event tap before `RegisterEventHotKey`. The test was green and
    // guarded nothing: the product never called the function.
}

/// Letter case in a keycap.
@Suite("Буква в кейкапе — прописная, как в macOS")
struct KeyCapLetterCaseTests {

    @Test func буквенноеСочетаниеПечатаетсяПрописной() {
        // macOS writes ⌘Z, not ⌘z; the key is also labeled uppercase. UCKeyTranslate returns
        // lowercase; nobody noticed until the "Shortcuts overview" screen appeared.
        let z = KeyCombo(keyCode: 6, modifiers: [.command, .option])   // kVK_ANSI_Z
        #expect(z.description.hasSuffix("Z"), "получили «\(z.description)»")
        let s = KeyCombo(keyCode: 1, modifiers: [.command, .option])   // kVK_ANSI_S
        #expect(s.description.hasSuffix("S"), "получили «\(s.description)»")
    }

    @Test func низкочернильнаяКлавишаПоказываетВторойЗнакТойЖеКлавиши() {
        // The key left of "1": "`" in a chip is indistinguishable from an empty field, so we show
        // "~", the second character of THE SAME key, larger and the name people say out loud.
        // The English "Grave" used to be here and fixed visibility at the cost of clarity.
        let grave = KeyCombo(keyCode: 50, modifiers: [])
        #expect(grave.description == "~", "получили «\(grave.description)»")
    }

    @Test func заменаНеТрогаетОбычныеБуквыИФРяд() {
        // Substitution only for low-ink glyphs: letters and F keys must stay themselves.
        #expect(KeyCombo(keyCode: 6, modifiers: []).description == "Z")
        #expect(KeyCombo(keyCode: 99, modifiers: []).description == "F3")
    }
}

/// Modifier order in a combination label.
@Suite("Модификаторы печатаются в порядке macOS")
struct ModifierOrderTests {

    @Test func commandПоследний() {
        // Apple prints ⌃⌥⇧⌘; the product printed the exact reverse, and its combinations did not match
        // what the user sees in System Settings and in other apps' menus.
        let combo = KeyCombo(keyCode: 6, modifiers: [.command, .option])
        #expect(combo.description == "⌥⌘Z", "получили «\(combo.description)»")
    }

    @Test func полныйНаборИдётВКанонеApple() {
        let combo = KeyCombo(keyCode: 6, modifiers: [.command, .option, .shift, .control])
        #expect(combo.description == "⌃⌥⇧⌘Z", "получили «\(combo.description)»")
    }

    @Test func одиночныйМодификаторНеЛомается() {
        #expect(KeyCombo(keyCode: 6, modifiers: [.control]).description == "⌃Z")
        #expect(KeyCombo(keyCode: 6, modifiers: [.shift]).description == "⇧Z")
    }
}
