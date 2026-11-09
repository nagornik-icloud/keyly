import Testing
@testable import KeylyLogic

/// Warning dot in the sidebar.
///
/// Before this, one dot meant both "turned off on purpose" and "missing setup", with one
/// caption for both cases: the product shouted about something the user did themselves.
struct ModuleAttentionTests {

    @Test("Выключенный модуль — красная точка, а не «нужно настроить»")
    func disabledWins() {
        #expect(ModuleAttention.resolve(isEnabled: false, hasHotKey: true,
                                        needsKey: false, hasKey: false) == .disabled)
    }

    @Test("Выключенность важнее недостающего ключа — иначе два предупреждения разом")
    func disabledBeatsMissingKey() {
        #expect(ModuleAttention.resolve(isEnabled: false, hasHotKey: false,
                                        needsKey: true, hasKey: false) == .disabled)
    }

    @Test("Включён без хоткея — недонастроен")
    func missingHotKeyIsIncomplete() {
        #expect(ModuleAttention.resolve(isEnabled: true, hasHotKey: false,
                                        needsKey: false, hasKey: false) == .incomplete)
    }

    @Test("Включён с хоткеем, но без нужного ключа — тоже недонастроен")
    func missingKeyIsIncomplete() {
        #expect(ModuleAttention.resolve(isEnabled: true, hasHotKey: true,
                                        needsKey: true, hasKey: false) == .incomplete)
    }

    @Test("Модулю без ключа отсутствие ключа не мешает")
    func keylessModuleIsFine() {
        #expect(ModuleAttention.resolve(isEnabled: true, hasHotKey: true,
                                        needsKey: false, hasKey: false) == .none)
    }

    @Test("Всё на месте — точки нет")
    func readyHasNoDot() {
        let ready = ModuleAttention.resolve(isEnabled: true, hasHotKey: true,
                                            needsKey: true, hasKey: true)
        #expect(ready == .none)
        #expect(ready.labelKey == nil)
    }

    @Test("У каждого состояния с точкой есть СВОЯ подпись")
    func statesHaveDistinctLabels() {
        #expect(ModuleAttention.disabled.labelKey != ModuleAttention.incomplete.labelKey)
        #expect(ModuleAttention.disabled.labelKey != nil)
        #expect(ModuleAttention.incomplete.labelKey != nil)
    }
}
