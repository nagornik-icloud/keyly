import AppKit
import Testing
@testable import KeylyLogic

/// Warning about a bare key (no modifiers).
///
/// The requirement sat unimplemented until someone ran into it by eye:
/// a user assigns "]" to layout switching and stops being able to type "]" anywhere at all,
/// with no hint of the cause.
struct BareKeyWarningTests {

    private func combo(_ code: UInt16, _ mods: NSEvent.ModifierFlags = [], system: Bool = false) -> KeyCombo {
        KeyCombo(keyCode: code, modifiers: mods, isSystemKey: system)
    }

    @Test("С модификаторами предупреждать не о чем")
    func modifiedComboIsSilent() {
        #expect(BareKeyWarning.reason(for: combo(0x1E, [.command, .option])) == nil)
    }

    @Test("Пустая комбинация предупреждения не даёт")
    func nilComboIsSilent() {
        #expect(BareKeyWarning.reason(for: nil) == nil)
    }

    @Test("Голая обычная клавиша: предупреждаем, что символ перестанет печататься")
    func bareCharacterWarns() {
        let reason = BareKeyWarning.reason(for: combo(0x1E))
        #expect(reason?.messageKey == "hotkey.bare.character")
    }

    @Test("Голая системная клавиша: называем действие macOS, а не символ")
    func bareSystemKeyNamesTheAction() {
        let reason = BareKeyWarning.reason(for: combo(NXKeyType.soundUp, system: true))
        #expect(reason?.messageKey == "hotkey.bare.system")
        #expect(reason?.actionKey == "key.action.volume")
    }

    @Test("Непечатающая клавиша предупреждает про РАБОТУ, а не про печать")
    func nonPrintingKeysWarnAboutFunction() {
        // "F3 will stop typing" is false: F3 never typed anything.
        //
        // We check the INTENT, not a specific key. The previous version required exactly
        // `hotkey.bare.action`, and so it failed when F3 learned to name Mission
        // Control: the test protected an old defect from its own fix. Both
        // branches satisfy the rule; the one thing forbidden here is promising typing.
        for code: UInt16 in [99, 160, 96, 176, 111, 36, 51, 53, 48, 123] {
            let reason = BareKeyWarning.reason(for: combo(code))
            #expect(reason?.messageKey != "hotkey.bare.character",
                    "код \(code) обещает печать, которой нет")
            #expect(reason != nil, "код \(code) не предупредил вовсе")
        }
    }

    @Test("F3 и F4 называют действие macOS, хотя приходят НЕ как системные")
    func fRowKeysNameTheirAction() {
        // The `guard combo.isSystemKey` guard physically kept the F row out of the action table:
        // the built-in keyboard sends these keys as a plain keyDown with isSystemKey: false.
        // A user taking F3 heard ""F3" will stop working", a restatement of their own
        // action instead of "Mission Control will not open".
        for code: UInt16 in [99, 160] {
            let reason = BareKeyWarning.reason(for: combo(code))
            #expect(reason?.actionKey == "key.action.missionControl", "код \(code)")
        }
        for code: UInt16 in [118, 177] {
            let reason = BareKeyWarning.reason(for: combo(code))
            #expect(reason?.actionKey == "key.action.search", "код \(code)")
        }
    }

    @Test("Код 25 не называет действие: две таблицы спорили, что это за клавиша")
    func code25StaysUnnamed() {
        // `NXKeyType.menu` = 25, and the same code used to be listed as "macOS dictation" (0x19).
        // The chip printed "Menu", the warning said "dictation"; one of them lied. Naming
        // an action wrongly is worse than not naming it.
        let reason = BareKeyWarning.reason(for: combo(25, system: true))
        #expect(reason != nil, "предупредить всё равно обязаны")
        #expect(reason?.actionKey == nil, "неподтверждённое имя действия называть нельзя")
    }

    @Test("Печатающая клавиша по-прежнему предупреждает про печать")
    func printingKeysWarnAboutTyping() {
        // 0x1E is "]", exactly the key that was assigned to layout switching in practice.
        #expect(BareKeyWarning.reason(for: combo(0x1E))?.messageKey == "hotkey.bare.character")
    }

    @Test("Неизвестная системная клавиша всё равно предупреждает — молчать нельзя")
    func unknownSystemKeyStillWarns() {
        let reason = BareKeyWarning.reason(for: combo(0xFF, system: true))
        #expect(reason != nil, "клавиша глушится в любом случае, значит и сказать надо в любом случае")
    }
}

/// Display rule: the warning lives at the MOMENT of assignment, not in the field value.
///
/// A permanent yellow line (repeated every time the screen opened) was removed, and the first
/// fix removed the warning entirely, so users no longer learned that "]" no longer
/// types. These tests hold both boundaries at once.
@Suite("Свежесть предупреждения о голой клавише")
struct BareKeyWarningFreshnessTests {

    private func combo(_ code: UInt16, _ mods: NSEvent.ModifierFlags = []) -> KeyCombo {
        KeyCombo(keyCode: code, modifiers: mods)
    }

    @Test func приНазначенииГолойКлавишиПредупреждаем() {
        let c = combo(0x1E)
        #expect(BareKeyWarning.fresh(current: c, justAssigned: c) != nil)
    }

    @Test func сохранённаяРанееГолаяКлавишаМолчит() {
        // Screen reopened: justAssigned is empty, the value is the same, so no repeat.
        #expect(BareKeyWarning.fresh(current: combo(0x1E), justAssigned: nil) == nil)
    }

    @Test func назначениеДругойКлавишиНеОживляетСтароеПредупреждение() {
        #expect(BareKeyWarning.fresh(current: combo(0x1E), justAssigned: combo(0x1F)) == nil)
    }

    @Test func сМодификаторамиМолчимДажеСразуПослеНазначения() {
        let c = combo(0x1E, [.command, .option])
        #expect(BareKeyWarning.fresh(current: c, justAssigned: c) == nil)
    }

    @Test func пустоеПолеНеПредупреждает() {
        #expect(BareKeyWarning.fresh(current: nil, justAssigned: nil) == nil)
    }
}
