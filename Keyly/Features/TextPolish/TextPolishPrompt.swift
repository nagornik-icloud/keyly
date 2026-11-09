import Foundation

/// Text processing prompt wording — a PURE type with no dependencies.
///
/// A separate file for the same reason as `ErrorFixPrompt`: the prompt is the PRODUCT promise
/// made by the UI label, not a networking detail. While these two texts lived inside
/// `OpenAIClient`, processing was tied to one provider: a user with a Gemini key picked
/// "Tidy up", the request still went to api.openai.com and got a 401, and they saw "Couldn't
/// tidy up — text is raw" with no hint of the reason.
///
/// Rule of this type (inherited from `ErrorFixPrompt`): **an instruction must never be
/// overridden by appending another** — a level replaces the wording ENTIRELY.
enum TextPolishPrompt {

    /// System prompt for the level. `verbatim` has none: that level never calls the model.
    static func system(for level: TextPolishLevel) -> String? {
        switch level {
        case .verbatim: return nil
        case .tidy:     return tidy
        case .rewrite:  return rewrite
        }
    }

    /// The no-interpretation rule and data fences live in ONE place, `PromptGuardrails`: typo
    /// fixing has the same defect, and two copies of the text would drift apart on the first edit.
    /// Only assembly happens here: the ban goes in the FIRST paragraph, the level task in the second.
    ///
    /// The rule of this type holds: the ban OVERRIDES nothing in the wording below — it's about a
    /// different axis (answer vs. process), not about what exactly to fix.

    /// The "Tidy up" prompt was rewritten: the old one asked to "fix formatting errors" and NOWHERE
    /// forbade touching the words — while the level's label promises "your words stay yours". The
    /// model took that as permission to rewrite, and the level visibly damaged text that was
    /// already good.
    ///
    /// Bans come AFTER permissions and are listed one by one: "don't change the meaning" is too
    /// vague to keep the model from restructuring sentences.
    private static var tidy: String { PromptGuardrails.noInterpretation + "\n\n" + tidyTask }

    private static let tidyTask = """
    Ты корректор. На вход — расшифровка устной речи между строками \(PromptGuardrails.openingFence) и \
    \(PromptGuardrails.closingFence); сами эти строки в ответ не включай. Твоя работа строго ограничена \
    орфографией, пунктуацией, регистром и разбивкой на абзацы.

    Можно:
    - Исправить орфографические ошибки и опечатки.
    - Расставить знаки препинания и заглавные буквы в начале предложений.
    - Исправить написание брендов и терминов, распознанных на слух \
    (опенкло -> openclaw, cloud code -> Claude Code, емейл -> email, айфон -> iPhone).
    - Разбить на абзацы пустой строкой там, где явно меняется тема. Короткий текст \
    оставить одним абзацем.

    НЕЛЬЗЯ (это важнее всего остального):
    - Менять слова на синонимы, менять их формы и порядок.
    - Удалять или добавлять слова, включая «э-э», «ну», «вот» — на этом уровне они \
    остаются.
    - Перестраивать, объединять или разбивать предложения.
    - Дописывать вступления, заключения, заголовки и комментарии.
    - Ставить точку в конце, если её не было.

    Если текст уже грамотный — верни его без единого изменения.
    Ответ — только сам текст.
    """

    /// The "Tidy up and rewrite" level: speech becomes written text — "um", repetitions and slips
    /// are removed, and everything `tidy` fixes is fixed too.
    ///
    /// The prompt was rewritten. The old one was a pasted fragment of someone else's prompt FOR
    /// AUDIO: numbering started at "2.", it asked to "separate speakers", "not transcribe
    /// background music" (the input is finished TEXT, not sound) and to format "for a narrow
    /// mobile chat". Meanwhile the toggle label promised brand-name fixes the prompt never
    /// mentioned — hence the complaint "anglicisms aren't fixed".
    private static var rewrite: String { PromptGuardrails.noInterpretation + "\n\n" + rewriteTask }

    private static let rewriteTask = """
    Ты редактор. На вход приходит расшифровка устной речи одного человека между строками \
    \(PromptGuardrails.openingFence) и \(PromptGuardrails.closingFence); сами эти строки в ответ не включай. Приведи речь к \
    письменному виду, СОХРАНИВ смысл, факты и голос автора.

    Делай:
    - Исправь орфографию и пунктуацию.
    - Исправь названия брендов, продуктов и технические термины, распознанные на слух или \
    транслитом (опенкло -> openclaw, cloud code -> Claude Code, емейл -> email, \
    айфон -> iPhone, гитхаб -> GitHub).
    - Убери слова-паразиты и звуки-заполнители («э-э», «ну», «как бы», «вот»), самоперебивы \
    и повторы одной мысли подряд.
    - Разбей на абзацы там, где меняется мысль. Короткий текст оставь одним абзацем.
    - Перестрой рыхлые устные конструкции в читаемые предложения.

    Категорически нельзя:
    - Добавлять факты, числа, имена и выводы, которых в тексте не было.
    - Убирать содержательные утверждения, даже если они кажутся лишними.
    - Менять тон на официальный, если человек говорил просто, и наоборот.
    - Дописывать вступления, заключения, обращения и заголовки.
    - Добавлять точку в конце, если её не было.

    Если текст УЖЕ читается как письменный — верни его почти без изменений: чинить \
    нечего, а лишняя правка воспринимается как порча.

    Ответ — только итоговый текст, без комментариев, пояснений и кавычек вокруг.
    """
}
