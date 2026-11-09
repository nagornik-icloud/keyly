import Foundation

/// Where and with what to process text: provider, key and model as ONE value.
///
/// As three separate parameters they drifted out of sync: `TextPolisher` got the key and the
/// model but never the provider — and silently assumed it was always OpenAI. A user with a
/// Gemini key paid for that with processing failures and no explainable reason. Bundled
/// together, the three fields are read from the store in one go and can't diverge.
struct TextPolishTarget {
    let provider: APIProvider
    let apiKey: String
    let model: String

    /// No key — nothing to process with.
    var isUsable: Bool { !apiKey.isEmpty }
}

/// The single point where a model processes text.
///
/// This used to be spread across three places with different trigger conditions:
/// `TranscriptionService` formatted only on the OpenAI branch, `VoiceToTextManager` kept its own
/// copy for the fallback path (and in one scenario both ran back to back — a double paid
/// request), and the local model and Gemini went through neither. Hence "text isn't split into
/// paragraphs" and "anglicisms aren't fixed": the setting was on, but the code path ignored it.
@MainActor
enum TextPolisher {

    static var level: TextPolishLevel {
        TextPolishLevel(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.textPolishLevel) ?? "")
            ?? .default
    }

    /// Processes the text. On ANY error returns the original: losing the processing is better than
    /// losing the result — it represents seconds of the user's speech and money paid for
    /// transcription.
    ///
    /// No key (local model without a key) → processing is impossible, return as is.
    /// This must not be silent, so it's logged: from outside it looks like "the setting doesn't work".
    /// `level` defaults to `nil` — read from settings. The parameter default can't be computed from
    /// `TextPolisher.level`: default values are evaluated outside actor isolation, while the
    /// setting lives on the main actor.
    static func apply(_ text: String, level explicitLevel: TextPolishLevel? = nil,
                      target: TextPolishTarget) async -> String {
        let level = explicitLevel ?? Self.level
        guard let system = TextPolishPrompt.system(for: level) else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard target.isUsable else {
            Log.warn(.voice, "TextPolisher: уровень «\(level.rawValue)» требует ключа, его нет — текст без обработки")
            await announce(BadgeText.polishNeedsKey)
            return text
        }
        do {
            // The provider DECIDES the route. Previously both level branches hit OpenAI no matter
            // whose key was selected — so a Gemini key was sent to api.openai.com and got a 401.
            // The user's text goes WRAPPED: the `user` role in chat/completions is both a command
            // channel and a data channel, so the boundary must be marked explicitly
            // (`PromptGuardrails`).
            let payload = PromptGuardrails.fenced(text)
            let result: String
            switch target.provider {
            case .openai:
                result = try await OpenAIClient.complete(systemPrompt: system, userText: payload,
                                                         model: target.model, apiKey: target.apiKey,
                                                         temperature: 0)
            case .gemini:
                // This Gemini client has no separate system role — concatenate the same way
                // `ErrorFixService` and `CustomModuleService` do. That makes the wrapper all the
                // more important: here it's the ONLY boundary between instruction and user text.
                result = try await GeminiClient.complete(prompt: system + "\n" + payload,
                                                         model: target.model, apiKey: target.apiKey)
            }
            // Strip the fences BEFORE judging: the model repeats them even though the prompt says
            // not to (seen in practice), and the guard would count them as added words.
            let clean = PromptGuardrails.unfenced(result)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty model answer is a failure, not "the text turned out empty": return the original.
            guard !clean.isEmpty else { return text }

            // THE MODEL MAY HAVE ANSWERED INSTEAD OF EDITING (a recurring real-world problem).
            // The ban in the prompt relies on the model's obedience and can only be verified with
            // a real call; here we look at the RESULT and so catch a failure regardless. If it
            // failed, the user gets THEIR OWN text back — dictating a question must return the
            // question, not an answer to it.
            if let strictness = TextPolishGuard.strictness(for: level),
               case .rejected(let reason) = TextPolishGuard.judge(input: text, output: clean,
                                                                  strictness: strictness) {
                Log.warn(.voice, "TextPolisher: модель \(reason.explanation) вместо обработки — "
                               + "отдаём текст человека без изменений (уровень «\(level.rawValue)»)")
                await announce(BadgeText.polishAnswered)
                return text
            }
            return clean
        } catch {
            Log.warn(.voice, "TextPolisher: обработка через \(target.provider.title) не удалась (\(LogSanitizer.sanitize(error.localizedDescription))) — текст без обработки")
            await announce(BadgeText.polishFailed)
            return text
        }
    }

    /// Who shows the badge. Set by the same layer as for the other services.
    @MainActor static weak var badgePresenter: BadgePresenting?
    /// Who shows the toast. A processing failure goes to a TOAST: the text is in place, raw, and
    /// the message must not sit as a badge over the line — that reads as failure of the whole
    /// dictation, even though the dictated text was inserted.
    @MainActor static weak var errorToastPresenter: VoiceErrorToastPresenting?

    /// A processing failure WITHOUT a message silently loses the setting: the user picked
    /// "Tidy up", got raw text and concluded the switch does nothing. That's exactly what
    /// happened in practice (offline + "Tidy up"): "saw no difference at all".
    ///
    /// The ORIGINAL text is returned — losing the dictation because polishing failed would be
    /// worse than silence. The badge only explains why it's raw.
    private static func announce(_ badge: @autoclosure @escaping () -> String) async {
        await MainActor.run {
            // A toast if there's someone to show it: it has room for the reason and sits under the
            // menu bar icon, not over the text. The badge is the fallback.
            if let toast = errorToastPresenter {
                toast.showVoiceErrorToast(message: badge())
            } else {
                badgePresenter?.showBadge(badge(), kind: .warning)
            }
        }
    }
}
