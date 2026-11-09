import Testing
import Foundation
@testable import KeylyLogic

/// Store envelope tests.
///
/// What is checked is not "encodes and decodes" but a SPECIFIC data loss chain that was armed
/// in the product before this change: decoding failed -> the store returned `[]` -> the UI showed empty ->
/// the user added an entry -> `save()` overwrote everything else.
@Suite("Хранилище: пусто, сломано и старый формат — три разных исхода")
struct StoreEnvelopeTests {

    private struct Item: Codable, Equatable {
        var id: Int
        var name: String?
    }

    @Test("Пустой ключ — это «записей нет», а не ошибка")
    func emptyIsNotError() {
        if case .empty = StoreEnvelope.decode(nil, as: Item.self) {} else {
            Issue.record("nil должен давать .empty")
        }
        if case .empty = StoreEnvelope.decode(Data(), as: Item.self) {} else {
            Issue.record("пустые данные должны давать .empty")
        }
    }

    @Test("Круговой проход: что записали, то и прочитали")
    func roundTrip() throws {
        let items = [Item(id: 1, name: "первый"), Item(id: 2, name: nil)]
        let data = try StoreEnvelope.encode(items)
        guard case .ok(let back, let version) = StoreEnvelope.decode(data, as: Item.self) else {
            Issue.record("конверт не прочитался"); return
        }
        #expect(back == items)
        #expect(version == StoreEnvelope.currentVersion)
    }

    @Test("Старый формат — голый массив без версии — читается как версия 0")
    func legacyBareArrayMigrates() throws {
        // This is exactly how ALL stores wrote data before this change.
        let legacy = try JSONEncoder().encode([Item(id: 7, name: "старый")])
        guard case .ok(let items, let version) = StoreEnvelope.decode(legacy, as: Item.self) else {
            Issue.record("легаси-массив обязан читаться, иначе миграция теряет данные"); return
        }
        #expect(items == [Item(id: 7, name: "старый")])
        #expect(version == 0, "версия 0 — признак, что запись надо переписать конвертом")
    }

    @Test("СЛОМАННЫЕ данные НЕ выглядят как пустые — и отдают исходные байты")
    func corruptedIsDistinguishableFromEmpty() {
        // Incompatible model change: it was a number, now it is something else.
        let broken = Data(#"[{"id":"это-не-число","name":"важные данные"}]"#.utf8)
        guard case .corrupted(let raw, let reason) = StoreEnvelope.decode(broken, as: Item.self) else {
            Issue.record("""
                Битые данные прочитались как пустые. Именно этот исход и есть механизм потери:
                интерфейс покажет «ничего нет», человек добавит запись, сохранение затрёт остальное.
                """)
            return
        }
        #expect(raw == broken, "исходные байты обязаны дойти до резервной копии в целости")
        #expect(!reason.isEmpty, "причина нужна в логе — иначе сбой не диагностируется")
    }

    @Test("Запись без необязательного поля НЕ роняет декод всего массива")
    func missingOptionalFieldDoesNotKillTheBatch() {
        // An armed trigger found in an audit: `name` was required, and the first entry without it
        // would have broken decoding of the WHOLE snippet array, working entries included.
        let mixed = Data(#"[{"id":1,"name":"есть имя"},{"id":2}]"#.utf8)
        guard case .ok(let items, _) = StoreEnvelope.decode(mixed, as: Item.self) else {
            Issue.record("запись без опционального поля не должна ронять остальные"); return
        }
        #expect(items.count == 2)
        #expect(items[1].name == nil)
    }

    @Test("Имя файла копии несёт метку времени и имя хранилища")
    func backupFileNameIsStable() {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 7, 26, 6, 5, 4)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = cal.date(from: c)!
        let name = StoreEnvelope.backupFileName(store: "snippets", at: date, calendar: cal)
        #expect(name == "snippets-corrupted-20260726-060504.json")
    }
}

/// Separately, the snippet itself: the name became optional, and the list must show
/// the beginning of the text instead of empty quotes.
@Suite("Сниппет: необязательное имя и подпись в списке")
struct SnippetNameTests {

    @Test("Старая запись с пустым именем читается как «имени нет»")
    func emptyNameBecomesNil() throws {
        let old = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"","content":"почта@example.com"}]"#.utf8)
        let items = try JSONDecoder().decode([Snippet].self, from: old)
        #expect(items.first?.name == nil, "пустая строка и nil — не два разных «нет имени»")
    }

    @Test("Запись вообще без поля name читается и не роняет массив")
    func absentNameDecodes() throws {
        let data = Data(#"[{"id":"00000000-0000-0000-0000-000000000002","content":"текст"}]"#.utf8)
        let items = try JSONDecoder().decode([Snippet].self, from: data)
        #expect(items.count == 1)
        #expect(items.first?.name == nil)
    }

    @Test("Без имени в списке показывается начало текста, а не пустые кавычки")
    func displayTitleFallsBackToContent() {
        let s = Snippet(name: nil, content: "user@example.com")
        #expect(s.displayTitle == "user@example.com")
    }

    @Test("Имя, если задано, побеждает текст")
    func displayTitlePrefersName() {
        let s = Snippet(name: "Почта", content: "user@example.com")
        #expect(s.displayTitle == "Почта")
    }

    @Test("Многострочный текст схлопывается в одну строку и обрезается")
    func displayTitleFlattensAndTruncates() {
        let long = String(repeating: "длинный текст ", count: 10)
        let s = Snippet(name: nil, content: "первая строка\nвторая строка")
        #expect(!s.displayTitle.contains("\n"), "перенос строки в подписи списка ломает высоту строки")
        let t = Snippet(name: nil, content: long)
        #expect(t.displayTitle.count <= 49, "подпись обязана быть ограничена, иначе строка разъедется")
    }

    @Test("Имя из одних пробелов — это отсутствие имени")
    func whitespaceNameIsNoName() {
        let s = Snippet(name: "   ", content: "текст")
        #expect(s.displayTitle == "текст")
    }
}
