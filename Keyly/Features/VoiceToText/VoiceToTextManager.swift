import AppKit
import AVFoundation
import Foundation

@MainActor
protocol VoiceTimerPresenting: AnyObject {
    func showVoiceTimer(_ text: String)
    func hideVoiceTimer()
    /// Removes the menu bar icon entirely — for the duration of dictation.
    func hideMenuBarIcon()
    /// Brings the icon back — when dictation is finished.
    func restoreMenuBarIcon()
}

@MainActor
protocol VoiceRecordingOverlayPresenting: AnyObject {
    func showVoiceRecordingOverlay(elapsedProvider: @escaping () -> Int,
                                   onCancel: @escaping () -> Void,
                                   placement: VoiceIndicatorPlacement)
    /// Recording stopped, recognition in progress. The badge STAYS and changes its look.
    func markVoiceOverlayProcessing()
    /// Text inserted and left on the clipboard: show it, then the plate hides by itself.
    @discardableResult
    func markVoiceOverlayCopied() -> Bool
    func hideVoiceRecordingOverlay()
}

@MainActor
protocol VoiceErrorToastPresenting: AnyObject {
    func showVoiceErrorToast(message: String)
    /// A toast with its OWN action. The generic handler opens Keyly settings, but a busy
    /// microphone is fixed in the system sound settings — sending the user to the wrong
    /// place is worse than not sending them anywhere.
    func showVoiceErrorToast(message: String, actionTitle: String, action: @escaping () -> Void)
    func showVoiceInfoToast(message: String)
}

/// Coordinates recording, transcription and inserting the result.
@MainActor
final class VoiceToTextManager: NSObject {
    static let shared = VoiceToTextManager()

    weak var statusPresenter: VoiceTimerPresenting?
    weak var statusAnimator: MenuBarAnimating?
    weak var overlayPresenter: VoiceRecordingOverlayPresenting?
    weak var realtimeIndicatorPresenter: RealtimeIndicatorPresenting?
    weak var badgePresenter: BadgePresenting?
    weak var errorToastPresenter: VoiceErrorToastPresenting? {
        didSet { transcriptionService.errorToastPresenter = errorToastPresenter }
    }

    private let recorder = VoiceRecorder()
    private let transcriptionService = TranscriptionService()
    private var isTranscribing = false
    private var startDate: Date?
    private var recordingTimer: Timer?
    private var focusSnapshot: FocusSnapshot?
    private var realtimeSession: RealtimeVoiceSession?
    /// What we have already "typed" into the active field in realtime mode — we need to know
    /// how many backspaces to send before replacing it with the final formatted text.
    private var realtimeTypedText: String = ""

    /// Background polish task: after dictation stops, names/terms are fixed in the background.
    private var polishTask: Task<Void, Never>?

    private struct FocusSnapshot {
        let app: NSRunningApplication?
        let element: AXUIElement
    }

    override private init() {}

    // MARK: - Public

    /// Whether real dictation is in progress. Needed by the level monitor on the settings screen:
    /// two open captures of one microphone cause a device failure or a silent track in one of them.
    var isDictating: Bool { recorder.isRecording || isTranscribing || realtimeSession != nil }

    func startSession() {
        if isTranscribing { return }
        // Pressing the hotkey again during an active session means stop.
        if recorder.isRecording {
            Task { await stopAndTranscribe() }
            return
        }
        if realtimeSession != nil {
            Task { await stopRealtimeAndPaste() }
            return
        }
        // Refuse BEFORE recording, not after. The user used to learn the reason only after
        // speaking the phrase: recording ran, the microphone was on, and only at recognition
        // did it turn out the model wasn't downloaded. What is known in advance must be
        // checked in advance.
        if let badge = refusalBeforeRecording() {
            // An empty string means refusal WITHOUT a message: the user just pressed "Cancel"
            // themselves, there is no need to repeat that with a badge.
            if !badge.isEmpty { badgePresenter?.showBadge(badge, kind: .warning) }
            return
        }

        // Hold the lock for the WHOLE dictation, not just recognition. The side effect is
        // intentional: the lock also enables the global Esc, which is what provides
        // "cancel recording with Esc" — no second mechanism is needed for that.
        guard let token = OperationGate.begin(.voice) else { return }
        token.onCancel = { [weak self] in self?.cancelRecordingSession() }
        operationToken = token
        // The settings screen may hold the microphone for the live level indicator — yield it
        // to dictation. A check on the monitor's side is not enough: it looks at busyness only
        // when it starts, and the user opens that section BEFORE pressing the hotkey.
        InputLevelMonitor.shared.suspendForDictation()

        startDate = Date()
        focusSnapshot = captureFocusSnapshot()
        startTimer()

        if shouldUseRealtime() {
            startRealtimeSession()
        } else {
            startFileSession()
        }
    }

    /// What to do after the user answers "no model: download or use the cloud?".
    ///
    /// The method used to return nothing, and the caller continued recording on ANY outcome —
    /// including "Cancel". This reproduced the bug exactly: "Cancel" → 18 seconds of speech →
    /// "local model not downloaded".
    enum ModelMissingAnswer {
        /// Allowed the cloud — recording may proceed.
        case proceed
        /// Started the download — nothing to record with yet.
        case startedDownload
        /// Cancelled.
        case cancelled
    }

    /// One question for the lifetime of the installation: download the model or work in the cloud.
    /// "Cancel" remembers nothing — the user may have pressed the hotkey by accident.
    private func askModelMissingChoice() -> ModelMissingAnswer {
        let alert = NSAlert()
        alert.messageText = "voice.modelMissing.title".loc
        alert.informativeText = "voice.modelMissing.body".loc
        alert.addButton(withTitle: "voice.modelMissing.download".loc)
        alert.addButton(withTitle: "voice.modelMissing.cloud".loc)
        alert.addButton(withTitle: "common.cancel".loc)
        // Keyly lives in the menu bar and keeps no window in front. Without explicit activation
        // `runModal` draws the dialog BEHIND another app's window: the user presses the hotkey in an
        // email and sees… nothing, while the main thread sits in the modal loop — the module is dead,
        // and there is no way out (observed: an empty screen and a blocked main thread).
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            ModelMissingChoice.stored = .download
            Task { await LocalTranscriber.shared.prepare() }
            return .startedDownload
        case .alertSecondButtonReturn:
            ModelMissingChoice.stored = .useCloud
            return .proceed
        default:
            return .cancelled
        }
    }

    /// Why recording must NOT start. `nil` means it may.
    ///
    /// Checks what is known BEFORE the first word: whether the local model is downloaded, whether
    /// a download is in progress, whether cloud mode has a key. None of this changes during
    /// recording, and finding out afterwards wastes the user's time.
    private func refusalBeforeRecording() -> String? {
        let hasKey = APIKeyStore.shared.entry(
            for: APIKeyStore.shared.currentSelection(for: .voiceToText)) != nil

        switch recognitionMode {
        case .onDevice:
            // Files on disk = nothing to refuse for: `transcribe` loads the model into memory
            // itself. Without this branch a user with a downloaded model was asked after every
            // launch "no model, download or use the cloud?" — and answering "cloud" quietly sent
            // their speech out forever.
            //
            // BUT not when loading the model was already tried and failed: after a failure a
            // 60-second cooldown applies, `prepare()` doesn't even retry in that window, and the
            // recording is guaranteed to end in a refusal. Letting it through would bring back
            // exactly the class this fixes — "told after a long recording", only for a broken
            // model instead of a missing one.
            if case .failed = LocalTranscriber.shared.state {
                Log.warn(.voice, "VoiceToText: запись не начата — модель на диске есть, но подняться не смогла")
                return BadgeText.localModelFailed
            }
            if LocalTranscriber.isDownloadedOnDisk { return nil }
            switch LocalTranscriber.shared.state {
            case .ready:
                return nil
            case .downloading(let progress):
                let percent = Int((progress * 100).rounded())
                Log.warn(.voice, "VoiceToText: запись не начата — модель качается, \(percent)%")
                return "badge.localModelDownloading".loc(percent)
            default:
                // Ask once what the user wants and remember the answer: the hotkey is pressed
                // dozens of times a day, and a dialog on every press would turn the feature
                // into an interrogation.
                switch ModelMissingChoice.action(modelReady: false, hasKey: hasKey,
                                                 stored: ModelMissingChoice.stored) {
                case .cloud:
                    return nil   // the user allowed the cloud — proceed without asking
                case .ask:
                    Log.info(.voice, "VoiceToText: модель не скачана, спрашиваем один раз")
                    // The answer DECIDES whether to start recording. This used to be an
                    // unconditional `return nil` ("the dialog will decide what to do next") — and
                    // after "Cancel" or "Download" the product still started recording and refused
                    // only after the spoken phrase: "Cancel" → 18 seconds of speech → "local model
                    // not downloaded".
                    switch askModelMissingChoice() {
                    case .proceed:
                        return nil
                    case .startedDownload:
                        Log.info(.voice, "VoiceToText: запись не начата — только что запущено скачивание модели")
                        return "badge.localModelDownloading".loc(0)
                    case .cancelled:
                        // Silently: the user just pressed "Cancel" themselves, telling them the
                        // same thing is noise. Nothing was recorded, nothing to lose.
                        Log.info(.voice, "VoiceToText: запись не начата — человек отменил диалог")
                        return ""
                    }
                case .refuse, .useLocal:
                    Log.warn(.voice, "VoiceToText: запись не начата — локальная модель не скачана")
                    return hasKey ? BadgeText.localModelMissing : BadgeText.localModelOrKey
                }
            }
        case .cloudBatch, .cloudLive:
            guard hasKey else {
                Log.warn(.voice, "VoiceToText: запись не начата — нет ключа для облачного режима")
                return BadgeText.voiceNeedsKey
            }
            // No network — refuse BEFORE recording. Recording half a minute of speech and
            // reporting the network only at recognition means losing what was said.
            guard !NetworkReachability.shared.isDefinitelyOffline else {
                Log.warn(.voice, "VoiceToText: запись не начата — сети нет")
                return BadgeText.offline
            }
            return nil
        }
    }

    // MARK: - Path selection

    private var recognitionMode: VoiceRecognitionMode {
        VoiceRecognitionMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? "")
            ?? .default
    }

    /// Whether live typing is ACTUALLY possible. The screen doesn't allow an incompatible
    /// combination, but settings may have changed since (key changed, model changed) — then we
    /// honestly fall back to batch mode instead of trying to open a socket that won't open.
    private func shouldUseRealtime() -> Bool {
        guard recognitionMode.isLive else { return false }
        let store = APIKeyStore.shared
        let sel = store.currentSelection(for: .voiceToText)
        guard sel.provider == .openai, store.entry(for: sel) != nil else {
            Log.warn(.voice, "VoiceToText: живая печать выбрана, но ключ не подходит — пакетный режим")
            return false
        }
        // Check the RECOGNITION model, not the one selected in the picker: the picker now holds
        // the text post-processing model, and its name has nothing to do with streaming
        // recognition.
        guard !VoiceRecognitionMode.modelsWithoutLive.contains(TranscriptionModelCatalog.selectedOpenAI) else {
            Log.warn(.voice, "VoiceToText: модель распознавания не умеет живую печать — пакетный режим")
            return false
        }
        return true
    }

    private func startFileSession() {
        do {
            statusPresenter?.hideMenuBarIcon()
            // Input lost (headset unplugged) → stop and transcribe what was recorded.
            // No point continuing: digital zero is being written to the file while the user
            // sees the timer running and talks into the void.
            recorder.onSignalLost = { [weak self] verdict in
                guard let self, self.recorder.isRecording else { return }
                switch verdict {
                case .ok:
                    return
                case .lost:
                    // There WAS input and it dropped: what was recorded before is worth transcribing.
                    Log.warn(.voice, "VoiceToText: вход пропал — останавливаем запись")
                    self.badgePresenter?.showBadge(BadgeText.inputLost, kind: .warning)
                    Task { await self.stopAndTranscribe() }
                case .neverStarted:
                    // There was NO sound at all. Nothing to transcribe here, and it must not be sent
                    // to the cloud: such a "recording" once went to OpenAI and came back as eleven
                    // characters of hallucination, which the product inserted into the user's window.
                    // Paid for with their money and a corrupted text.
                    Log.error(.voice, "VoiceToText: система не дала звук — запись отменена, "
                                      + "в облако НИЧЕГО не отправлено")
                    self.badgePresenter?.showBadge(BadgeText.micNoSignal, kind: .warning)
                    self.cancelRecordingSession()
                    // Open settings ONCE per session: otherwise every hotkey press would steal
                    // focus and cover the badge that was just shown.
                    if !self.micSettingsOpened {
                        self.micSettingsOpened = true
                        MicrophonePermission.openMicrophoneSettings()
                    }
                }
            }
            try recorder.start()
            micSettingsOpened = false   // permission granted — show the next denial in settings again
            // Read the setting here too: the batch path showed the badge UNCONDITIONALLY, so
            // "Don't show" didn't work at all, and "At the cursor" behaved like "Top center".
            overlayPresenter?.showVoiceRecordingOverlay(
                elapsedProvider: { [weak self] in self?.elapsedSeconds() ?? 0 },
                onCancel: { [weak self] in self?.cancelRecordingSession() },
                placement: indicatorPlacement
            )
        } catch {
            Log.error(.voice, "VoiceToText: не удалось начать запись: \(error)")
            startDate = nil
            stopTimer()
            finishOverlay()
            statusPresenter?.restoreMenuBarIcon()
            releaseOperation()
            // The refusal must be VISIBLE. It used to go only to the log, and the user got
            // exactly what a successful recording without speech gives — silence.
            switch error {
            case VoiceRecorder.StartFailure.permissionUnknown:
                // Permission not asked yet — show the NATIVE dialog. No badge here on purpose:
                // the system window explains the situation itself, and a badge under it simply
                // wouldn't be read.
                MicrophonePermission.ensurePermission(prompt: true)
            case VoiceRecorder.StartFailure.notPermitted:
                badgePresenter?.showBadge(BadgeText.micDenied, kind: .warning)
                // Open settings ONCE per denial session. Otherwise every hotkey press would
                // steal focus into the system window — and also cover the badge that was just
                // shown, so the user wouldn't have time to read it.
                if !micSettingsOpened {
                    micSettingsOpened = true
                    MicrophonePermission.openMicrophoneSettings()
                }
            case VoiceRecorder.StartFailure.deviceUnavailable:
                // A toast, not a badge: a badge has neither room for an explanation nor a
                // click, and the fix isn't in Keyly — the microphone is busy with another
                // app or the wrong input is selected.
                errorToastPresenter?.showVoiceErrorToast(
                    message: "voice.micBusy.body".loc,
                    actionTitle: "voice.micBusy.action".loc,
                    action: { MicrophonePermission.openSoundSettings() }
                )
            default:
                badgePresenter?.showBadge(BadgeText.recordFailed, kind: .warning)
            }
        }
    }

    private func startRealtimeSession() {
        let store = APIKeyStore.shared
        let sel = store.currentSelection(for: .voiceToText)
        guard let entry = store.entry(for: sel) else {
            errorToastPresenter?.showVoiceErrorToast(message: "voice.err.noOpenAIKey".loc)
            stopTimer()
            startDate = nil
            releaseOperation()
            return
        }
        // Recognition is always done by the transcription model. The picker holds the
        // text POST-PROCESSING model, and it must not be sent for recognition.
        let model = TranscriptionModelCatalog.selectedOpenAI

        // If the previous polish is still running, cancel it — otherwise it would overwrite fresh deltas.
        polishTask?.cancel()
        polishTask = nil
        realtimeTypedText = ""

        let session = RealtimeVoiceSession()
        session.onFailed = { [weak self] msg in
            guard let self else { return }
            Task { @MainActor in
                await self.handleRealtimeFailure(message: msg)
            }
        }
        // Every delta from the model is typed into the active field right away as a unicode keypress.
        // Whisper models almost always start output with a leading space (a tokenizer
        // artifact), so that space is eaten from the very first delta of the session.
        session.onDeltaTyped = { [weak self] delta in
            guard let self else { return }
            // Don't type during finalizing/stop — otherwise a late delta would sneak in after
            // `typed` is captured and desync the field from what we are about to replace.
            guard !self.isTranscribing else { return }
            var piece = delta
            if self.realtimeTypedText.isEmpty {
                piece = String(piece.drop(while: { $0.isWhitespace }))
            }
            guard !piece.isEmpty else { return }
            // Secure field: live typing is not allowed. The check is cheap (no BFS/hit test), and
            // focus may have moved to a password field during dictation.
            //
            // Staying silent is not an option: the user keeps talking, text stops appearing
            // mid-sentence, and without an explanation it looks like a breakage. Tell them ONCE per
            // session, otherwise the toast would pop up on every word.
            // The `realtimeTypedText` accumulator is NOT extended here — otherwise the final
            // replacement would count backspaces for text that isn't in the field and eat someone else's.
            if CaretProbe.isSecureNow() {
                if !self.liveTypingBlockedNotified {
                    self.liveTypingBlockedNotified = true
                    Log.warn(.voice, "VoiceToText: живая печать остановлена — защищённое поле")
                    self.badgePresenter?.showBadge(BadgeText.secureTyping, kind: .warning)
                }
                return
            }
            self.realtimeTypedText += piece
            TextInjector.type(piece, source: .combinedSession)
        }
        liveTypingBlockedNotified = false   // new session — warn again
        realtimeSession = session

        // No text overlay — the text goes straight into the field with the cursor. But
        // a compact corner "recording" indicator is shown (unless disabled).
        statusPresenter?.hideMenuBarIcon()
        do {
            realtimeIndicatorPresenter?.showRealtimeIndicator(
                session: session,
                elapsedProvider: { [weak self] in self?.elapsedSeconds() ?? 0 }
            )
        }
        // Language from settings. "Auto" = don't send a code at all: a forced language on
        // mixed ru/en speech hurts the result more than it helps.
        let language = VoiceLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceLanguage) ?? "") ?? .default
        session.start(apiKey: entry.value, model: model, language: language.apiCode ?? "ru")
    }

    /// Auto-fallback: realtime failed — try sending the accumulated audio through the regular
    /// /v1/audio/transcriptions so the user gets at least something.
    private func handleRealtimeFailure(message: String) async {
        guard let session = realtimeSession else { return }
        session.onDeltaTyped = nil
        // Ahead is an attempt to transcribe the accumulated audio via the file path — that is
        // processing, and it must be visible. The badge is hidden in `defer`, not here.
        realtimeIndicatorPresenter?.markRealtimeIndicatorProcessing()
        defer { finishOverlay(); statusPresenter?.restoreMenuBarIcon(); releaseOperation() }
        // At least 1.5 s — on short recordings whisper models sometimes return an echo
        // of the prompt instead of "empty". 1.5 s guarantees the file contains speech.
        let hasUsableAudio = session.capturedSeconds >= 1.5
        let typed = realtimeTypedText
        Log.error(.voice, "VoiceToText: realtime failed (\(message)), captured=\(String(format: "%.2f", session.capturedSeconds))s, typed=\(typed.count) chars")

        stopTimer()
        startDate = nil
        realtimeSession = nil
        statusAnimator?.endMenuAnimation()

        guard hasUsableAudio else {
            // There was no connection — roll back what was typed (if anything got through).
            if !typed.isEmpty {
                await replaceTypedText(oldLength: typed.count, newText: "")
            }
            errorToastPresenter?.showVoiceErrorToast(
                message: "voice.err.realtimeFailed".loc
            )
            realtimeTypedText = ""
            focusSnapshot = nil
            return
        }

        // Dump the PCM to a WAV file and send it the regular way.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("realtime-fallback-\(UUID().uuidString).wav")
        guard session.writeCapturedAudio(to: tempURL) else {
            errorToastPresenter?.showVoiceErrorToast(message: message)
            focusSnapshot = nil
            return
        }

        Log.warn(.voice, "VoiceToText: fallback start, wav=\(tempURL.lastPathComponent)")
        // The fallback to file transcription is done SILENTLY — the user doesn't need the
        // transport internals, only the result (the "Processing…" indicator already said it all).
        isTranscribing = true
        defer {
            isTranscribing = false
            try? FileManager.default.removeItem(at: tempURL)
        }

        statusAnimator?.beginMenuAnimation()
        defer { statusAnimator?.endMenuAnimation() }

        do {
            let raw = try await transcriptionService.transcribe(url: tempURL)
            Log.warn(.voice, "VoiceToText: fallback вернул текст длиной \(raw.count)")

            // Paragraph formatting in the fallback goes through the LLM (as in the file-based path).
            let formatted = await TextPolisher.apply(raw, target: postProcessTarget())
            let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)

            // Replace what realtime typed with the final fallback text.
            if !trimmed.isEmpty {
                await replaceTypedText(oldLength: typed.count, newText: trimmed)
            } else if !typed.isEmpty {
                await replaceTypedText(oldLength: typed.count, newText: "")
            }
            realtimeTypedText = ""
            focusSnapshot = nil
        } catch {
            Log.error(.voice, "VoiceToText: fallback transcribe failed: \(error.localizedDescription)")
            if !typed.isEmpty {
                await replaceTypedText(oldLength: typed.count, newText: "")
            }
            realtimeTypedText = ""
            errorToastPresenter?.showVoiceErrorToast(message: humanReadableError(error))
            focusSnapshot = nil
        }
    }

    private func humanReadableError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "voice.err.offline".loc
            case .timedOut: return "voice.err.timeout".loc
            default: return "voice.err.network".loc
            }
        }
        return "voice.err.generic".loc
    }

    // MARK: - Recording lifecycle

    // MARK: - Recording lifecycle

    private func stopAndTranscribe() async {
        guard !isTranscribing else { return }
        isTranscribing = true
        defer { isTranscribing = false }
        // Cleanup via defer — otherwise an early return (no audio file) would leave the menu bar
        // icon hidden forever and wouldn't reset focusSnapshot for the next session.
        defer {
            recorder.deleteFile()
            focusSnapshot = nil
            statusPresenter?.restoreMenuBarIcon()
            finishOverlay()
            releaseOperation()
        }

        recorder.stop()
        stopTimer()
        startDate = nil
        // The badge STAYS until recognition finishes and changes its look. It is the only sign
        // that the recording was accepted and is being processed: it used to disappear here, and
        // a user who didn't see text within a second pressed the hotkey a second time.
        overlayPresenter?.markVoiceOverlayProcessing()

        let url = recorder.tempAudioURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.warn(.voice, "VoiceToText: нет аудиофайла — запись не состоялась")
            badgePresenter?.showBadge(BadgeText.recordFailed, kind: .warning)
            return
        }

        do {
            statusAnimator?.beginMenuAnimation()
            defer { statusAnimator?.endMenuAnimation() }
            // Engine choice from settings. The local path has no silent cloud fallback: inserting
            // nothing silently is worse than refusing with a reason (see below).
            let mode = recognitionMode
            let text: String
            // Take the local path when the model is ready OR its files are on disk.
            //
            // This used to check only `state.isReady`, which means "loaded into RAM" — a state that
            // resets on every app launch. A downloaded model was loaded into memory only by the
            // "Download" button on the settings screen, so after a restart the product declared it
            // missing. The reason for the original condition ("`transcribe` must not download a
            // gigabyte during dictation") still holds and is covered by the file check: the set is
            // on disk — so `prepare()` only loads it into memory in seconds, downloading nothing.
            if mode == .onDevice, LocalTranscriber.shared.isUsable,
               let local = await LocalTranscriber.shared.transcribe(url: url) {
                text = local.text
                Log.info(.voice, "VoiceToText: распознано локально, ×\(String(format: "%.1f", local.realtimeFactor)) от реального времени")
            } else if mode == .onDevice {
                // The selected mode is NOT silently replaced with another — especially when the
                // replacement changes the DATA ROUTE. This used to say "go to the cloud": the user
                // chose "On this computer" so their speech wouldn't leave the machine, the screen
                // promised "works without network or key", and the recording went to OpenAI with
                // their own key. The only trace was a log line — and a log is not consent.
                //
                // Refuse and name the reason. Switching to the cloud is possible only by the user's
                // explicit answer, and that answer is remembered.
                // The user may have ALLOWED the cloud when the model was missing. That is not a
                // silent route change but their own remembered answer — refusing against it would
                // be just as wrong.
                // "Downloaded" and "worked" are DIFFERENT things, and the message must tell them
                // apart. While the reason was derived from `state.isReady`, a user with a downloaded
                // model was told "not downloaded" — i.e. offered to download almost a gigabyte they
                // already had, instead of the truth "the model failed to start".
                let downloaded = LocalTranscriber.isDownloadedOnDisk
                if !downloaded, ModelMissingChoice.stored == .useCloud {
                    Log.info(.voice, "VoiceToText: модели нет, но облако разрешено человеком — распознаём в облаке")
                    text = try await transcriptionService.transcribe(url: url)
                } else {
                    let reason = downloaded ? BadgeText.localModelFailed : BadgeText.localModelMissing
                    Log.warn(.voice, "VoiceToText: локальная модель \(downloaded ? "не дала результата (файлы на месте)" : "не скачана") — ОТКАЗ, в облако не уходим")
                    badgePresenter?.showBadge(reason, kind: .warning)
                    return
                }
            } else {
                text = try await transcriptionService.transcribe(url: url)
            }
            Log.info(.voice, "VoiceToText: транскрипция получена, \(text.count) симв.")  // the text itself is NOT logged (privacy)
            // The post-processing tail shared by ALL recognition methods. It used to hang only on
            // the OpenAI branch of the file path: Gemini and the local model returned raw text, and
            // the enabled "paragraphs" and "anglicisms" settings simply had no effect on them.
            let polished = await TextPolisher.apply(text, target: postProcessTarget())
            #if DEBUG
            // Local model vs cloud measurement. Started BEFORE insertion, but runs asynchronously
            // and doesn't delay it — otherwise the measurement would distort the impression of
            // speed, which is the very reason the local model is being considered.
            ASRCompare.compare(cloudText: text, audioURL: url)
            #endif

            // An empty result is neither success nor failure but "didn't catch that". An empty
            // string used to go silently into the paste: the user saw nothing at all and couldn't
            // tell whether the app broke or they spoke too quietly.
            guard !polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.warn(.voice, "VoiceToText: распознавание вернуло пустой текст")
                badgePresenter?.showBadge(BadgeText.nothingHeard, kind: .warning)
                return
            }

            await restoreFocusIfPossible()
            // Add a space before insertion if the caret sits right after a letter or a period
            // ("…or not.This is a penalty" — dictated text stuck to the previous sentence, and
            // the user had to fix it by hand).
            let toInsert = InsertSpacing.prepared(polished, previous: characterBeforeCaret())
            pendingInsertText = toInsert
            guard canInsertRecognizedText() else { return }
            let keepInClipboard = UserDefaults.standard.object(forKey: SettingsKeys.voiceKeepInClipboard) as? Bool ?? true
            await TextInjector.paste(toInsert, source: .combinedSession, style: .physicalCommandKey,
                                     clipboard: keepInClipboard ? .keepResult : .restoring,
                                     context: "voice:transcribe")
            if keepInClipboard, overlayPresenter?.markVoiceOverlayCopied() == true {
                overlayHidesItself = true
            }
            // Count WORDS, and only those actually inserted: when the gate above refuses
            // we never get here, and dictation into the clipboard doesn't increase the counter.
            UsageStatsStore.shared.record(.dictatedWords, count: polished.wordCount)
        } catch {
            if let apiErr = error as? APIKeyError, apiErr == .missingKey {
                APIKeyStore.shared.presentMissingKeyAlert()
            }
            Log.error(.voice, "VoiceToText: все попытки исчерпаны: \(error)")
        }
    }

    /// The character left of the caret — needed to decide whether to put a space before the insertion.
    ///
    /// Read via Accessibility and ONLY one character: fetching the whole field value for one
    /// character means pulling someone else's document into memory. If it can't be read, assume
    /// the caret is at the start: an extra space is more noticeable and worse than a missing one.
    private func characterBeforeCaret() -> Character? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)

        var rangeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRaw) == .success,
              let rangeRaw, CFGetTypeID(rangeRaw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(rangeRaw, to: AXValue.self), .cfRange, &range),
              range.location > 0 else { return nil }

        var previous = CFRange(location: range.location - 1, length: 1)
        guard let previousValue = AXValueCreate(.cfRange, &previous) else { return nil }
        var textRaw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString,
                previousValue, &textRaw) == .success,
              let text = textRaw as? String else { return nil }
        return text.first
    }

    private func cancelRecordingSession() {
        if realtimeSession != nil {
            cancelRealtimeSession()
            return
        }
        guard recorder.isRecording else { return }
        statusAnimator?.endMenuAnimation()
        recorder.stop()
        stopTimer()
        finishOverlay()
        startDate = nil
        recorder.deleteFile()
        focusSnapshot = nil
        statusPresenter?.restoreMenuBarIcon()
        releaseOperation()
        Log.warn(.voice, "VoiceToText: запись отменена")
    }

    private func cancelRealtimeSession() {
        guard let session = realtimeSession else { return }
        session.onDeltaTyped = nil
        finishOverlay()
        let typed = realtimeTypedText
        polishTask?.cancel()
        polishTask = nil
        session.cancel()
        realtimeSession = nil
        statusAnimator?.endMenuAnimation()
        stopTimer()
        startDate = nil
        focusSnapshot = nil
        // Roll back what was typed so far.
        if !typed.isEmpty {
            Task { @MainActor in
                await self.replaceTypedText(oldLength: typed.count, newText: "")
            }
        }
        realtimeTypedText = ""
        statusPresenter?.restoreMenuBarIcon()
        releaseOperation()
        Log.warn(.voice, "VoiceToText: realtime отменено")
    }

    private func stopRealtimeAndPaste() async {
        guard let session = realtimeSession else { return }
        if isTranscribing { return }
        isTranscribing = true
        defer { isTranscribing = false }

        // CRITICAL: detach live typing right away. Otherwise deltas already received from the
        // server and still queued on the main actor would fire AFTERWARDS — typing more text into
        // the field while we count backspaces from the already captured `typed`. The field and
        // `typed` would desync → cursor in the middle, garbage letters.
        session.onDeltaTyped = nil
        // Do NOT hide the indicator: post-processing is ahead and will still edit the field.
        // It used to be removed here — and all that time the user saw nothing, although the
        // text under the cursor could change at any moment.
        realtimeIndicatorPresenter?.markRealtimeIndicatorProcessing()
        // The text is already in the field thanks to live delta typing.
        let typed = realtimeTypedText
        session.cancel()
        realtimeSession = nil
        stopTimer()
        startDate = nil

        realtimeTypedText = ""
        focusSnapshot = nil

        // Background post-processing — the same level and the same code as the file path
        // (`TextPolisher`). There used to be a separate pair of conditions with its own priority:
        // with polishing on, paragraph splitting was silently ignored.
        let level = TextPolisher.level
        let target = postProcessTarget()
        if !typed.isEmpty, level.requiresLLM, target.isUsable {
            startBackgroundPostProcess(typed: typed, target: target, level: level)
        } else {
            // Nothing to process — dictation ends right here, remove the badge.
            finishOverlay()
            statusPresenter?.restoreMenuBarIcon()
            releaseOperation()
        }
    }

    /// Where transcript post-processing goes: provider, key and model — in ONE store read.
    ///
    /// These used to be two methods (`postProcessKey` and `postProcessModel`), and the provider
    /// wasn't read at all: `TextPolisher` assumed post-processing was always OpenAI. With a Gemini
    /// key the user got a 401 and a "Couldn't polish" message without a reason. Post-processing
    /// goes TO THE SAME provider whose key is selected on the voice screen — as the keys screen
    /// promises ("goes only to the selected provider"), and regardless of who did the
    /// recognition: the local model also sends text to the cloud at this step.
    private func postProcessTarget() -> TextPolishTarget {
        let store = APIKeyStore.shared
        let selection = store.currentSelection(for: .voiceToText)
        let entry = store.entry(for: selection)
        let provider = entry?.provider ?? selection.provider
        return TextPolishTarget(provider: provider,
                                apiKey: entry?.value ?? "",
                                model: postProcessModel(provider: provider))
    }

    /// The transcript POST-PROCESSING model: the chat model from the picker. A transcription model
    /// must not get here — it doesn't accept a chat request, and post-processing silently failed
    /// with a "Processing failed" badge instead of paragraphs. The fallback model is taken from the
    /// CURRENT provider: substituting the OpenAI default for a Gemini key would just trade one
    /// failure for another.
    private func postProcessModel(provider: APIProvider) -> String {
        let picked = APIKeyStore.shared.model(for: .voiceToText)
        let resolved = TextPolishModel.resolve(picked: picked,
                                               transcriptionModelIDs: Set(TranscriptionModelCatalog.openAIIDs),
                                               fallback: provider.defaultModel)
        if resolved != picked {
            Log.warn(.voice, "VoiceToText: в пикере осталась транскрипционная модель «\(picked)» — обрабатываем текст запасной чат-моделью \(provider.title)")
        }
        return resolved
    }

    /// Recording badge placement — THE key the UI writes.
    ///
    /// This used to read the legacy key `voiceIndicatorEnabled`, which had NOT A SINGLE writer:
    /// it always returned the default `true`. The picker on the voice screen wrote
    /// `voiceIndicatorPlacement`, and nobody read that key. The control toggled, was saved and
    /// affected nothing — a phantom setting, including the "Don't show" option, which showed.
    private var indicatorPlacement: VoiceIndicatorPlacement {
        VoiceIndicatorPlacement(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceIndicatorPlacement) ?? ""
        ) ?? .default
    }

    /// Starts post-processing in the background. The menu bar icon stays hidden until
    /// the pass finishes. If the result differs, the tail after the common prefix is
    /// replaced via a lossless AX substitution.
    private func startBackgroundPostProcess(typed: String, target: TextPolishTarget, level: TextPolishLevel) {
        polishTask?.cancel()
        polishTask = Task { @MainActor [weak self] in
            defer {
                // The "Processing…" badge was kept exactly until this point: post-processing edits
                // already inserted text, and removing the sign of work earlier would promise
                // that the field won't be touched anymore.
                self?.finishOverlay()
                self?.statusPresenter?.restoreMenuBarIcon()
                self?.polishTask = nil
                // Release the lock HERE, not in stopRealtimeAndPaste: post-processing runs
                // in the background and keeps editing the field after stop returns.
                self?.releaseOperation()
            }
            let processed = await TextPolisher.apply(typed, level: level, target: target)
            if Task.isCancelled { return }
            let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == typed { return }
            guard let self else { return }
            let common = typed.commonPrefix(with: trimmed)
            let toDelete = typed.count - common.count
            let toType = String(trimmed.dropFirst(common.count))

            // Diagnostics: compare what WE think we typed (typed) with what is ACTUALLY
            // in the field now (via AX kAXValue). If lengths/suffix differ — backspaces
            // were counted from the wrong length, and the cursor will end up in the middle.
            let fieldText = self.axFocusedFieldValue()
            let fieldLen = fieldText?.count ?? -1
            let endsWithTyped = fieldText?.hasSuffix(typed) ?? false
            Log.info(.voice, "VoiceToText: post-process(\(level.rawValue)) typed=\(typed.count) field=\(fieldLen) endsWithTyped=\(endsWithTyped) toDelete=\(toDelete) toType=\(toType.count)")

            await self.replaceTypedText(oldLength: toDelete, newText: toType)
        }
    }



    /// Replaces the last oldLength characters with newText:
    /// a burst of backspaces (erasing the flat live input from the cursor) → PASTING the new
    /// text via the clipboard (Cmd+V), not unicode typing.
    ///
    /// Why paste and not keystroke typing: the final text contains `\n\n` (paragraphs).
    /// A synthetic newline press in a regular editor is a line break, but in terminal fields
    /// (Claude Code, etc.) newline means "send", so keystroke retyping there broke off at the
    /// first `\n`, the counters desynced and the cursor ended up in the middle. A paste goes
    /// through bracketed paste — terminals insert line breaks literally without executing them.
    /// Backspace over the flat live input (no `\n`) is safe everywhere.
    private func replaceTypedText(oldLength: Int, newText: String) async {
        if oldLength > 0 {
            await TextInjector.deleteBackward(oldLength, source: .combinedSession)
            // Wait until the app applies all deletions before inserting the new text —
            // events go through one FIFO queue, but leave a margin for slow apps.
            try? await Task.sleep(nanoseconds: 60_000_000)  // 60 ms
        }
        guard !newText.isEmpty else { return }
        // Without line breaks, type with keys — the clipboard isn't touched at all.
        // With line breaks (paragraphs) a paste is needed: in terminal fields a newline press
        // means "send", while bracketed paste inserts line breaks literally.
        if newText.contains("\n") {
            await TextInjector.paste(newText, source: .combinedSession, style: .physicalCommandKey, context: "voice:replace")
        } else {
            TextInjector.type(newText, source: .combinedSession)
        }
    }



    /// Reads the active field's text via AX (kAXValue). For desync diagnostics.
    private func axFocusedFieldValue() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }


    // MARK: - Timer

    private func startTimer() {
        updateTimerLabel()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimerLabel()
        }
        if let t = recordingTimer { RunLoop.main.add(t, forMode: .common) }
    }

    /// Stops the TIMER, but not the badge.
    ///
    /// This method used to remove the badge too — so it disappeared exactly when the user
    /// released the hotkey: recognition followed, nothing happened on screen, and that was
    /// indistinguishable from "didn't work". The badge is now removed at every point where
    /// dictation FINISHES (`finishOverlay`), not when the timer stops.
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        statusPresenter?.hideVoiceTimer()
    }

    /// Dictation is completely over (text inserted, refusal shown, cancelled) — remove both
    /// badges. Both, because the recognition path may have changed along the way (fallback).
    private func finishOverlay() {
        // After "copied" the plate stays a moment and hides itself.
        if overlayHidesItself {
            overlayHidesItself = false
        } else {
            overlayPresenter?.hideVoiceRecordingOverlay()
        }
        realtimeIndicatorPresenter?.hideRealtimeIndicator()
    }

    private var overlayHidesItself = false

    private func updateTimerLabel() {
        guard let start = startDate else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        statusPresenter?.showVoiceTimer(String(format: "🎙 %d:%02d", elapsed / 60, elapsed % 60))
    }

    private func elapsedSeconds() -> Int {
        guard let startDate else { return 0 }
        return Int(Date().timeIntervalSince(startDate))
    }

    // MARK: - Focus

    private func captureFocusSnapshot() -> FocusSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let app = NSWorkspace.shared.frontmostApplication
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return FocusSnapshot(app: app, element: unsafeBitCast(focused, to: AXUIElement.self))
    }

    // MARK: - Gate for inserting recognized text

    /// Whether recognized text may be inserted into the current focus.
    ///
    /// Voice was the ONLY service without caret probes: it inserted both where there is no input
    /// field at all (desktop, Finder — the paste went nowhere, while the result counted as
    /// delivered) and into password fields (the model's output overwrote the password being typed).
    ///
    /// Call AFTER `restoreFocusIfPossible()` — before focus is restored our own app is in front,
    /// and the probe would describe it instead of the target.
    ///
    /// `false` → the text stays on the clipboard (the caller puts it there) + a toast: silently
    /// losing the dictation is not allowed, it is the only result of the user's work.
    private func canInsertRecognizedText() -> Bool {
        // Tier gate: always insert, except for an unambiguous "this is not a text field".
        // In Electron/web the caret tier is almost unreachable, so ambiguous/editable — insert.
        let caret = CaretProbe.resolve(context: "voice:insert")
        if caret.isDefinitelyNotField {
            // SILENTLY to the clipboard, by design: if we couldn't tell where to insert the text,
            // it has landed on the clipboard, which is fine. A message about a normal outcome
            // only gets in the way.
            Log.warn(.voice, "VoiceToText: нет поля ввода (.none) — текст в буфере, молча")
            ClipboardManager.write(pendingInsertText)
            return false
        }
        // Secure is checked LAST: resolve() above spends up to 0.28 s walking the tree, and in
        // that time focus may have moved to a password field. The check must sit right before insertion.
        if CaretProbe.isSecureNow() {
            Log.warn(.voice, "VoiceToText: secure-поле — вставка отменена, текст в буфере")
            return refuseInsertion(reason: BadgeText.secureBuffered, caretRect: caret.caretRect)
        }
        return true
    }

    /// Refusing to insert: the dictation is NOT lost — it goes to the clipboard and we say why.
    /// The channel is the badge at the caret, not an error toast: this is a normal refusal, not
    /// a failure, and an error toast offers to open settings that have nothing to do with it.
    private func refuseInsertion(reason: String, caretRect: CGRect?) -> Bool {
        ClipboardManager.write(pendingInsertText)
        badgePresenter?.showBadge(reason, kind: .warning, caretRect: caretRect)
        return false
    }

    /// The text being inserted right now: the gate needs it to put it on the clipboard on refusal.
    private var pendingInsertText: String = ""

    /// Whether the user was told in THIS session that live typing stopped (the toast is shown once).
    private var liveTypingBlockedNotified = false

    /// Whether the Privacy settings were already opened because of a microphone denial. Reset as soon
    /// as recording actually starts — i.e. permission was granted, and the next denial deserves the window again.
    private var micSettingsOpened = false

    /// Operation lock for the whole dictation. Kept in a property, not in `defer`: dictation starts
    /// in one call (hotkey) and ends in another (second hotkey press, cancel, realtime failure).
    private var operationToken: OperationGate.Token?

    /// Releases the lock. Call at EVERY point where dictation finishes — otherwise the next hotkey
    /// press gets "Already working…" and voice stays dead until restart.
    private func releaseOperation() {
        // Dictation is over — give the meter back to the screen if that section is still open.
        InputLevelMonitor.shared.resumeAfterDictation()
        operationToken?.release()
        operationToken = nil
    }

    private func restoreFocusIfPossible() async {
        guard let snapshot = focusSnapshot else { return }
        snapshot.app?.activate()
        try? await Task.sleep(nanoseconds: 140_000_000)
        AXUIElementSetAttributeValue(snapshot.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

}
