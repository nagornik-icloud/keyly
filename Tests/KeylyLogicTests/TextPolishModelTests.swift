import Testing
@testable import KeylyLogic

/// Choosing the model for processing a transcript.
///
/// Added because the fix "processing goes to the provider of the selected
/// key" depended on the model decision, and checking it required a paid request,
/// so in practice it was never checked.
struct TextPolishModelTests {

    private let transcription: Set<String> = ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]

    @Test("Чат-модель проходит как есть")
    func chatModelKept() {
        #expect(TextPolishModel.resolve(picked: "gpt-4.1-mini",
                                        transcriptionModelIDs: transcription,
                                        fallback: "gpt-4.1-mini") == "gpt-4.1-mini")
        #expect(TextPolishModel.resolve(picked: "gemini-flash-latest",
                                        transcriptionModelIDs: transcription,
                                        fallback: "gemini-flash-latest") == "gemini-flash-latest")
    }

    /// Negative case: a transcription model takes audio, not a dialogue. Keeping it would
    /// break processing with a "Tidy failed" error instead of paragraphs.
    @Test("Транскрипционная модель заменяется запасной")
    func transcriptionModelReplaced() {
        for model in transcription {
            #expect(TextPolishModel.resolve(picked: model,
                                            transcriptionModelIDs: transcription,
                                            fallback: "gpt-4.1-mini") == "gpt-4.1-mini")
        }
    }

    /// The key point of the fix: the fallback model is taken from the CURRENT provider. Substituting
    /// the OpenAI default for a Gemini key would swap one failure (400) for another (404).
    @Test("Запасная модель — того же провайдера, что и ключ")
    func fallbackFollowsProvider() {
        #expect(TextPolishModel.resolve(picked: "whisper-1",
                                        transcriptionModelIDs: transcription,
                                        fallback: "gemini-flash-latest") == "gemini-flash-latest")
    }

    @Test("Пустой выбор — тоже повод взять запасную")
    func emptySelectionFallsBack() {
        #expect(TextPolishModel.resolve(picked: "",
                                        transcriptionModelIDs: transcription,
                                        fallback: "gpt-4.1-mini") == "gpt-4.1-mini")
        #expect(TextPolishModel.resolve(picked: "   ",
                                        transcriptionModelIDs: transcription,
                                        fallback: "gpt-4.1-mini") == "gpt-4.1-mini")
    }

    @Test("Пробелы вокруг имени не превращают известную модель в неизвестную")
    func trimsWhitespace() {
        #expect(TextPolishModel.resolve(picked: " whisper-1 ",
                                        transcriptionModelIDs: transcription,
                                        fallback: "gpt-4.1-mini") == "gpt-4.1-mini")
    }
}
