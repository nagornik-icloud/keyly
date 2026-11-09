import Foundation
import Testing
@testable import KeylyLogic

/// The `Snippet` decoder carries migration from the old format. Such code breaks silently:
/// the user simply loses snippets after an update, and no gate would notice.
struct SnippetDecodingTests {

    private func decode(_ json: String) throws -> Snippet {
        try JSONDecoder().decode(Snippet.self, from: Data(json.utf8))
    }

    @Test("Старый формат: одиночный triggerSequence превращается в массив триггеров")
    func migratesLegacyTriggerSequence() throws {
        let s = try decode("""
        {"id":"\(UUID().uuidString)","name":"Адрес","content":"ул. Ленина 1","triggerSequence":"адр"}
        """)
        #expect(s.triggers == ["адр"], "триггер из старого формата потерян — сниппет перестанет срабатывать")
    }

    @Test("Пустой legacy-триггер не превращается в пустой триггер")
    func ignoresEmptyLegacyTrigger() throws {
        // An empty trigger string would match anything, which is worse than having no trigger.
        let s = try decode("""
        {"id":"\(UUID().uuidString)","name":"X","content":"Y","triggerSequence":""}
        """)
        #expect(s.triggers.isEmpty)
    }

    @Test("Новый формат читается как есть и не затирается миграцией")
    func keepsModernTriggers() throws {
        let s = try decode("""
        {"id":"\(UUID().uuidString)","name":"X","content":"Y","triggers":["адр","addr"]}
        """)
        #expect(s.triggers == ["адр", "addr"])
    }

    @Test("Сниппет без флага isEnabled считается включённым")
    func defaultsToEnabled() throws {
        // Otherwise snippets saved before the flag existed would silently turn off for everyone.
        let s = try decode("""
        {"id":"\(UUID().uuidString)","name":"X","content":"Y"}
        """)
        #expect(s.isEnabled)
    }

    @Test("Явно выключенный сниппет остаётся выключенным")
    func respectsExplicitDisabled() throws {
        let s = try decode("""
        {"id":"\(UUID().uuidString)","name":"X","content":"Y","isEnabled":false}
        """)
        #expect(!s.isEnabled)
    }

    @Test("Сниппет переживает круг кодирования без потерь")
    func roundTripsThroughCoding() throws {
        let original = Snippet(name: "Почта", content: "a@b.c", triggers: ["почта"], isEnabled: false)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Snippet.self, from: data)
        #expect(restored == original)
    }
}
