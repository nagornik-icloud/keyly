import Testing
@testable import KeylyLogic

/// Undo edits someone else's text, and an error here does not crash, it silently destroys
/// what was typed by hand. So both "it worked" and every refusal branch are covered.
@Suite("Отмена: что именно возвращаем")
struct UndoPlanTests {

    // MARK: - diff

    @Test("Вставка в конец: изменённым считается только дописанный хвост")
    func diffAppend() {
        let d = UndoPlan.diff(before: "Привет", after: "Привет, мир")
        #expect(d.old == "")
        #expect(d.new == ", мир")
    }

    @Test("Замена в середине: общий префикс и суффикс не попадают в диапазон")
    func diffMiddle() {
        let d = UndoPlan.diff(before: "сегодня ghbdtn завтра", after: "сегодня привет завтра")
        #expect(d.old == "ghbdtn")
        #expect(d.new == "привет")
    }

    @Test("Полная замена поля: диапазон — весь текст")
    func diffWhole() {
        let d = UndoPlan.diff(before: "аaa", after: "ббб")
        #expect(d.old == "аaa")
        #expect(d.new == "ббб")
    }

    @Test("Составные символы не режутся посередине")
    func diffGraphemes() {
        // A family emoji is one Character made of several scalars. Cutting by UTF-16 would give
        // half a cluster, and a broken character would land in the user's field.
        let d = UndoPlan.diff(before: "тест 👨‍👩‍👧‍👦 хвост", after: "тест 🙂 хвост")
        #expect(d.old == "👨‍👩‍👧‍👦")
        #expect(d.new == "🙂")
    }

    // MARK: - restoredText, success cases

    @Test("Поле не трогали после нас — возвращаем снимок целиком")
    func restoreUntouched() {
        let restored = UndoPlan.restoredText(current: "Привет, мир",
                                             before: "Привет", after: "Привет, мир")
        #expect(restored == "Привет")
    }

    @Test("Пользователь дописал ПОСЛЕ нашей вставки — его текст сохраняется")
    func restoreKeepsLaterEdits() {
        // This is the main scenario undo was rewritten for: the field used to be
        // restored in full, and text typed by hand afterwards was lost.
        let restored = UndoPlan.restoredText(current: "сегодня привет завтра И ещё от руки",
                                             before: "сегодня ghbdtn завтра",
                                             after: "сегодня привет завтра")
        #expect(restored == "сегодня ghbdtn завтра И ещё от руки")
    }

    @Test("Пользователь дописал ПЕРЕД нашей вставкой — его текст тоже сохраняется")
    func restoreKeepsEarlierEdits() {
        let restored = UndoPlan.restoredText(current: "Заголовок. сегодня привет завтра",
                                             before: "сегодня ghbdtn завтра",
                                             after: "сегодня привет завтра")
        #expect(restored == "Заголовок. сегодня ghbdtn завтра")
    }

    // MARK: - restoredText, refusals

    @Test("Правка ВПЛОТНУЮ к нашему фрагменту не мешает — он цел, возвращаем только его")
    func restoreWithAdjacentEdit() {
        // The user typed "!!!" right after our word. The word itself is untouched, so it is
        // unambiguously ours: restore it and leave the exclamation marks in place.
        let restored = UndoPlan.restoredText(current: "сегодня привет!!! завтра",
                                             before: "сегодня ghbdtn завтра",
                                             after: "сегодня привет завтра")
        #expect(restored == "сегодня ghbdtn!!! завтра")
    }

    @Test("Отредактировали САМ фрагмент — отказ, ничего не трогаем")
    func refuseWhenFragmentEdited() {
        // A typo inside our word (a doubled letter). There is no verbatim match anymore,
        // and we have no right to guess that this is the word meant.
        let restored = UndoPlan.restoredText(current: "сегодня привеет завтра",
                                             before: "сегодня ghbdtn завтра",
                                             after: "сегодня привет завтра")
        #expect(restored == nil)
    }

    @Test("Фрагмент встречается дважды — отказ, угадывать не имеем права")
    func refuseWhenAmbiguous() {
        // Layout switching edits one word; the same word easily occurs in the field again.
        // Replacing "some" one of two means corrupting the text half the time.
        // The "!" tail is required: without it the fast path "field untouched" would fire, and
        // the test would check the wrong branch.
        let restored = UndoPlan.restoredText(current: "привет и ещё раз привет!",
                                             before: "ghbdtn и ещё раз привет",
                                             after: "привет и ещё раз привет")
        #expect(restored == nil)
    }

    @Test("Поле не трогали — быстрый путь возвращает снимок даже при повторах фрагмента")
    func restoreExactSnapshotBeatsAmbiguity() {
        // Same ambiguous text, but the field is exactly as we left it:
        // no doubt, the "before" snapshot is known to be accurate.
        let restored = UndoPlan.restoredText(current: "привет и ещё раз привет",
                                             before: "ghbdtn и ещё раз привет",
                                             after: "привет и ещё раз привет")
        #expect(restored == "ghbdtn и ещё раз привет")
    }

    @Test("Поле очистили — отказ")
    func refuseWhenCleared() {
        let restored = UndoPlan.restoredText(current: "",
                                             before: "было", after: "стало")
        #expect(restored == nil)
    }

    @Test("Мы только удаляли — возвращать некуда, отказ")
    func refuseWhenNothingInserted() {
        // The inserted chunk is gone -> the position is known only from an offset, which is unreliable.
        let restored = UndoPlan.restoredText(current: "хвост дописан",
                                             before: "лишнее хвост", after: "хвост")
        #expect(restored == nil)
    }

    @Test("Отмена идемпотентна по смыслу: повторный поиск уже не находит наш фрагмент")
    func refuseAfterAlreadyUndone() {
        let once = UndoPlan.restoredText(current: "сегодня привет завтра",
                                         before: "сегодня ghbdtn завтра",
                                         after: "сегодня привет завтра")
        #expect(once == "сегодня ghbdtn завтра")
        // A second undo on already reverted text: our fragment is no longer there.
        let twice = UndoPlan.restoredText(current: once!,
                                          before: "сегодня ghbdtn завтра",
                                          after: "сегодня привет завтра")
        #expect(twice == nil)
    }
}
