import Foundation
import Testing
@testable import KeylyLogic

/// Ranking fails SILENTLY: a wrong order does not crash, it puts the right snippet second,
/// the user presses Enter without looking and pastes the wrong text. That is worse than an empty list.
struct SnippetSearchTests {

    private func snippet(_ name: String, _ content: String, triggers: [String] = [],
                         enabled: Bool = true) -> Snippet {
        Snippet(name: name, content: content, triggers: triggers, isEnabled: enabled)
    }

    // MARK: - Ranking

    @Test("Пустой запрос показывает все включённые в исходном порядке")
    func emptyQueryShowsAll() {
        let list = [snippet("A", "текст а"), snippet("B", "текст б")]
        #expect(SnippetSearch.rank(list, query: "").map(\.name) == ["A", "B"])
        #expect(SnippetSearch.rank(list, query: "   ").map(\.name) == ["A", "B"])
    }

    @Test("Выключенные не попадают в палитру никогда")
    func disabledNeverShown() {
        let list = [snippet("вкл", "x", triggers: ["зн"]), snippet("выкл", "x", triggers: ["зн"], enabled: false)]
        #expect(SnippetSearch.rank(list, query: "").map(\.name) == ["вкл"])
        #expect(SnippetSearch.rank(list, query: "зн").map(\.name) == ["вкл"])
    }

    @Test("Точный триггер побеждает вхождение в тексте — иначе Enter вставит чужое")
    func exactTriggerBeatsContent() {
        let byTrigger = snippet("почта", "a@b.c", triggers: ["адр"])
        let byContent = snippet("длинный", "здесь внутри есть слово адр и много другого текста")
        let ranked = SnippetSearch.rank([byContent, byTrigger], query: "адр")
        #expect(ranked.first?.name == "почта", "сниппет, названный по триггеру, обязан быть первым")
    }

    @Test("Порядок весов: точный триггер > префикс триггера > имя > текст")
    func scoreOrder() {
        let exact = SnippetSearch.score(snippet("x", "y", triggers: ["адр"]), query: "адр")!
        let prefix = SnippetSearch.score(snippet("x", "y", triggers: ["адрес"]), query: "адр")!
        let byName = SnippetSearch.score(snippet("адрес", "y"), query: "адр")!
        let byText = SnippetSearch.score(snippet("x", "мой адрес"), query: "адр")!
        #expect(exact > prefix)
        #expect(prefix > byName)
        #expect(byName > byText)
    }

    @Test("Не подходящий сниппет исключается, а не уезжает вниз")
    func nonMatchingExcluded() {
        #expect(SnippetSearch.score(snippet("почта", "a@b.c", triggers: ["адр"]), query: "телефон") == nil)
        #expect(SnippetSearch.rank([snippet("почта", "a@b.c")], query: "телефон").isEmpty)
    }

    @Test("Регистр запроса и триггера не важен")
    func caseInsensitive() {
        let list = [snippet("Почта", "a@b.c", triggers: ["АДР"])]
        #expect(SnippetSearch.rank(list, query: "адр").count == 1)
        #expect(SnippetSearch.rank(list, query: "ПОЧ").count == 1)
    }

    @Test("При равном счёте порядок исходного списка сохраняется — иначе строки прыгают")
    func stableOrderOnTie() {
        let list = [snippet("первый", "адрес один"), snippet("второй", "адрес два")]
        #expect(SnippetSearch.rank(list, query: "адрес").map(\.name) == ["первый", "второй"])
    }

    // MARK: - Match by the longest trigger

    @Test("Срабатывает САМЫЙ ДЛИННЫЙ совпавший триггер, а не первый в списке")
    func longestTriggerWins() {
        let short = snippet("короткий", "К", triggers: ["адр"])
        let long = snippet("длинный", "Д", triggers: ["адрес"])
        // The order in the list is deliberately reversed: it must not matter.
        let a = SnippetSearch.matchByLongestTrigger(typed: "пишу адрес", in: [short, long])
        let b = SnippetSearch.matchByLongestTrigger(typed: "пишу адрес", in: [long, short])
        #expect(a?.0.name == "длинный")
        #expect(b?.0.name == "длинный", "drag-reorder не должен менять, какой сниппет сработает")
    }

    @Test("Короткий триггер, который является началом длинного, помечается как неоднозначный")
    func ambiguousPrefixDetected() {
        let short = snippet("короткий", "К", triggers: ["адр"])
        let long = snippet("длинный", "Д", triggers: ["адрес"])
        // This is exactly what broke in a real run: a short trigger ("addr") matched in full before
        // the user could finish typing the longer one ("address"), and the long one never fired.
        #expect(SnippetSearch.hasLongerTriggerStarting(with: "адр", in: [short, long]))
        #expect(!SnippetSearch.hasLongerTriggerStarting(with: "адрес", in: [short, long]))
    }

    @Test("Одинаковая длина неоднозначности не создаёт")
    func sameLengthIsNotAmbiguous() {
        let a = snippet("a", "A", triggers: ["адр"])
        let b = snippet("b", "B", triggers: ["абв"])
        #expect(!SnippetSearch.hasLongerTriggerStarting(with: "адр", in: [a, b]))
    }

    @Test("Выключенный длинный триггер не заставляет короткий ждать")
    func disabledLongerDoesNotBlock() {
        let short = snippet("короткий", "К", triggers: ["адр"])
        let long = snippet("длинный", "Д", triggers: ["адрес"], enabled: false)
        #expect(!SnippetSearch.hasLongerTriggerStarting(with: "адр", in: [short, long]))
    }

    @Test("Регистр не мешает увидеть неоднозначность")
    func ambiguityIgnoresCase() {
        let short = snippet("к", "К", triggers: ["АДР"])
        let long = snippet("д", "Д", triggers: ["адрес"])
        #expect(SnippetSearch.hasLongerTriggerStarting(with: "адр", in: [short, long]))
    }

    @Test("Матч только по ХВОСТУ набранного, не по середине")
    func matchesSuffixOnly() {
        let s = snippet("x", "y", triggers: ["адр"])
        #expect(SnippetSearch.matchByLongestTrigger(typed: "мой адр", in: [s]) != nil)
        #expect(SnippetSearch.matchByLongestTrigger(typed: "адр и ещё", in: [s]) == nil)
    }

    @Test("Выключенный сниппет не срабатывает по триггеру")
    func disabledDoesNotTrigger() {
        let s = snippet("x", "y", triggers: ["адр"], enabled: false)
        #expect(SnippetSearch.matchByLongestTrigger(typed: "адр", in: [s]) == nil)
    }

    // MARK: - Conflict validator

    @Test("Точный дубль триггера находится")
    func findsExactDuplicate() {
        let list = [snippet("A", "a", triggers: ["адр"]), snippet("B", "b", triggers: ["адр"])]
        let conflicts = SnippetSearch.triggerConflicts(in: list)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.isExactDuplicate == true)
    }

    @Test("Префиксное перекрытие находится — короткий съедает ввод до длинного")
    func findsPrefixOverlap() {
        // A short trigger overlaps a longer one with the same prefix: typing the long one, you never reach it.
        let list = [snippet("A", "a", triggers: ["адр"]), snippet("B", "b", triggers: ["адрес"])]
        let conflicts = SnippetSearch.triggerConflicts(in: list)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.isExactDuplicate == false)
    }

    @Test("Непересекающиеся триггеры конфликтом не считаются")
    func noFalseConflicts() {
        let list = [snippet("A", "a", triggers: ["адр"]), snippet("B", "b", triggers: ["тел"])]
        #expect(SnippetSearch.triggerConflicts(in: list).isEmpty)
    }

    @Test("Свои же триггеры внутри одного сниппета конфликтом не считаются")
    func ownTriggersAreNotConflicts() {
        let list = [snippet("A", "a", triggers: ["адр", "адрес"])]
        #expect(SnippetSearch.triggerConflicts(in: list).isEmpty)
    }

    @Test("Выключенный сниппет не создаёт конфликтов — он и не сработает")
    func disabledDoesNotConflict() {
        let list = [snippet("A", "a", triggers: ["адр"]),
                    snippet("B", "b", triggers: ["адр"], enabled: false)]
        #expect(SnippetSearch.triggerConflicts(in: list).isEmpty)
    }
}

/// Overlapping triggers are forbidden.
struct TriggerAllowanceTests {

    private func snippet(_ id: UUID = UUID(), _ triggers: [String]) -> Snippet {
        Snippet(id: id, name: "s", content: "c", triggers: triggers, isEnabled: true)
    }

    @Test("Триггер, начинающийся с существующего, завести нельзя")
    func prefixOfExistingRejected() {
        let existing = [snippet(UUID(), ["адр"])]
        #expect(!SnippetSearch.triggerIsAllowed("адрес", existing: existing, excluding: nil))
    }

    @Test("Триггер, который сам является началом существующего, тоже нельзя")
    func existingIsPrefixRejected() {
        let existing = [snippet(UUID(), ["адрес"])]
        #expect(!SnippetSearch.triggerIsAllowed("адр", existing: existing, excluding: nil))
    }

    @Test("Точный дубль запрещён")
    func duplicateRejected() {
        let existing = [snippet(UUID(), ["адр"])]
        #expect(!SnippetSearch.triggerIsAllowed("АДР", existing: existing, excluding: nil))
    }

    @Test("Непересекающийся триггер разрешён")
    func distinctAllowed() {
        let existing = [snippet(UUID(), ["адр"])]
        #expect(SnippetSearch.triggerIsAllowed("тел", existing: existing, excluding: nil))
    }

    @Test("Собственные триггеры сниппета себе не мешают")
    func ownTriggersExcluded() {
        let id = UUID()
        let existing = [snippet(id, ["адр"])]
        #expect(SnippetSearch.triggerIsAllowed("адрес", existing: existing, excluding: id))
    }
}

/// Trigger firing mode.
struct TriggerModeTests {

    private func snippet(_ triggers: [String], _ mode: Snippet.TriggerMode) -> Snippet {
        Snippet(name: "s", content: "c", triggers: triggers, isEnabled: true, triggerMode: mode)
    }

    @Test("Режим «сразу» срабатывает на последнем символе триггера")
    func immediateFiresOnLastCharacter() {
        let s = snippet(["@@em"], .immediate)
        let hit = SnippetSearch.match(typed: "текст @@em", justTyped: "m", in: [s])
        #expect(hit?.trigger == "@@em")
        #expect(hit?.separator == nil)
    }

    @Test("Режим «после разделителя» на последнем символе НЕ срабатывает")
    func afterSeparatorWaits() {
        let s = snippet(["адр"], .afterSeparator)
        #expect(SnippetSearch.match(typed: "пишу адр", justTyped: "р", in: [s]) == nil)
    }

    @Test("Режим «после разделителя» срабатывает на разделителе и возвращает его")
    func afterSeparatorFiresOnSeparator() {
        let s = snippet(["адр"], .afterSeparator)
        let hit = SnippetSearch.match(typed: "пишу адр ", justTyped: " ", in: [s])
        #expect(hit?.trigger == "адр")
        #expect(hit?.separator == " ")
    }

    @Test("Разделитель не поднимает когорту «сразу» — она уже отработала")
    func separatorDoesNotRefireImmediate() {
        let s = snippet(["@@em"], .immediate)
        #expect(SnippetSearch.match(typed: "@@em ", justTyped: " ", in: [s]) == nil)
    }

    @Test("Триггер внутри слова не стреляет в режиме «после разделителя»")
    func noFireInsideWord() {
        // This is exactly why this mode is the default: a short trigger inside a longer word.
        let s = snippet(["адр"], .afterSeparator)
        #expect(SnippetSearch.match(typed: "адресат", justTyped: "т", in: [s]) == nil)
    }

    @Test("Enter и таб — тоже разделители")
    func newlineAndTabAreSeparators() {
        let s = snippet(["адр"], .afterSeparator)
        #expect(SnippetSearch.match(typed: "адр\n", justTyped: "\n", in: [s])?.trigger == "адр")
        #expect(SnippetSearch.match(typed: "адр\t", justTyped: "\t", in: [s])?.trigger == "адр")
    }

    @Test("Старые записи без режима считаются «сразу» — поведение не меняется молча")
    func legacyDecodesAsImmediate() throws {
        let json = """
        {"id":"\(UUID().uuidString)","content":"c","triggers":["адр"],"isEnabled":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Snippet.self, from: json)
        #expect(decoded.triggerMode == .immediate)
    }

    @Test("Новые записи по умолчанию ждут разделителя")
    func newDefaultsToAfterSeparator() {
        #expect(Snippet(content: "c").triggerMode == .afterSeparator)
    }
}
