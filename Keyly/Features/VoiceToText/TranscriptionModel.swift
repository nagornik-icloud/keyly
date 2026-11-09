import Foundation

struct TranscriptionModel: Hashable {
    let id: String
    let displayName: String
    let description: String
}

enum TranscriptionModelCatalog {
    static let openAI: [TranscriptionModel] = [
        TranscriptionModel(
            id: "gpt-4o-mini-transcribe",
            displayName: "gpt-4o-mini-transcribe",
            description: "voice.model.mini.hint".loc
        ),
        TranscriptionModel(
            id: "gpt-4o-transcribe",
            displayName: "gpt-4o-transcribe",
            description: "voice.model.full.hint".loc
        ),
        TranscriptionModel(
            id: "whisper-1",
            displayName: "whisper-1",
            description: "voice.model.whisper.hint".loc
        )
    ]

    static var openAIIDs: [String] { openAI.map(\.id) }

    /// The RECOGNITION model the product picks by itself.
    ///
    /// There is no point letting the user choose: only one is reasonable here, and a choice of three
    /// caused exactly the bug that made transcript post-processing silently fail — the selected
    /// transcription model ended up in a chat request, which doesn't accept it.
    static let openAIDefaultID = "gpt-4o-mini-transcribe"

    /// The recognition model selected by the user. A value outside the catalog (coming from old
    /// settings where the key was shared with the processing model) is replaced with the default:
    /// a chat model must not be sent for recognition.
    @MainActor
    static var selectedOpenAI: String {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.voiceTranscriptionModel) ?? ""
        return openAIIDs.contains(stored) ? stored : openAIDefault
    }

    /// Models capable of live typing as you speak. `whisper-1` returns only the final
    /// segment, so it is unavailable in streaming mode.
    static var liveCapableOpenAIIDs: [String] {
        openAIIDs.filter { !VoiceRecognitionMode.modelsWithoutLive.contains($0) }
    }

    static var openAIDefault: String { openAI[0].id }

    static func openAIModel(id: String) -> TranscriptionModel? {
        openAI.first { $0.id == id }
    }
}
