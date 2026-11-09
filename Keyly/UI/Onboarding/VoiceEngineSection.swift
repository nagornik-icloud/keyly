import SwiftUI

/// The "Recognition method" block on the "Voice → text" screen.
///
/// One choice of three instead of the old pair "engine segment + live typing toggle". Those two
/// controls described one axis but looked independent: picking "Local" while leaving live
/// typing on, the user got the cloud — and could not tell, because both controls showed
/// exactly what they had set.
///
/// Screen rule: an option that CANNOT WORK in the current configuration is shown with a
/// reason and disabled — not silently replaced by another one.
struct VoiceRecognitionSection: View {

    @AppStorage(SettingsKeys.voiceRecognitionMode) private var modeRaw: String = VoiceRecognitionMode.default.rawValue
    /// The processing level is read HERE because the truthfulness of the local option's caption
    /// depends on it: "works offline and without a key" is only true on "As spoken".
    @AppStorage(SettingsKeys.textPolishLevel) private var polishLevelRaw: String = TextPolishLevel.default.rawValue
    /// The "transcribe in the cloud while the model is missing" permission, granted once in a dialog.
    /// Read HERE because while it is in effect, the local option describes something other than
    /// what actually happens.
    @AppStorage(ModelMissingChoice.storageKey) private var modelMissingChoiceRaw: String = ""
    @StateObject private var local = LocalTranscriber.shared

    /// Provider and model of the selected key — live typing availability depends on them.
    let provider: APIProvider?
    let model: String?
    let hasKey: Bool

    private var mode: VoiceRecognitionMode {
        get { VoiceRecognitionMode(rawValue: modeRaw) ?? .default }
        nonmutating set { modeRaw = newValue.rawValue }
    }

    var body: some View {
        // TWO GROUPS instead of one list of three: subheadings — "on this computer", where
        // the model can be downloaded; then "in the cloud", with paste-all-at-once or
        // type-as-you-speak.
        //
        // The old view stacked unrelated things in one column: two cloud options, one
        // local option and a model download row "hanging" between them — and read as
        // clutter. There is still ONE choice: both groups share one `selection`, and
        // checking one unchecks the other. It is still a single setting, just grouped by
        // where the speech is processed.
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            // The setting lost its name when split into two groups: the screen showed
            // "ON THIS COMPUTER" and "IN THE CLOUD" without a word that this is ONE choice,
            // and the two groups read as two independent settings. Every other block on the
            // screen has a name — only the main one did not.
            SectionLabel(text: "voice.mode".loc)
            // An active cloud permission gets a SEPARATE row with a cancel action, not just the
            // option caption: this is the only place where the user can learn that their speech
            // goes out, and the only place where they can stop it.
            if cloudFallbackActive {
                HStack(spacing: Theme.Space.m) {
                    Text("voice.mode.cloudFallback.active".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("voice.mode.cloudFallback.revoke".loc) {
                        ModelMissingChoice.stored = nil
                        Log.info(.voice, "Разрешение на облако при отсутствующей модели отозвано человеком")
                    }
                    .buttonStyle(KeylySecondaryButtonStyle())
                    Spacer(minLength: 0)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                groupLabel("voice.mode.group.local".loc)
                KeylyOptionGroup(
                    selection: Binding(get: { mode }, set: { mode = $0 }),
                    options: [localOption],
                    trailing: { value in
                        // "Download" sits IN the option row. A separate strip under it took
                        // ~50pt of vertical space for two words, while half the width of the row
                        // itself was empty.
                        guard value == .onDevice, case .notLoaded = local.state,
                              !LocalTranscriber.isDownloadedOnDisk else { return nil }
                        return AnyView(
                            Button("voice.model.download".loc) { Task { await local.prepare() } }
                                .buttonStyle(KeylySecondaryButtonStyle())
                        )
                    },
                    detail: { value in
                        // The model status is shown under "On this computer" ALWAYS while it is not
                        // ready — even when the option is unavailable and therefore not selected. Otherwise
                        // it is a dead end: the unavailability reason points to the "Download" button, and
                        // the button is hidden precisely because the option can't be selected without the model.
                        // The inset box stays ONLY where its own row is needed: the download progress
                        // bar with percentage and the file path of a ready model. The "not downloaded"
                        // state moved to the trailing position — a button is enough for it.
                        guard value == .onDevice else { return nil }
                        if case .notLoaded = local.state, !LocalTranscriber.isDownloadedOnDisk { return nil }
                        let inapplicable = mode != .onDevice && local.state.isReady
                        return AnyView(
                            modelStatusRow
                                .keylyInapplicable(when: inapplicable,
                                                   reason: "voice.model.localOnly".loc)
                        )
                    }
                )
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                groupLabel("voice.mode.group.cloud".loc)
                KeylyOptionGroup(
                    selection: Binding(get: { mode }, set: { mode = $0 }),
                    options: cloudOptions
                )
            }
        }
    }

    /// A GROUP caption inside the setting — quieter than the setting's own name. The same
    /// `SectionLabel` on both levels made three equal headers in a row and did not show
    /// that "on this computer" and "in the cloud" are nested in "recognition method".
    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Typography.mono(10))
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.fgMuted)
    }

    /// Option titles NO longer repeat the group subheading: "In the cloud, paste all at once"
    /// under an "IN THE CLOUD" header said the word twice in two consecutive lines.
    private var localOption: KeylyOption<VoiceRecognitionMode> {
        // The caption DEPENDS on the processing level. "Works offline and without a key"
        // is exactly why people pick the local model, and they believe the first sentence,
        // not a line a thousand pixels below. On the "Polish"/"Rewrite" levels the promise
        // is false: processing goes to the cloud. The admission must stand where the
        // promise is — otherwise the screen contradicts itself.
        let polishLevel = TextPolishLevel(rawValue: polishLevelRaw) ?? .default
        // While the "transcribe in the cloud" permission is active, the caption must say so,
        // not "works offline": at that moment the app is sending audio out.
        let subtitle: String
        if cloudFallbackActive {
            subtitle = "voice.mode.onDevice.hint.cloudFallback".loc
        } else {
            subtitle = polishLevel.requiresLLM ? "voice.mode.onDevice.hint.withPolish".loc
                                               : "voice.mode.onDevice.hint".loc
        }
        return KeylyOption(value: .onDevice,
                           title: "voice.mode.onDevice".loc,
                           subtitle: subtitle,
                           disabledReason: localDisabledReason)
    }

    /// The model is missing, but the user once allowed the cloud — and since then transcription
    /// goes there silently. `ModelMissingChoice.action` returns `.cloud`, yet the screen used to
    /// show not a single line about it and offered no way to cancel: the key sat in
    /// `UserDefaults` and never appeared in the UI.
    private var cloudFallbackActive: Bool {
        !local.state.isReady && ModelMissingChoice(rawValue: modelMissingChoiceRaw) == .useCloud
    }

    /// Why the local option can't be selected. The reason depends on the model STATE: while
    /// there was a single text, it pointed to the "Download" button both during download and
    /// after a failure — i.e. it told the person who had already clicked to click (the button
    /// is not there at that moment, it exists only in the "not downloaded" state).
    private var localDisabledReason: String? {
        // Files on disk mean the mode works, even if the model is not loaded into memory yet:
        // `transcribe` calls `prepare` itself. Without this branch someone with a downloaded
        // model saw "download the model first" after every launch and couldn't select a mode
        // they had set up long ago.
        if LocalTranscriber.isDownloadedOnDisk { return nil }
        switch local.state {
        case .ready:       return nil
        case .notLoaded:   return "voice.mode.onDevice.needsModel".loc
        case .downloading: return "voice.mode.onDevice.downloading".loc
        case .failed:      return "voice.mode.onDevice.failed".loc
        }
    }

    private var cloudOptions: [KeylyOption<VoiceRecognitionMode>] {
        [
            KeylyOption(value: .cloudBatch,
                        title: "voice.mode.cloudBatch".loc,
                        subtitle: "voice.mode.cloudBatch.hint".loc,
                        disabledReason: hasKey ? nil : "voice.mode.needsKey".loc),
            KeylyOption(value: .cloudLive,
                        title: "voice.mode.cloudLive".loc,
                        subtitle: "voice.mode.cloudLive.hint".loc,
                        disabledReason: liveDisabledReason),
        ]
    }

    /// Why live typing is unavailable. Checks go from the most general to the specific:
    /// without a key, talking about provider and model makes no sense.
    private var liveDisabledReason: String? {
        if !hasKey { return "voice.mode.needsKey".loc }
        if provider != .openai { return "voice.mode.cloudLive.needsOpenAI".loc }
        if let model, VoiceRecognitionMode.modelsWithoutLive.contains(model) {
            return "voice.mode.cloudLive.badModel".loc(model)
        }
        return nil
    }

    // MARK: - Local model state

    @State private var showDeleteConfirm = false

    /// Download starts ONLY via the button. It used to start by itself on the first
    /// dictation and hang voice for minutes: the hotkey was blocked, and nothing showed
    /// on screen.
    @ViewBuilder
    private var modelStatusRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            switch local.state {
            // Files are on disk, the model is not loaded into memory yet — for the user that
            // is "ready": loading happens by itself on the first dictation. Without this branch
            // the app offered to download 900 MB that were already downloaded after every
            // launch.
            case .notLoaded where LocalTranscriber.isDownloadedOnDisk:
                readyRow
            case .notLoaded:
                // The button sits NEXT to the status, not at the opposite edge: there used to be a
                // `Spacer` between them, and at screen width they ended up 520pt apart.
                HStack(spacing: Theme.Space.m) {
                    Text("voice.model.notLoaded".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                    Button("voice.model.download".loc) { Task { await local.prepare() } }
                        .buttonStyle(KeylySecondaryButtonStyle())
                    Spacer(minLength: 0)
                }

            case .downloading(let progress):
                // A progress bar, not just "downloading": almost a gigabyte is downloaded, and
                // without the remainder the wait is indistinguishable from a hang.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("voice.model.downloading".loc)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                        Spacer(minLength: Theme.Space.m)
                        Text("\(Int(progress * 100)) %")
                            .font(Theme.Typography.mono(11))
                            .foregroundStyle(Theme.Colors.fgDim)
                            .monospacedDigit()
                    }
                    KeylyProgressBar(value: progress)
                }

            case .ready:
                readyRow

            case .failed:
                // The error text is NOT shown: it is technical and won't help the user.
                // The "Retry" button is the only thing they can do.
                HStack(spacing: Theme.Space.m) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.warning)
                        Text("voice.model.failed".loc)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                    }
                    Spacer(minLength: Theme.Space.m)
                    Button("voice.model.retry".loc) { Task { await local.prepare() } }
                        .buttonStyle(KeylySecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("voice.model.delete.title".loc,
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            // "Cancel" first — Enter cancels instead of wiping almost a gigabyte.
            Button("common.cancel".loc, role: .cancel) { }
            Button("common.delete".loc, role: .destructive) {
                try? FileManager.default.removeItem(at: LocalTranscriber.modelDirectory)
                LocalTranscriber.shared.forgetDownloadedModel()
                Log.info(.voice, "Файлы локальной модели удалены человеком")
            }
        } message: {
            Text("voice.model.delete.body".loc)
        }
    }

    /// "Model ready" plus HOW MUCH space it takes — measured on disk. A constant in the caption
    /// has already drifted from reality twice, and the user can check it in ten seconds in Finder.
    private var readyText: String {
        guard let bytes = LocalTranscriber.downloadedBytes() else { return "voice.model.ready".loc }
        return "voice.model.ready.size".loc(DiskSpace.format(bytes))
    }

    /// Ready model: checkmark, file path and delete. One look for two states —
    /// "loaded in memory" and "on disk": for the user they are the same.
    private var readyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.success)
            Text(readyText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgMuted)
            Spacer(minLength: 0)
            // Path to the model files: without it the user can neither verify what was
            // downloaded nor clean up almost a gigabyte if they decide to drop it.
            Button("voice.model.revealInFinder".loc) {
                NSWorkspace.shared.activateFileViewerSelecting([LocalTranscriber.modelFolderForFinder])
            }
            .buttonStyle(.borderless)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.accent)
            .help(LocalTranscriber.modelFolderForFinder.path)
            // Delete lives HERE, not in Settings: it is part of managing the local engine,
            // and nobody would look for it in another section.
            Button("voice.model.delete".loc) { showDeleteConfirm = true }
                .buttonStyle(.borderless)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgDim)
        }
    }
}

/// "Mono" progress bar. The system `ProgressView` brings its own accent and height, and
/// also does not render in QA snapshots — a deterministic frame matters more than one line of code.
struct KeylyProgressBar: View {
    /// 0…1.
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surfaceHover)
                Capsule().fill(Theme.Colors.accent)
                    .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}
