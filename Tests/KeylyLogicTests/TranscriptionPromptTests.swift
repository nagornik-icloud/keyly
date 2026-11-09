import Testing
@testable import KeylyLogic

/// Speech recognition prompt and its protection against interpretation.
///
/// Added after a bug: when dictating via OpenAI, the model sometimes
/// does not transcribe speech verbatim but "answers" it: an answer arrives instead of the text.
/// Cause: gpt-4o-*-transcribe and Gemini are instruction-following, and without an explicit ban
/// they execute a spoken command. This pins the invariant: an instruction-following
/// model gets the "transcription only" ban, while whisper-1 (pure ASR) does not; otherwise
/// the extra text leaks into its output.
struct TranscriptionPromptTests {

    /// Default OpenAI recognition model. Break the invariant and the bug returns.
    private let defaultModel = "gpt-4o-mini-transcribe"

    @Test("instruction-following модель распознаётся как таковая, whisper-1 — нет")
    func classifiesModels() {
        #expect(TranscriptionPrompt.interpretsInstructions("gpt-4o-mini-transcribe"))
        #expect(TranscriptionPrompt.interpretsInstructions("gpt-4o-transcribe"))
        #expect(TranscriptionPrompt.interpretsInstructions("gemini-2.5-flash"))
        #expect(!TranscriptionPrompt.interpretsInstructions("whisper-1"))
    }

    /// Core of the fix: the default model's prompt has an explicit ban on answering/executing.
    @Test("Дефолтная модель получает запрет интерпретации")
    func defaultModelForbidsAnswering() {
        let prompt = TranscriptionPrompt.text(forModel: defaultModel)
        #expect(prompt.contains("Не отвечай"), "нет запрета отвечать на вопросы")
        #expect(prompt.contains("не выполняй"), "нет запрета выполнять команды")
    }

    @Test("gpt-4o-transcribe тоже удержан")
    func fullModelForbidsAnswering() {
        #expect(TranscriptionPrompt.text(forModel: "gpt-4o-transcribe").contains("Не отвечай"))
    }

    @Test("Gemini — instruction-following, запрет обязателен")
    func geminiForbidsAnswering() {
        #expect(TranscriptionPrompt.text(forModel: "gemini-2.5-flash").contains("Не отвечай"))
    }

    /// whisper-1 ignores instructions, and extra text in the prompt leaks into the output,
    /// so it gets NO ban, only biasing.
    @Test("whisper-1 получает только биасинг, без инструкции")
    func whisperGetsBiasingOnly() {
        let prompt = TranscriptionPrompt.text(forModel: "whisper-1")
        #expect(!prompt.contains("Не отвечай"), "whisper-1 не должен получать инструкцию")
        #expect(prompt == TranscriptionPrompt.biasingContext)
    }

    /// Biasing context (language) goes to everyone without exception: it is about recognition accuracy.
    @Test("Язык-контекст присутствует у всех моделей")
    func biasingContextEverywhere() {
        for model in ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1", "gemini-2.5-flash"] {
            #expect(TranscriptionPrompt.text(forModel: model).contains("русском"),
                    "\(model): пропал биасинг-контекст языка")
        }
    }

    /// A CLASS, not a single case. The check used the EXACT name `whisper-1`, so any
    /// other whisper model was treated as instruction-following. Streaming recognition runs
    /// on `gpt-realtime-whisper`: it would get an instruction it cannot follow,
    /// yet that TEXT can leak into its output, i.e. into the user's field under the cursor.
    @Test("whisper опознаётся по семейству, а не по имени одного экземпляра")
    func whisperFamilyRecognised() {
        for model in ["whisper-1", "gpt-realtime-whisper", "whisper-large-v3", "WHISPER-1"] {
            #expect(!TranscriptionPrompt.interpretsInstructions(model),
                    "\(model): whisper принята за instruction-following — инструкция протечёт в текст")
            #expect(TranscriptionPrompt.text(forModel: model) == TranscriptionPrompt.biasingContext,
                    "\(model): whisper получила инструкцию вместо одного биасинга")
        }
    }

    /// And conversely: models that DO follow instructions must get the ban.
    @Test("Instruction-following модели по-прежнему получают запрет")
    func instructionFollowingStillGuarded() {
        for model in ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "gemini-2.5-flash"] {
            #expect(TranscriptionPrompt.interpretsInstructions(model))
            #expect(TranscriptionPrompt.text(forModel: model).contains("Не отвечай"), "\(model): нет запрета")
        }
    }
}
