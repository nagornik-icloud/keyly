import Combine
import Foundation

/// Dictation try-out on the settings screen.
///
/// Three modules out of four had a try-out, voice didn't, although it has the most failure points:
/// microphone permission, selected device, downloaded model, key. The only way to check that it all
/// fits together was to switch to another window and press the hotkey blindly — so setup ended with
/// nothing, and the first failure looked like "the product doesn't work".
///
/// The try-out shows RECOGNITION AS IS: text post-processing ("Polish") is not applied. That way it
/// answers exactly its own question — "does the Mac hear me and recognize the words" — and doesn't
/// spend money on every click. The caption under the button says so.
@MainActor
final class VoicePreview: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case done(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Its own recorder and ITS OWN file: the try-out must not be mixed with real dictation — that one
    /// has the badge, timer, insertion into another app's field and undo. A shared recording path would
    /// mean the try-out's `deleteFile()` erases what the user has already dictated.
    private let recorder = VoiceRecorder(fileName: "keyly-preview-recording.m4a")
    private let cloud = TranscriptionService()

    /// Lock of the current operation. The try-out is a microphone operation just like dictation and
    /// must go through the SHARED mechanism: a private "is the manager busy" check covered only one
    /// side (the try-out saw dictation, dictation didn't see the try-out).
    private var operationToken: OperationGate.Token?

    var isRecording: Bool { state == .recording }

    /// Start or stop with a single button, like the voice hotkey itself.
    func toggle() {
        switch state {
        case .recording: Task { await stopAndRecognise() }
        default:         start()
        }
    }

    private func start() {
        // The lock is shared with dictation, layout switching and typo fixing: two operations on one
        // microphone and one clipboard aren't "slower", they corrupt each other's result.
        // `begin` shows the refusal badge itself, but the settings screen also needs a line —
        // the user is looking at the button, not at the menu bar.
        guard let token = OperationGate.begin(.voice) else {
            state = .failed("module.tryOut.voice.busy".loc)
            return
        }
        operationToken = token
        // Esc aborts the try-out like any other operation.
        token.onCancel = { [weak self] in
            guard let self, self.state == .recording else { return }
            self.recorder.stop()
            self.recorder.deleteFile()
            self.state = .idle
            self.releaseToken()
            Log.info(.voice, "Проба голоса: отменена по Esc")
        }
        do {
            try recorder.start()
            state = .recording
            Log.info(.voice, "Проба голоса: запись начата")
        } catch let failure as VoiceRecorder.StartFailure {
            state = .failed(reason(for: failure))
            releaseToken()
            Log.warn(.voice, "Проба голоса: запись не началась (\(failure))")
        } catch {
            state = .failed("module.tryOut.failed".loc)
            releaseToken()
            Log.warn(.voice, "Проба голоса: запись не началась (\(LogSanitizer.sanitize(error.localizedDescription)))")
        }
    }

    private func releaseToken() {
        operationToken?.release()
        operationToken = nil
    }

    private func stopAndRecognise() async {
        recorder.stop()
        state = .transcribing
        let url = recorder.tempAudioURL
        // Hold the lock until recognition is DONE: while the request is running, dictation must not
        // start — it would grab the microphone and overwrite the state underneath.
        defer { recorder.deleteFile(); releaseToken() }

        let text = await recognise(url: url)
        // An empty result is not a failure but "didn't catch that": the same handling as the main
        // path. The user needs to tell "didn't hear" from "broke".
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failed("module.tryOut.voice.nothing".loc)
            return
        }
        Log.info(.voice, "Проба голоса: распознано \(text.count) симв.")  // the text itself is NOT logged (privacy)
        state = .done(text)
    }

    /// Recognize THE SAME way that is selected on screen — otherwise the try-out would test
    /// something other than what the user actually uses.
    private func recognise(url: URL) async -> String? {
        let mode = VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? "") ?? .default
        if mode == .onDevice {
            return await LocalTranscriber.shared.transcribe(url: url)?.text
        }
        do {
            return try await cloud.transcribe(url: url)
        } catch {
            Log.warn(.voice, "Проба голоса: облако отказало (\(LogSanitizer.sanitize(error.localizedDescription)))")
            return nil
        }
    }

    private func reason(for failure: VoiceRecorder.StartFailure) -> String {
        switch failure {
        case .permissionUnknown, .notPermitted: return "module.tryOut.voice.noMic".loc
        case .deviceUnavailable:                return "module.tryOut.voice.nothing".loc
        }
    }
}
