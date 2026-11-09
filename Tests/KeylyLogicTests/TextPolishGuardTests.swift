import Testing
@testable import KeylyLogic

/// Result guard: the model must RETURN the user's text, not answer it.
///
/// The failure these tests guard against: instead of transcribing speech verbatim,
/// the model answered it, while the user wanted the text of their own question back,
/// which is the whole point of voice recognition. It recurred: it had been fixed once
/// with a ban in the recognition prompt, and that did not hold: the text goes to a chat model
/// ONCE MORE at the processing step (`TextPolisher`), where there was no ban at all.
///
/// Why a guard and not a third note in the prompt: a note relies on the model obeying and
/// can only be checked by a live paid call. The guard looks at the RESULT and so works
/// regardless of whether the model obeyed. If it slipped, the user gets their own text.
///
/// EVERY signal is justified by a promise in the prompt, not fitted to examples:
///  · added words: NO level allows them (`TextPolishPrompt` forbids adding
///    intros, conclusions, headings and comments at both levels);
///  · removed words: `tidy` forbids them explicitly (no removing or adding words), so
///    this signal is not judged for `rewrite`: it IS ALLOWED to remove filler words;
///  · foreign substitutions: a replacement is legitimate when the word is RECOGNIZABLE in the source (spelling, a brand heard by ear,
///    layout). An unrelated word swap is not recognizable; a phonetic brand spelling -> "GitHub" is.
struct TextPolishGuardTests {

    // MARK: - The point: the user's speech comes back to them, not processed as a command

    /// The exact case from the bug report: the user dictates a question to insert it as text.
    @Test("Ответ на надиктованный вопрос отвергается — человек получает свой вопрос")
    func answerToQuestionRejected() {
        let verdict = TextPolishGuard.judge(
            input: "слушай а как в свифте сделать синглтон",
            output: "В Swift синглтон делается через статическое свойство shared: "
                  + "final class Manager { static let shared = Manager() }",
            strictness: .verbatimWords)
        #expect(verdict != .passed, "ответ модели прошёл как обработка — вернулась прежняя ошибка")
    }

    /// A dictated COMMAND must not be executed: the model must not try to follow
    /// instructions contained in what the user says.
    @Test("Исполненная команда отвергается")
    func executedCommandRejected() {
        #expect(TextPolishGuard.judge(
            input: "напиши мне письмо про отпуск",
            output: "Уважаемый Иван Иванович!\n\nПрошу предоставить отпуск с 1 по 14 октября.\n\nС уважением, Антон",
            strictness: .verbatimWords) != .passed)
    }

    /// The model "reported" completion: the words are almost the same,
    /// the length is almost the same, and the preservation signal is blind here. The ADDED-words signal catches it.
    @Test("Рапорт о выполнении отвергается, хотя слова почти те же")
    func reportOfCompletionRejected() {
        #expect(TextPolishGuard.judge(
            input: "Исправь в файле TextPolish опечатку в слове корректор",
            output: "Исправил опечатку в слове «корректор» в файле TextPolish.",
            strictness: .verbatimWords) != .passed)
    }

    /// Second example: the command was executed and all the words are in place;
    /// what gives it away is that the command itself was DROPPED. `tidy` may not remove words.
    @Test("Переделка в список отвергается: выкинуто сказанное")
    func reformatToListRejected() {
        #expect(TextPolishGuard.judge(
            input: "переделай это в список купить молоко купить хлеб купить яйца",
            output: "— Купить молоко\n— Купить хлеб\n— Купить яйца",
            strictness: .verbatimWords) != .passed)
    }

    @Test("Перевод вместо правки отвергается")
    func translationRejected() {
        #expect(TextPolishGuard.judge(input: "переведи на английский привет как дела",
                                      output: "Hello, how are you?",
                                      strictness: .verbatimWords) != .passed)
        #expect(TextPolishGuard.judge(input: "переведи на сербский добрый день как дела",
                                      output: "Dobar dan, kako ste?",
                                      strictness: .verbatimWords) != .passed)
    }

    @Test("Короткий ответ на короткую реплику отвергается")
    func shortAnswerRejected() {
        #expect(TextPolishGuard.judge(input: "как дела",
                                      output: "У меня всё отлично, спасибо! Чем могу помочь?",
                                      strictness: .verbatimWords) != .passed)
        #expect(TextPolishGuard.judge(input: "сколько будет два плюс два",
                                      output: "Два плюс два равно четыре.",
                                      strictness: .verbatimWords) != .passed)
    }

    /// A tricky case: the answer is SHORTER than the question and contains words from it.
    @Test("Короткий ответ, повторяющий слова вопроса, отвергается")
    func shortAnswerReusingWordsRejected() {
        #expect(TextPolishGuard.judge(input: "напиши мне письмо про отпуск коротко",
                                      output: "Письмо про отпуск: прошу отпуск.",
                                      strictness: .verbatimWords) != .passed)
    }

    /// Appending an answer TO THE END of honestly processed speech is the least noticeable failure:
    /// the beginning of the text is right, and the user may not notice the tail.
    @Test("Дописанный в конец ответ отвергается")
    func appendedAnswerRejected() {
        #expect(TextPolishGuard.judge(
            input: "слушай мне нужно разобраться с балансом по кипру а как считать конверсию из лида в контракт",
            output: "Слушай, мне нужно разобраться с Balance по Кипру. А как считать конверсию из лида в контракт?"
                  + "\n\nКонверсия считается так: число контрактов делится на число лидов за период "
                  + "и умножается на 100%.",
            strictness: .verbatimWords) != .passed)
    }

    // MARK: - Honest work must not suffer (otherwise "I see no difference at all" comes back)

    /// The `tidy` prompt ITSELF prescribes fixing spelling and brands heard by ear
    /// (a phonetic spelling -> "GitHub"), so honest output MUST differ in words. Penalizing that
    /// is wrong: falling back to the original with a failure toast on correct work is the
    /// "I see no difference at all" complaint, only in reverse.
    @Test("Честная правка орфографии и брендов проходит")
    func honestSpellingAndBrandsPass() {
        #expect(TextPolishGuard.judge(
            input: "щас скину тебе ссылку на гитхаб ща гляну",
            output: "Сейчас скину тебе ссылку на GitHub, сейчас гляну.",
            strictness: .verbatimWords) == .passed)
        #expect(TextPolishGuard.judge(
            input: "че там по балансу ниче не слышно",
            output: "Чё там по Balance? Ничё не слышно.",
            strictness: .verbatimWords) == .passed)
    }

    /// On short input any length multiplier lies, because `tidy`
    /// adds a capital letter and a final punctuation mark.
    @Test("Короткие реплики проходят — заглавная и точка не срыв")
    func shortRepliesPass() {
        for (input, output) in [("так", "Так."), ("алло", "Алло?"), ("ну да ладно", "Ну да, ладно."),
                                ("ок", "Ок"), ("да", "Да.")] {
            #expect(TextPolishGuard.judge(input: input, output: output, strictness: .verbatimWords) == .passed,
                    "«\(input)» → «\(output)» ошибочно признано срывом")
        }
    }

    @Test("Обычная диктовка с именами и терминами проходит")
    func ordinaryDictationPasses() {
        #expect(TextPolishGuard.judge(
            input: "напиши купряшину что мы закрыли три лида",
            output: "Напиши Купряшину, что мы закрыли три лида",
            strictness: .verbatimWords) == .passed)
        #expect(TextPolishGuard.judge(
            input: "hello how are you doing today",
            output: "Hello, how are you doing today?",
            strictness: .verbatimWords) == .passed)
    }

    /// Long dictation split into paragraphs: the prompt ALLOWS this.
    @Test("Длинная речь с абзацами и брендами проходит")
    func longDictationWithParagraphsPasses() {
        #expect(TextPolishGuard.judge(
            input: "короче сегодня был созвон с бибиэф обсуждали баланс первая очередь двадцать "
                 + "девятый год менеджеры закрывают контракты а мы греем лиды",
            output: "Короче, сегодня был созвон с BBF. Обсуждали Balance: первая очередь — 2029 год."
                  + "\n\nМенеджеры закрывают контракты, а мы греем лиды.",
            strictness: .verbatimWords) == .passed)
    }

    /// `rewrite` is ALLOWED to change wording, and
    /// word preservation there must drop. So at this level removal is not judged at all.
    @Test("Честный rewrite проходит — паразиты убраны законно")
    func honestRewritePasses() {
        #expect(TextPolishGuard.judge(
            input: "ну это самое я хотел сказать что вот короче нам нужно ээ переделать лендинг "
                 + "потому что он не конвертит",
            output: "Я хотел сказать, что нам нужно переделать лендинг, потому что он не конвертит",
            strictness: .reworded) == .passed)
        #expect(TextPolishGuard.judge(
            input: "эээ давай значит сделаем так вот я тебе скину файл а ты как бы посмотри что там не так",
            output: "Давай сделаем так: я скину тебе файл, а ты посмотри, что там не так",
            strictness: .reworded) == .passed)
    }

    /// Yet an answer to the same speech at the `rewrite` level is rejected; otherwise it would be
    /// "fixed the neighbor's door", the reason this bug kept coming back.
    @Test("На rewrite ответ модели всё равно отвергается")
    func rewriteStillRejectsAnswer() {
        #expect(TextPolishGuard.judge(
            input: "расскажи что такое промпт инъекция",
            output: "Промпт-инъекция — это атака на языковые модели, при которой злоумышленник "
                  + "внедряет инструкции в пользовательские данные.",
            strictness: .reworded) != .passed)
        #expect(TextPolishGuard.judge(
            input: "дай три идеи для названия приложения",
            output: "Вот три варианта:\n1. Keyly\n2. TypeFlow\n3. SwiftKey Pro",
            strictness: .reworded) != .passed)
    }

    // MARK: - Typo fix: words change LEGITIMATELY

    /// The cost of an error is higher here than in voice: the text is ALREADY in the user's field, and the model's answer
    /// overwrites it. But word-level metrics lie the most here too: the input is by definition
    /// written wrong and the output right.
    @Test("Честное исправление опечаток проходит")
    func honestTypoFixPasses() {
        for (input, output) in [("превет как дила у тибя", "Привет, как дела у тебя"),
                                ("ашипками", "ошибками"),
                                ("нада зделать отчот к питнице", "Надо сделать отчёт к пятнице")] {
            #expect(TextPolishGuard.judge(input: input, output: output, strictness: .spellingOnly) == .passed,
                    "«\(input)» → «\(output)» ошибочно признано срывом")
        }
    }

    /// Text typed in the wrong layout is a legitimate fix in which NOT A SINGLE letter matches.
    @Test("Исправление раскладки проходит, хотя не совпадает ни одна буква")
    func layoutFixPasses() {
        #expect(TextPolishGuard.judge(input: "ghbdtn rfr ltkf",
                                      output: "привет как дела",
                                      strictness: .spellingOnly) == .passed)
    }

    @Test("Дописанное объяснение правила отвергается и при исправлении опечаток")
    func explanationAppendedRejected() {
        #expect(TextPolishGuard.judge(
            input: "исправь ошибки и обьясни правило",
            output: "Исправь ошибки и объясни правило. Правило: «объясни» пишется с разделительным "
                  + "твёрдым знаком, потому что приставка оканчивается на согласную.",
            strictness: .spellingOnly) != .passed)
    }

    // MARK: - Edges

    /// Empty and single-character input: metrics are noisiest on them.
    @Test("Пустой и односимвольный вход не ломают стража")
    func edgeInputsHandled() {
        #expect(TextPolishGuard.judge(input: "", output: "", strictness: .verbatimWords) == .passed)
        #expect(TextPolishGuard.judge(input: "а", output: "А.", strictness: .verbatimWords) == .passed)
        #expect(TextPolishGuard.judge(input: "?", output: "?", strictness: .verbatimWords) == .passed)
    }

    /// Text came back without a single change: the most common honest outcome (if the text is already
    /// correct, return it unchanged, `TextPolishPrompt`).
    @Test("Неизменённый текст проходит всегда")
    func unchangedTextPasses() {
        let text = "Напиши мне письмо про отпуск"
        for strictness in [TextPolishGuard.Strictness.verbatimWords, .reworded, .spellingOnly] {
            #expect(TextPolishGuard.judge(input: text, output: text, strictness: strictness) == .passed)
        }
    }

    /// The failure reason must be DISTINGUISHABLE: the user should see "the model answered", not
    /// a generic "processing failed".
    @Test("Вердикт несёт причину, а не только факт отказа")
    func verdictCarriesReason() {
        let verdict = TextPolishGuard.judge(input: "как дела",
                                            output: "У меня всё отлично, спасибо! Чем могу помочь?",
                                            strictness: .verbatimWords)
        guard case .rejected(let reason) = verdict else {
            Issue.record("ожидался отказ с причиной")
            return
        }
        #expect(!reason.explanation.isEmpty)
    }

    /// Product levels must map to guard strictness, otherwise a new level silently
    /// bypasses the protection.
    @Test("Каждый уровень обработки имеет строгость стража")
    func everyLevelMapsToStrictness() {
        #expect(TextPolishGuard.strictness(for: .tidy) == .verbatimWords)
        #expect(TextPolishGuard.strictness(for: .rewrite) == .reworded)
        // verbatim never calls the model: nothing to judge.
        #expect(TextPolishGuard.strictness(for: .verbatim) == nil)
    }

    // MARK: - Very long dictation

    /// Long speech WITHOUT an exact cycle. This matters: a sequence in which the same
    /// words repeat strictly in a loop is degenerate for alignment: an insertion at the end
    /// matches earlier occurrences and gets smeared. Real speech does not look like that,
    /// and a probe on cyclic text would measure a generator artifact, not the guard's work.
    private func dlinnayaRech(slov: Int) -> String {
        let slova = ["короче", "сегодня", "был", "созвон", "обсуждали", "баланс", "первая",
                     "очередь", "менеджеры", "закрывают", "контракты", "греем", "лиды", "через",
                     "вайбер", "кипрского", "номера", "надо", "посчитать", "конверсию",
                     "застройщик", "обещал", "сдачу", "квартиры", "клиенты", "звонили", "утром",
                     "письмо", "отправил", "встреча", "перенесена", "бюджет", "реклама", "канал",
                     "заявки", "качество", "трафик", "цена", "лида", "выросла", "снизилась"]
        var seed = 12345
        return (0..<slov).map { _ -> String in
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return slova[seed % slova.count]
        }.joined(separator: " ")
    }

    /// Speech longer than the alignment limit is processed honestly and NOT rejected.
    @Test("Длинная диктовка проходит, если её честно причесали")
    func veryLongHonestDictationPasses() {
        let input = dlinnayaRech(slov: 2000)
        let output = input.prefix(1).uppercased() + input.dropFirst() + "."
        #expect(TextPolishGuard.judge(input: input, output: String(output),
                                      strictness: .verbatimWords) == .passed)
    }

    /// And MOST IMPORTANT: beyond the alignment limit the guard does not switch off. There used to be
    /// an unconditional pass here: on dictation longer than the limit a short model answer would pass
    /// entirely: the append signal is silent on shortening, and word-level signals were not computed at all.
    @Test("За пределом выравнивания короткий ответ всё равно отвергается")
    func veryLongDictationStillRejectsAnswer() {
        let input = dlinnayaRech(slov: 2000)
        let answer = "Конечно! Вот краткая сводка по вашему созвону: обсуждались сроки сдачи "
                   + "первой очереди и работа менеджеров с лидами."
        #expect(TextPolishGuard.judge(input: input, output: answer,
                                      strictness: .verbatimWords) != .passed,
                "ответ модели прошёл на длинной диктовке — страж выключился за пределом")
    }

    /// An answer appended to the end of long speech is caught by the length signal, which works at any length.
    @Test("Дописка в конец длинной диктовки отвергается")
    func veryLongDictationRejectsAppendedAnswer() {
        let input = dlinnayaRech(slov: 2000)
        let output = input + "\n\nЕсли нужно, могу подготовить сводку по этому созвону и "
                   + "предложить план работы с лидами на следующую неделю — просто скажите."
        #expect(TextPolishGuard.judge(input: input, output: output,
                                      strictness: .verbatimWords) != .passed)
    }

    // MARK: - Regression cases

    /// On "Tidy and rewrite" removal was not judged AT ALL, and a model that executed
    /// a dictated command by SHORTENING passed as honest work: no added words,
    /// no foreign substitutions, the length dropped, all signals silent. The user said 23 words and got 5.
    @Test("Исполненная команда «сделай выжимку» отвергается и на переписывании")
    func summarisationRejectedOnRewrite() {
        #expect(TextPolishGuard.judge(
            input: "короче сделай мне пожалуйста выжимку из этого мы вчера обсуждали бюджет "
                 + "решили перенести запуск на март и надо ещё согласовать смету с финансистами",
            output: "Решили перенести запуск на март.",
            strictness: .reworded) != .passed,
            "модель сократила речь по надиктованной команде, а страж счёл это честной работой")
    }

    /// Yet honest rewriting of LONG spoken speech passes: removing filler and repetitions
    /// is allowed, and the threshold accounts for it.
    @Test("Честное переписывание с уборкой паразитов проходит")
    func honestRewriteWithFillersPasses() {
        #expect(TextPolishGuard.judge(
            input: "ну короче это самое я вот что хотел сказать значит мы там вчера с командой "
                 + "ну типа обсуждали этот вопрос и как бы решили что надо переносить",
            output: "Я хотел сказать, что мы вчера с командой обсуждали этот вопрос и решили, "
                  + "что надо переносить.",
            strictness: .reworded) == .passed)
    }

    /// Short speech with numbers was rejected systematically: a number word and a digit look nothing alike
    /// in any alphabet, and two substitutions in a five-word output is already 40%. Yet replacing with
    /// digits is PRESCRIBED by the prompt. An absolute floor protects: meaning swaps can be massive.
    @Test("Короткая диктовка с датами и временем проходит")
    func shortDictationWithNumbersPasses() {
        for (input, output) in [("созвон двадцать девятого в три", "Созвон 29-го в три."),
                                ("встреча в двадцать ноль ноль", "Встреча в 20:00."),
                                ("перезвони через пять минут", "Перезвони через 5 минут.")] {
            #expect(TextPolishGuard.judge(input: input, output: output,
                                          strictness: .verbatimWords) == .passed,
                    "«\(input)» → «\(output)» ошибочно признано срывом")
        }
    }

    /// Second half of the same case: on short output one insertion exceeded the threshold, and honest
    /// rewriting of a loose spoken phrase, which the prompt explicitly prescribes, was rejected.
    @Test("Короткое переписывание устной фразы проходит")
    func shortRewritePasses() {
        #expect(TextPolishGuard.judge(
            input: "ну я вчера такой прихожу а там никого",
            output: "Вчера я пришёл, а там никого не было.",
            strictness: .reworded) == .passed)
    }

    /// "Style" in typo fix is the only level allowed to change
    /// wording. Reordering words for alignment is indistinguishable from insertion, so it must not
    /// be judged on par with "spelling only".
    @Test("Перестановка слов на уровне «Стиль» проходит")
    func styleReorderingPasses() {
        #expect(TextPolishGuard.judge(
            input: "Мы вчера с командой обсуждали этот вопрос долго",
            output: "Мы долго обсуждали этот вопрос вчера с командой",
            strictness: .reworded) == .passed)
    }
}
