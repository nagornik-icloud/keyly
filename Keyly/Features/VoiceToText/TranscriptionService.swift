import Foundation

/// Transcribes an audio file, automatically cycling through keys and providers.
@MainActor
final class TranscriptionService {
    weak var errorToastPresenter: VoiceErrorToastPresenting?

    func transcribe(url: URL) async throws -> String {
        let store = APIKeyStore.shared
        let primarySelection = store.currentSelection(for: .voiceToText)
        let primaryProvider = primarySelection.provider
        let secondaryProvider: APIProvider = primaryProvider == .openai ? .gemini : .openai

        let allPrimaryKeys = store.availableKeys(for: primaryProvider)
        var orderedPrimaryKeys: [APIKeyEntry] = []
        if let selected = store.entry(for: primarySelection) {
            orderedPrimaryKeys.append(selected)
            orderedPrimaryKeys += allPrimaryKeys.filter { $0.id != selected.id }
        } else {
            orderedPrimaryKeys = allPrimaryKeys
        }
        let secondaryKeys = store.availableKeys(for: secondaryProvider)

        var lastError: Error? = nil

        // Selected key up to 2 attempts, the others once. What failed decides what's next:
        // a bad request stops (every key would fail the same way, no point sending the
        // audio around), a refused key moves on, network/server trouble repeats.
        keys: for (keyIndex, entry) in orderedPrimaryKeys.enumerated() {
            let maxAttempts = keyIndex == 0 ? 2 : 1
            for attempt in 1...maxAttempts {
                if lastError != nil {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    let message = attempt == 2 ? "voice.retry.sameKey" : "voice.retry.otherKey"
                    errorToastPresenter?.showVoiceInfoToast(message: message.loc(primaryProvider.title))
                }
                do {
                    return try await callTranscription(entry: entry, provider: primaryProvider,
                                                       model: primarySelection.model, url: url)
                } catch {
                    // A cancelled transcription must not go on to try other keys.
                    if Task.isCancelled || error is CancellationError { throw error }
                    lastError = error
                    errorToastPresenter?.showVoiceErrorToast(message: humanReadableError(error))
                    switch TranscriptionFailure.classify(error) {
                    case .badRequest: break keys
                    case .keySpecific: continue keys
                    case .transient: continue
                    }
                }
            }
        }

        // There is no switching to ANOTHER provider here anymore.
        //
        // The keys screen promises the user literally: "The key is stored on this computer and
        // goes only to the SELECTED provider". The code broke that promise: when all OpenAI keys
        // failed, the recording silently went to Gemini (and vice versa) — the user's audio went to
        // someone they didn't choose, and they learned about it from a toast after it was sent.
        // Same class as never silently replacing the selected mode with another one — only the
        // stakes are higher here, because the DATA route changes.
        //
        // Cycling through keys WITHIN the selected provider stays: the route doesn't change there.
        if !secondaryKeys.isEmpty {
            Log.info(.voice, "TranscriptionService: ключи \(primaryProvider.title) исчерпаны; ключи \(secondaryProvider.title) есть, но автоматически на них не переходим — провайдера выбирает человек")
        }

        throw lastError ?? NSError(domain: "VoiceToText", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "voice.err.allKeysFailed".loc])
    }

    // MARK: - API dispatch

    private func callTranscription(entry: APIKeyEntry, provider: APIProvider,
                                   model: String?, url: URL) async throws -> String {
        let audioData = try Data(contentsOf: url)
        switch provider {
        case .openai:
            // The model comes from the Voice screen picker; the key's model is for text processing.
            let t = await MainActor.run { TranscriptionModelCatalog.selectedOpenAI }
            // Text post-processing is NOT done here: it is shared by all recognition paths and
            // lives in `TextPolisher`. Formatting used to exist only in this branch — both Gemini
            // and the local model returned raw text, and the setting looked broken.
            return try await OpenAIClient.transcribe(audioData: audioData, model: t,
                                                     prompt: TranscriptionPrompt.text(forModel: t),
                                                     apiKey: entry.value,
                                                     filename: url.lastPathComponent)
        case .gemini:
            let m = model ?? entry.model ?? provider.defaultModel
            return try await GeminiClient.transcribe(audioData: audioData, model: m,
                                                     prompt: TranscriptionPrompt.text(forModel: m),
                                                     apiKey: entry.value)
        }
    }

    // MARK: - Human-readable errors

    private func humanReadableError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return "voice.err.offline".loc
            case .timedOut: return "voice.err.timeout".loc
            default: return "voice.err.network".loc
            }
        }
        switch (error as NSError).code {
        case 400: return "voice.err.badRequest".loc
        case 401, 403: return "voice.err.key".loc
        case 404: return "voice.err.model".loc
        case 413: return "voice.err.tooLarge".loc
        case 429: return "voice.err.rateLimit".loc
        case 500...599: return "voice.err.server".loc
        case -1: return "voice.err.badResponse".loc
        case -2, 2: return "voice.err.noText".loc
        default: return "voice.err.generic".loc
        }
    }
}
