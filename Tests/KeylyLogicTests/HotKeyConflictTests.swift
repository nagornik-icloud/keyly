import Testing
import Foundation
@testable import KeylyLogic

/// A conflict carries the NAME of the function holding the combo and knows whether it can be moved.
@Suite struct HotKeyConflictTests {

    @Test func системуПодвинутьНельзя() {
        #expect(!HotKeyConflictOwner.system.isReleasable)
    }

    @Test func остальныхПодвинутьМожно() {
        #expect(HotKeyConflictOwner.module(.voiceToText).isReleasable)
        #expect(HotKeyConflictOwner.app(id: UUID(), name: "Safari").isReleasable)
        #expect(HotKeyConflictOwner.snippet(id: UUID(), title: "Подпись").isReleasable)
    }

    /// The name is needed EXACTLY where there are many holders and the message text does not name them.
    @Test func имяПодставляетсяТолькоСпискам() {
        #expect(HotKeyConflictOwner.app(id: UUID(), name: "Safari").argument == "Safari")
        #expect(HotKeyConflictOwner.customModule(id: UUID(), name: "Перевод").argument == "Перевод")
        #expect(HotKeyConflictOwner.module(.errorFix).argument == nil)
        #expect(HotKeyConflictOwner.system.argument == nil)
    }

    /// Keys differ: the same text for different holders does not let the user understand
    /// WHAT is taking the combination, and that is the whole point of the message.
    @Test func ключиСообщенийРазличаются() {
        let keys = [
            HotKeyConflictOwner.system,
            .module(.layoutSwitch), .module(.errorFix), .module(.voiceToText),
            .app(id: UUID(), name: "A"),
            .customModule(id: UUID(), name: "B"),
            .snippet(id: UUID(), title: "C"),
        ].map(\.messageKey)
        #expect(Set(keys).count == keys.count)
    }
}
