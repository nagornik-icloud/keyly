import SwiftUI
import AppKit

extension OnboardingView {
    var customHotKey: KeyCombo? {
        guard let data = customHotKeyData,
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return nil }
        return combo
    }

    var customHotKeyErrorFix: KeyCombo? {
        guard let data = customHotKeyErrorFixData,
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return nil }
        return combo
    }

    var customHotKeyVoice: KeyCombo? {
        guard let data = customHotKeyVoiceData,
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return nil }
        return combo
    }

    /// Shared background for the hotkey recorder field (each module used to have its own border color).
    var hotkeyRecorderBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .fill(Theme.Colors.surfaceHover)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            )
    }

    /// HORIZONTAL hotkey row.
    ///
    /// The hotkey stopped being a third column to the right of key and model and became its own
    /// full-width row. Why this shape:
    /// - the "Layout" screen has neither key nor model — the row stands alone there, while
    ///   the column left 570–620pt of dead space on the right;
    /// - there is room for the conflict banner (up to 360pt) by construction: it lays out under
    ///   the row and moves nothing;
    /// - the order matches: the combo is how the module is launched, and it comes FIRST, as on
    ///   "Layout". Previously the order differed between screens.
    func hotkeyRow(label: String, fieldID: String, keyCombo: Binding<KeyCombo?>) -> some View {
        // The bare-key warning lives INSIDE the field (KeylyHotKeyField): attached to the
        // wrapper, it reached only three screens out of six.
        KeylyHotKeyField(keyCombo: keyCombo,
                         conflict: hotKeyConflictBanner(fieldID),
                         fieldID: fieldID,
                         onClear: { keyCombo.wrappedValue = nil },
                         rowLabel: label)
    }

    var hotKeySection: some View {
        hotkeyRow(label: "hotkey.label".loc, fieldID: HotKeyFieldID.layout, keyCombo: hotKeyBinding(
            fieldID: HotKeyFieldID.layout,
            get: { customHotKey },
            module: .layoutSwitch,
            assign: { combo in
                customHotKeyData = combo.flatMap { try? JSONEncoder().encode($0) }
                NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
            }
        ))
    }

    var errorFixHotKeySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            errorFixKeyRow
            Divider().overlay(Theme.Colors.border)
            // Its OWN ladder, not the voice one. A key shared with voice caused two problems
            // at once: the typo module never read it, and switching on this screen silently
            // changed voice behavior.
            ErrorFixLevelSection(hasKey: APIKeyStore.shared.entry(for: APIKeyStore.shared.currentSelection(for: .errorFix)) != nil)
        }
    }

    private var errorFixKeyRow: some View {
        // Combo FIRST, key and model below. Ordered by frequency: the hotkey is pressed
        // daily, the key is chosen once. It also matches "Layout", which has no key at
        // all — previously the hotkey sat in different places on different screens.
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            hotkeyRow(label: "hotkey.label".loc, fieldID: HotKeyFieldID.errorFix, keyCombo: hotKeyBinding(
                fieldID: HotKeyFieldID.errorFix,
                get: { customHotKeyErrorFix },
                module: .errorFix,
                assign: { combo in
                    customHotKeyErrorFixData = combo.flatMap { try? JSONEncoder().encode($0) }
                    NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
                }
            ))
            apiKeyPicker(context: .errorFix, title: "keys.picker.title".loc)
        }
    }

    func voiceToggle(_ title: String, _ desc: String?, _ binding: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // Label on the left, switch pinned to the right edge (Spacer) — one toggle column as
            // in Settings/Custom; the built-in Toggle label pushed the switch to the end of the text (jagged).
            HStack {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fg)
                Spacer(minLength: Theme.Space.m)
                Toggle("", isOn: binding)
                    .toggleStyle(KeylyToggleStyle())
                    .labelsHidden()
            }
            if let desc {
                Text(desc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var voiceHotKeySection: some View {
        // Recognition mode is the screen's CONTROLLING choice, so it comes FIRST.
        // The key used to be on top: going top-down the user dutifully chose it, while the decision
        // was made one row below, and in on-device mode the top control affected nothing.
        // A dependent setting cannot come before what it depends on.
        let mode = VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? ""
        ) ?? .default
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            // Combo FIRST — as on all other module screens. While it sat after the
            // recognition blocks, its position also FLOATED with the mode: second with the
            // on-device model, fourth in the cloud (the model block lives under `if`) —
            // even though the hotkey does not depend on the mode at all.
            hotkeyRow(label: "hotkey.label".loc, fieldID: HotKeyFieldID.voice, keyCombo: hotKeyBinding(
                fieldID: HotKeyFieldID.voice,
                get: { customHotKeyVoice },
                module: .voiceToText,
                assign: { combo in
                    customHotKeyVoiceData = combo.flatMap { try? JSONEncoder().encode($0) }
                    NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
                }
            ))
            Divider().overlay(Theme.Colors.border)
            voiceRecognitionBlock
            Divider().overlay(Theme.Colors.border)
            // Transcription model is its own choice. In cloud batch mode all three are
            // available; in streaming mode whisper-1 drops out — it only returns the final
            // segment, not deltas while speaking.
            if mode != .onDevice {
                transcriptionModelBlock(live: mode == .cloudLive)
                Divider().overlay(Theme.Colors.border)
            }
            // The key is active in ALL modes. It used to be dimmed on the on-device model
            // as "not needed" — which was false: the local model transcribes, but transcript
            // processing still runs in the cloud, so without a key the user silently lost
            // the "Polish" and "Rewrite" levels.
            apiKeyPicker(context: .voiceToText, title: "keys.picker.title".loc)
            Divider().overlay(Theme.Colors.border)
            // hasKey is passed EXPLICITLY. Without it the default `true` kicked in, and the
            // "Polish"/"Rewrite" levels looked available without a key — while at runtime
            // `TextPolisher` quietly logged "level requires a key, none present" and returned raw
            // text. The typo screen called the same block with the real value, so the hole was
            // exactly here.
            // Transcript processing is active in all modes: it runs in the cloud regardless of
            // who transcribed. With the on-device model only the REASON the upper levels need
            // a key changes, and in "while speaking" mode a warning is added: live text is
            // rewritten after stopping.
            TextPolishSection(
                hasKey: APIKeyStore.shared.entry(
                    for: APIKeyStore.shared.currentSelection(for: .voiceToText)) != nil,
                needsKeyReason: mode == .onDevice ? "polish.needsKey.local".loc
                                                  : "polish.needsKey".loc,
                // The cloud warning used to reach ONLY users without a key: the line served as
                // the reason a level was unavailable and disappeared once a key was added.
                // So exactly the people whose text really goes to the cloud were told nothing
                // about it anywhere ("are any requests made to OpenAI? why is that not written
                // anywhere?").
                //
                // ONE line per block, present in every mode. The first version of the fix also
                // appended "separate AI request" to each level description — three quiet repeats
                // instead of one visible place, and each level grew to two lines, pushing the
                // bottom of the screen below the fold.
                footnote: polishFootnote(for: mode))
            Divider().overlay(Theme.Colors.border)

            // The try-out comes BEFORE the collapsed rare settings, not after. Initially
            // it landed at the end of the card — below the window fold, under a section
            // people open once in a lifetime. The try-out is needed right after setup,
            // otherwise exactly the person it exists for (just set up, wants to confirm) won't find it.
            VoiceTryOutSection(isReady: voiceTryOutReady, notReadyReason: voiceTryOutReason)
            Divider().overlay(Theme.Colors.border)

            // Rare settings are collapsed. The screen grew with every change and started
            // cutting off mid-word in the default window: the app has no scroll bars, and
            // a clipped caption reads as a broken screen, not as "scroll down".
            // What stays on top is what people touch — method, model, key, hotkey and
            // text processing; microphone, overlay placement and dictation language are
            // set once.
            // NOT `DisclosureGroup`: only its ~10pt system triangle is clickable, not the
            // whole row with the caption. People click the words "Microphone, overlay,
            // language" and get nothing; and the triangle sits right against the text. Same
            // custom disclosure header as in "Settings → Advanced" — one pattern for the
            // app, not two.
            keylyDisclosureHeader(title: "voice.advanced".loc, isExpanded: $showVoiceAdvanced)

            if showVoiceAdvanced {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VoiceInputDeviceSection(isSelectable: mode == .cloudLive)
                    Divider().overlay(Theme.Colors.border)
                    voiceIndicatorBlock
                    Divider().overlay(Theme.Colors.border)
                    voiceAfterDictationBlock
                    Divider().overlay(Theme.Colors.border)
                    // Dictation language does NOT apply to the on-device model: Parakeet
                    // detects the language itself and has no language parameter at all.
                    voiceLanguageBlock
                        .keylyInapplicable(when: mode == .onDevice,
                                           reason: "voice.language.localAuto".loc)
                }
                .padding(.top, Theme.Space.m)
            }
        }
    }

    /// What to say under the processing block. Each mode has its own line, but "a separate
    /// AI request using the selected key" is in every one: processing costs money in all three,
    /// and that is exactly what users could not find out anywhere. `TextPolishSection` shows it
    /// only on levels that make a request — on "As spoken" it would describe work that does not happen.
    private func polishFootnote(for mode: VoiceRecognitionMode) -> String {
        switch mode {
        // On-device is the only mode where going to the cloud contradicts expectations,
        // so here the line says so directly.
        case .onDevice:   return "polish.cloudAlways".loc
        // "While speaking" additionally warns that already-shown text will be rewritten.
        case .cloudLive:  return "polish.afterStop".loc
        case .cloudBatch: return "polish.extraRequest".loc
        }
    }

    /// The recognition method is aware of the selected key: whether live typing is available
    /// depends on provider and model. This dependency used to be invisible — a saved
    /// `whisper-1` silently switched the app into another mode.
    private var voiceRecognitionBlock: some View {
        let store = APIKeyStore.shared
        let selection = store.currentSelection(for: .voiceToText)
        return VoiceRecognitionSection(
            provider: selection.provider,
            model: store.model(for: .voiceToText),
            hasKey: store.entry(for: selection) != nil
        )
    }

    /// Transcription model choice. Separate from the text processing model: they are different
    /// models, and a shared picker had already led to transcripts being sent as a chat request.
    private func transcriptionModelBlock(live: Bool) -> some View {
        let options = live ? TranscriptionModelCatalog.liveCapableOpenAIIDs
                           : TranscriptionModelCatalog.openAIIDs
        let current = TranscriptionModelCatalog.selectedOpenAI
        // The catalog here is ENTIRELY OpenAI: `TranscriptionService` reads `selectedOpenAI`
        // only in the OpenAI branch, while on Gemini the transcription model comes from the key row.
        // So with a Gemini key this block showed `gpt-4o-transcribe ≈ $0.006/min` —
        // someone else's model and price, and switching it affected nothing.
        let providerIsOpenAI = APIKeyStore.shared.currentSelection(for: .voiceToText).provider == .openai
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel(text: "voice.recognitionModel".loc)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        UserDefaults.standard.set(option, forKey: SettingsKeys.voiceTranscriptionModel)
                    } label: {
                        // Price per MINUTE of audio — in the menu too, not only for the selected one.
                        Label(ModelPricing.perMinute(for: option).map { "\(option)   ≈ \($0)" } ?? option,
                              systemImage: option == current ? "checkmark" : "waveform")
                    }
                }
            } label: {
                pickerField(text: options.contains(current) ? current : options.first ?? current,
                            // Per MINUTE, not per call: transcription is billed by audio length.
                            subtitle: ModelPricing.perMinute(
                                for: options.contains(current) ? current : options.first ?? current)
                                .map { "pricing.perMinute".loc($0) },
                            isPlaceholder: false)
            }
            .buttonStyle(.plain)
            .frame(minWidth: Theme.Size.picker, maxWidth: .infinity)
            .keylyInapplicable(when: !providerIsOpenAI,
                               reason: "voice.recognitionModel.geminiNote".loc)
            if live, providerIsOpenAI {
                Text("voice.recognitionModel.liveNote".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceIndicatorBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "voice.indicator".loc)
            KeylyOptionGroup(
                selection: Binding(
                    get: { VoiceIndicatorPlacement(rawValue: voiceIndicatorPlacement) ?? .default },
                    set: { voiceIndicatorPlacement = $0.rawValue }
                ),
                options: [
                    KeylyOption(value: .topCenter,
                                title: VoiceIndicatorPlacement.topCenter.titleKey.loc,
                                subtitle: "voice.indicator.topCenter.hint".loc),
                    KeylyOption(value: .bottomCenter,
                                title: VoiceIndicatorPlacement.bottomCenter.titleKey.loc,
                                subtitle: "voice.indicator.bottomCenter.hint".loc),
                    KeylyOption(value: .topTrailing,
                                title: VoiceIndicatorPlacement.topTrailing.titleKey.loc,
                                subtitle: "voice.indicator.topTrailing.hint".loc),
                ]
            )
            voiceToggle("voice.indicator.timer".loc, nil, $voiceIndicatorShowTimer)
        }
    }

    /// What happens to the text once it is pasted — its own group, not a plate setting.
    private var voiceAfterDictationBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "voice.afterDictation".loc)
            voiceToggle("voice.keepInClipboard".loc, "voice.keepInClipboard.hint".loc, $voiceKeepInClipboard)
        }
    }

    private var voiceLanguageBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "voice.language".loc)
            KeylySegmented(
                selection: Binding(
                    get: { VoiceLanguage(rawValue: voiceLanguage) ?? .default },
                    set: { voiceLanguage = $0.rawValue }
                ),
                options: [
                    (.auto, "voice.language.auto".loc),
                    (.ru, "voice.language.ru".loc),
                    (.en, "voice.language.en".loc),
                ]
            )
        }
    }

    func tips(for module: ModuleKind) -> [String] {
        switch module {
        case .layoutSwitch:
            return [
                "layout.tip.press".loc,
                "layout.tip.scope".loc,
                "layout.tip.field".loc
            ]
        case .errorFix:
            // Text updated: the hotkey NO longer selects the whole field unconditionally —
            // it respects the selection. The old wording described behavior that is gone,
            // and instructions that contradict reality are worse than none.
            return [
                "errorfix.tip.scope".loc,
                "errorfix.tip.network".loc,
                "errorfix.tip.undo".loc
            ]
        case .voiceToText:
            // Exactly THREE lines. A fourth ("audio in a temporary file") answered a
            // question the user is not asking at that moment and crowded out the main
            // thing — what to do by hand.
            return [
                "voice.tip.press".loc,
                "voice.tip.insert".loc,
                "voice.tip.local".loc
            ]
        case .appLauncher:
            return [
                "launcher.tip.add".loc,
                "launcher.tip.fkeys".loc,
                "launcher.tip.path".loc
            ]
        }
    }

    func conflictOwner(for combo: KeyCombo, ignoringAppID: UUID?, module: ModuleKind?, ignoringCustomModuleId: UUID? = nil, ignoringSnippetId: UUID? = nil, ignoringGlobal: HotKeyConflictOwner.Global? = nil) -> HotKeyConflictOwner? {
        func same(_ lhs: KeyCombo?, _ rhs: KeyCombo?) -> Bool {
            guard let l = lhs, let r = rhs else { return false }
            return l == r
        }

        // System combos are rejected FIRST: grabbing ⌘Q or ⌘Tab breaks working with the
        // system as a whole, and the user won't connect it to Keyly — it breaks everywhere.
        if SystemHotKeys.isReserved(combo) {
            return .system
        }

        if module != .layoutSwitch && same(combo, customHotKey) {
            return .module(.layoutSwitch)
        }
        if module != .errorFix && same(combo, customHotKeyErrorFix) {
            return .module(.errorFix)
        }
        if module != .voiceToText && same(combo, customHotKeyVoice) {
            return .module(.voiceToText)
        }

        // The three global combos are full-fledged holders: they used to be missing here,
        // and anyone could take ⌥⌘S away from the palette without a word.
        let globals: [(HotKeyConflictOwner.Global, KeyCombo?)] = [
            (.undo, decodeCombo(customHotKeyUndoData)),
            (.snippetPalette, decodeCombo(customHotKeyPaletteData)),
            (.cheatsheet, decodeCombo(customHotKeyCheatsheetData)),
        ]
        for (kind, assigned) in globals {
            if ignoringGlobal == kind { continue }
            if same(combo, assigned) { return .global(kind) }
        }

        for app in appLaunchShortcuts {
            if let ignore = ignoringAppID, ignore == app.id { continue }
            if same(combo, app.keyCombo) {
                return .app(id: app.id, name: app.displayName)
            }
        }

        for mod in customModules {
            if let ignore = ignoringCustomModuleId, ignore == mod.id { continue }
            if same(combo, mod.hotKey) {
                return .customModule(id: mod.id, name: mod.name)
            }
        }

        for snippet in snippets {
            if let ignore = ignoringSnippetId, ignore == snippet.id { continue }
            if same(combo, snippet.hotKey) {
                return .snippet(id: snippet.id, title: snippet.displayTitle.loc)
            }
        }

        return nil
    }

    // MARK: - Assignment conflict

    /// Builds the hotkey field binding: checks for a conflict BEFORE writing and, if the combo
    /// is taken, writes nothing and raises an inline conflict UNDER THIS field.
    ///
    /// Each of the six assignment places used to repeat this check by hand and show an alert
    /// its own way. Identical code in six copies diverges: some places checked the conflict
    /// only for a non-empty combo, others always.
    func hotKeyBinding(fieldID: String,
                       get: @escaping () -> KeyCombo?,
                       ignoringAppID: UUID? = nil,
                       module: ModuleKind? = nil,
                       ignoringCustomModuleId: UUID? = nil,
                       ignoringSnippetId: UUID? = nil,
                       ignoringGlobal: HotKeyConflictOwner.Global? = nil,
                       assign: @escaping (KeyCombo?) -> Void) -> Binding<KeyCombo?> {
        Binding(
            get: get,
            set: { combo in
                if let combo,
                   let owner = conflictOwner(for: combo,
                                            ignoringAppID: ignoringAppID,
                                            module: module,
                                            ignoringCustomModuleId: ignoringCustomModuleId,
                                            ignoringSnippetId: ignoringSnippetId,
                                            ignoringGlobal: ignoringGlobal) {
                    hotKeyConflict = HotKeyConflict(fieldID: fieldID, owner: owner) {
                        releaseHotKeyOwner(owner)
                        assign(combo)
                        hotKeyConflict = nil
                    }
                    return
                }
                hotKeyConflict = nil
                assign(combo)
            }
        )
    }

    /// What to show under a given field. There is only ever one conflict: the user assigns
    /// one combo at a time, and a second banner would mean the first was forgotten.
    func hotKeyConflictBanner(_ fieldID: String) -> KeylyHotKeyField.Conflict? {
        guard let conflict = hotKeyConflict, conflict.fieldID == fieldID else { return nil }
        let message = conflict.owner.argument.map { conflict.owner.messageKey.loc($0) }
            ?? conflict.owner.messageKey.loc
        return KeylyHotKeyField.Conflict(
            message: message,
            onReassign: conflict.owner.isReleasable ? conflict.apply : nil,
            onDismiss: { hotKeyConflict = nil }
        )
    }

    /// Removes the combo from its previous holder. Without this "Reassign" would create a
    /// second instance of the same combo, and whichever registered first would fire.
    func releaseHotKeyOwner(_ owner: HotKeyConflictOwner) {
        switch owner {
        case .system:
            break
        case .module(.layoutSwitch):
            customHotKeyData = nil
            NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
        case .module(.errorFix):
            customHotKeyErrorFixData = nil
            NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
        case .module(.voiceToText):
            customHotKeyVoiceData = nil
            NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
        case .app(let id, _):
            guard let index = appLaunchShortcuts.firstIndex(where: { $0.id == id }) else { return }
            appLaunchShortcuts[index].keyCombo = nil
            persistAppLaunchShortcuts()
        case .customModule(let id, _):
            guard let index = customModules.firstIndex(where: { $0.id == id }) else { return }
            customModules[index].hotKey = nil
            persistCustomModules()
        case .snippet(let id, _):
            guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
            snippets[index].hotKey = nil
            persistSnippets()
        case .global(let kind):
            switch kind {
            case .undo:           customHotKeyUndoData = nil
            case .snippetPalette: customHotKeyPaletteData = nil
            case .cheatsheet:     customHotKeyCheatsheetData = nil
            }
            NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
        }
    }

    /// Decodes a saved combo. One home for all three global fields: three copies of
    /// `flatMap { try? JSONDecoder()... }` would diverge on the first format change.
    func decodeCombo(_ data: Data?) -> KeyCombo? {
        data.flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
    }
}
