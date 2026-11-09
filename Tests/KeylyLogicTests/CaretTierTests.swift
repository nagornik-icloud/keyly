import Testing
@testable import KeylyLogic

/// Caret tier decision. Errors here are SILENT: the product either refuses
/// to work in a real field, or treats plain page text as a field and selects
/// the whole page. The latter was caught in a real run.
struct CaretTierTests {

    @Test("Доказанная редактируемость + rect каретки = caret")
    func provenWithRect() {
        let signals = CaretTier.Signals(editability: .proven, hasCaretRect: true)
        #expect(CaretTier.resolve(signals) == .caret)
    }

    @Test("Доказанная редактируемость без rect = editable (Electron)")
    func provenWithoutRect() {
        let signals = CaretTier.Signals(editability: .proven, hasCaretRect: false)
        #expect(CaretTier.resolve(signals) == .editable)
    }

    @Test("Каретка БЕЗ доказанной редактируемости полем не делает")
    func caretAloneIsNotProof() {
        // Exactly that case: clicking article text in Safari returns a caret rect, but you cannot write
        // there. This set of signals used to give .caret, and Cmd+A selected the page.
        let signals = CaretTier.Signals(roleVetoed: true, editability: .unknown, hasCaretRect: true)
        #expect(CaretTier.resolve(signals) == .none)
        #expect(!CaretTier.isEditable(CaretTier.resolve(signals)))
    }

    @Test("Явный отказ AX сильнее списка приложений")
    func deniedBeatsAllowlist() {
        // Read-only NSTextView: the Mail reading pane, the Xcode console. Both apps are in the
        // text-app list, and without this rule the list would nullify the refusal.
        let signals = CaretTier.Signals(editability: .denied, appInAllowlist: true, recentlyTyped: true)
        #expect(CaretTier.resolve(signals) == .none)
    }

    @Test("Роль забракована — обход дерева не спасает")
    func vetoBlocksScan() {
        // Otherwise a walk from the document area would find some unrelated search field on the page
        // and declare the cursor "in a field".
        let signals = CaretTier.Signals(roleVetoed: true, scanFoundEditable: true)
        #expect(CaretTier.resolve(signals) == .none)
    }

    @Test("Хит-тест по клику работает и при забракованной роли фокуса")
    func hitTestSurvivesVeto() {
        // Chrome and Electron return a broken focused element, but the click points to the real field.
        let signals = CaretTier.Signals(roleVetoed: true, hasCaretRect: true, hitTestFoundEditable: true)
        #expect(CaretTier.resolve(signals) == .caret)
    }

    @Test("Догадка по имени приложения даёт только ambiguous и права на Cmd+A не даёт")
    func allowlistIsNotProof() {
        let signals = CaretTier.Signals(appInAllowlist: true)
        #expect(CaretTier.resolve(signals) == .ambiguous)
        #expect(!CaretTier.isEditable(.ambiguous))
    }

    @Test("Недавняя печать без прочих признаков — тоже лишь догадка")
    func recentTypingIsAmbiguous() {
        #expect(CaretTier.resolve(CaretTier.Signals(recentlyTyped: true)) == .ambiguous)
    }

    @Test("Пустые признаки = не поле")
    func nothingKnown() {
        #expect(CaretTier.resolve(CaretTier.Signals()) == .none)
    }
}
