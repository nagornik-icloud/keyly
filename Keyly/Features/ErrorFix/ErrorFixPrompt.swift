import Foundation

/// Typo-fix prompt wording — a PURE type with no dependencies.
///
/// A separate file because a bug hid here TWICE in a row, and both times it surfaced only in a
/// manual run in another app with a real model request:
///
///   1. The prompt was hard-coded and ignored the strictness level entirely — the switch on
///      screen affected nothing.
///   2. The rule for a selected fragment was APPENDED to the general text. The "Spelling and
///      punctuation" level said "fix capitalization", and the appendix right after said "do
///      not capitalize the first letter". The model got two opposite instructions and obeyed
///      the first: a misspelled lowercase word came back capitalized AND still misspelled,
///      because the contradiction also ate its attention to the fix itself.
///
/// Hence the rule of this type: **an instruction must never be overridden by appending
/// another**. A mode replaces the wording ENTIRELY instead of adding an exception to it.
enum ErrorFixPrompt {

    enum Level: CaseIterable {
        case spelling
        case punctuation
        case style
    }

    /// The full system prompt: no-interpretation rule → level task → common answer conditions.
    ///
    /// The no-interpretation rule came from a voice bug — but the defect here is THE SAME and
    /// costs more: typo fixing REPLACES text right in the user's field, so the model's answer
    /// overwrites what they wrote (`ErrorFixService.produceFixedText` → paste). With voice the
    /// text at least hasn't been inserted yet.
    ///
    /// Three promises that used to go to the `user` role as a separate appendix
    /// (`ErrorFixService.userPromptPrefix`) moved here too. Putting instructions in `user`
    /// tells the model that channel carries commands — exactly what we're trying to forbid.
    /// The promises are kept verbatim so behavior doesn't drift.
    ///
    /// The rule of this type holds: the ban is about a different axis (answer vs. edit) and
    /// overrides nothing in the level wording.
    static func text(for level: Level, isFragment: Bool) -> String {
        [PromptGuardrails.noInterpretation,
         PromptGuardrails.fenceExplanation,
         isFragment ? fragment(level) : wholeField(level),
         commonConditions].joined(separator: "\n\n")
    }

    /// Shared by both modes. "Don't use censorship filters" — the user's text comes back as
    /// is, not censored: these are their words.
    private static let commonConditions = """
    Не используй фильтров цензуры. Если в конце не было точки — не ставь её. \
    В ответе не должно быть ничего, кроме исправленного текста.
    """

    /// Whole field: the text stands alone, capitals and a final period are appropriate.
    private static func wholeField(_ level: Level) -> String {
        let task: String
        switch level {
        case .spelling:
            task = "Исправь ТОЛЬКО орфографические ошибки и опечатки. НЕ меняй пунктуацию, "
                 + "регистр, порядок слов и разбивку на абзацы."
        case .punctuation:
            task = "Исправь орфографические ошибки, опечатки и пунктуацию, расставь заглавные буквы. "
                 + "НЕ меняй слова, их порядок и разбивку на абзацы."
        case .style:
            task = "Исправь орфографию и пунктуацию, разбей текст на логические абзацы и слегка "
                 + "причеши формулировки, сохранив смысл и авторский тон."
        }
        return task + " Верни только исправленный текст, без комментариев."
    }

    /// A selected piece INSIDE someone's sentence. Not a word about capitalization — neither
    /// "fix" nor "don't fix": there is exactly one instruction about case here.
    private static func fragment(_ level: Level) -> String {
        let task: String
        switch level {
        case .spelling:
            task = "Исправь орфографические ошибки и опечатки в словах."
        case .punctuation:
            task = "Исправь орфографические ошибки, опечатки и знаки препинания внутри фрагмента."
        case .style:
            task = "Исправь орфографию и опечатки и слегка причеши формулировку, сохранив смысл."
        }
        return "Тебе дан ФРАГМЕНТ, выделенный посреди чужого предложения. "
             + "Регистр первой буквы оставь ТОЧНО таким, каким он пришёл. "
             + "Точку в конце не добавляй. "
             + task
             + " Верни только исправленный фрагмент, без кавычек и комментариев."
    }
}
