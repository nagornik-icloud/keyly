import SwiftUI
import AppKit

extension OnboardingView {
    @ViewBuilder
    func moduleDetail(_ module: ModuleKind) -> some View {
        // A disabled module DIMS entirely and becomes non-clickable, except for the
        // master toggle in the header — otherwise it could never be turned back on. Settings
        // of a disabled module used to stay active and clickable although the hotkey was
        // already unregistered: the user fiddled with controls that affected nothing.
        let enabled = isModuleEnabled(module)
        return ScrollView {
            ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                moduleHeader(module)
                Group {
                switch module {
                case .layoutSwitch:
                    moduleCardLayout(hotkeySection: hotKeySection, tips: tips(for: .layoutSwitch)) {
                        ModuleTryOutSection(kind: .layout, isReady: true)
                        Divider().overlay(Theme.Colors.border)
                        Divider().overlay(Theme.Colors.border)
                        layoutPairSection
                    }
                case .errorFix:
                    moduleCardLayout(hotkeySection: errorFixHotKeySection, tips: tips(for: .errorFix)) {
                        Divider().overlay(Theme.Colors.border)
                        ModuleTryOutSection(kind: .errorFix,
                                            isReady: moduleHasKey(.errorFix),
                                            notReadyReason: "module.tryOut.needsKey".loc)
                    }
                case .voiceToText:
                    // The try-out lives INSIDE `voiceHotKeySection` — right after the text processing
                    // block. Via `extra` it would land at the very bottom of the card, below the fold.
                    moduleCardLayout(hotkeySection: voiceHotKeySection, tips: tips(for: .voiceToText))
                case .appLauncher:
                    moduleCardLayout(hotkeySection: appLaunchersSection, tips: tips(for: .appLauncher))
                }
                }
                .opacity(enabled ? 1 : 0.4)
                .disabled(!enabled)
                .overlay(alignment: .top) {
                    if !enabled {
                        // A reason caption is mandatory: a silent disabled state is not allowed.
                        Text("module.disabled.hint".loc)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                            .padding(.top, Theme.Space.s)
                    }
                }
                // Bottom anchor — same trick as on the dashboard. The voice screen is taller than
                // the window, and everything below the fold (try-out, collapsed "Microphone, overlay,
                // language", tips) made it into NO capture: the first attempt added a `voice-bottom`
                // frame, but it silently returned the same top — an unscrolled frame is
                // indistinguishable from a scrolled one and gives a false check.
                .id(Self.moduleBottomAnchor)
            }
            .onAppear {
                guard ProcessInfo.processInfo.environment["KEYLY_QA_SCROLL"] == "bottom" else { return }
                // Delayed: `onAppear` arrives BEFORE the ScrollView knows its content height,
                // and the scroll silently does nothing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    proxy.scrollTo(Self.moduleBottomAnchor, anchor: .bottom)
                }
            }
            }
        }
    }

    /// Bottom anchor of the module card — snapshot capture uses it to reach the end of the screen.
    static let moduleBottomAnchor = "module.bottom"

    @ViewBuilder
    func customModuleDetail(id: UUID) -> some View {
        if let binding = bindingForModule(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    customModuleCard(module: binding)
                }
            }
        } else {
            Text("module.notFound".loc)
                .foregroundStyle(.secondary)
        }
    }

    /// Module screen header — the same `KeylyScreenHeader` as Settings and Snippets.
    ///
    /// There used to be a SEPARATE copy of the same layout here, and it had already drifted:
    /// the icon lost the border the shared one has. One concept with two implementations
    /// always diverges — the only question is who notices first.
    func moduleHeader(_ module: ModuleKind) -> some View {
        KeylyScreenHeader(icon: module.icon, title: module.title, subtitle: module.subtitle) {
            VStack(alignment: .trailing, spacing: 5) {
                Toggle("", isOn: moduleEnabledBinding(module))
                    .toggleStyle(KeylyToggleStyle())
                    .labelsHidden()
                    // Test identifier comes from the module TYPE, not from its label.
                    .accessibilityIdentifier("keyly.module.\(module.axKey).enabled")
                    .accessibilityLabel(module.title)
                // Pill ONLY when there is a problem (hotkey/key needed). On/off is already shown by the
                // switch; duplicating "active/off" with a pill is noise and tautology.
                if let warning = moduleWarningText(module) {
                    Text(warning)
                        .font(Theme.Typography.mono(9, .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Colors.warning.opacity(0.15)))
                        .foregroundStyle(Theme.Colors.warning)
                        .fixedSize()
                }
            }
        }
        .keylyCard()
    }

    /// Whether the module needs a key RIGHT NOW — based on the selected mode, not the module type.
    ///
    /// This used to be an unconditional `module == .errorFix || module == .voiceToText`, and in
    /// on-device mode the app contradicted itself: the "Voice" screen dimmed the picker saying
    /// "the local model does not need a key", while the sidebar at the same moment showed a
    /// "needs setup" dot. The user added a key, the dot went out — and voice stayed silent for
    /// another reason (model not downloaded).
    func moduleNeedsKey(_ module: ModuleKind) -> Bool {
        switch module {
        case .errorFix:
            return true
        case .voiceToText:
            let mode = VoiceRecognitionMode(
                rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? ""
            ) ?? .default
            return mode.needsAPIKey
        default:
            return false
        }
    }

    func moduleHasKey(_ module: ModuleKind) -> Bool {
        let context: APIKeyContext = module == .voiceToText ? .voiceToText : .errorFix
        return apiKeyStore.entry(for: apiKeyStore.currentSelection(for: context)) != nil
    }

    /// Warning pill in the header — only when the module is ON but won't work
    /// (no hotkey / no key for an AI module). No pill for on/off — the switch says that.
    private func moduleWarningText(_ module: ModuleKind) -> String? {
        guard isModuleEnabled(module) else { return nil }
        if !moduleHasHotkey(module) { return "module.needs.hotkey".loc }
        // On-device mode without a downloaded model is the same "on but won't work"
        // as a missing key, and it used to be the only case without a pill. "Overview"
        // honestly said "Voice can't start", the user clicked "Open" — and landed on a
        // screen with a silent header and a toggle that looked on.
        if module == .voiceToText, voiceNeedsLocalModel { return "module.needs.model".loc }
        if moduleNeedsKey(module) && !moduleHasKey(module) { return "module.needs.key".loc }
        return nil
    }

    /// On-device mode is selected but the model is missing. Voice needs no key in this mode, so
    /// the key check below does not cover it — a separate branch is required.
    var voiceNeedsLocalModel: Bool {
        let mode = VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? "")
        return mode == .onDevice && !LocalTranscriber.shared.isUsable
    }

    /// The try-out needs exactly what real dictation needs: the model in on-device mode, a key
    /// in cloud modes. A button on a non-ready module would deceive twice: it would make a
    /// doomed attempt and blame the failure on the microphone.
    var voiceTryOutReady: Bool {
        voiceNeedsLocalModel ? false : (voiceUsesCloud ? moduleHasKey(.voiceToText) : true)
    }

    /// The reason depends on the model STATE, not one text for all cases. A single "download
    /// the model — button above" was shown during download too (there is no button then, only
    /// a progress bar) and after a failure (the button is called "Retry") — so the try-out
    /// advised pressing something that wasn't there. One level up the same class is already
    /// handled by branching on state (`localDisabledReason`); here it was forgotten.
    var voiceTryOutReason: String {
        guard voiceUsesCloud == false else { return "module.tryOut.needsKey".loc }
        if LocalTranscriber.isDownloadedOnDisk { return "" }
        switch LocalTranscriber.shared.state {
        case .ready:       return ""
        case .notLoaded:   return "module.tryOut.voice.needsModel".loc
        case .downloading: return "voice.mode.onDevice.downloading".loc
        case .failed:      return "voice.mode.onDevice.failed".loc
        }
    }

    var voiceUsesCloud: Bool {
        VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? "") != .onDevice
    }

    /// Shared module card skeleton. Blocks specific to ONE module do not go here: all four
    /// modules use this function, and a layout pair added here once surfaced on the voice,
    /// typo and app launcher screens where it does not belong.
    func moduleCardLayout(hotkeySection: some View, tips: [String],
                          @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            hotkeySection
            extra()
            Divider().overlay(Theme.Colors.border)
            tipsSection(tips: tips)
        }
        .keylyCard()
    }

    /// RU↔EN layout pair. The pair is stored EXPLICITLY because the old "next in cycle"
    /// switching with three or more installed layouts sent the system to a foreign source:
    /// the text was converted, but the layout ended up wrong.
    @ViewBuilder
    var layoutPairSection: some View {
        let layouts = KeyboardLayoutService.availableLayouts()
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "layout.pair".loc)
            if layouts.count < 2 {
                // One layout — nothing to switch, and a picker would only confuse.
                Text("layout.pair.needTwo".loc)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fgMuted)
            } else {
                layoutPairRow(title: "layout.pair.latin".loc, layouts: layouts, isLatinSide: true)
                layoutPairRow(title: "layout.pair.cyrillic".loc, layouts: layouts, isLatinSide: false)
            }
        }
    }

    private func layoutPairRow(title: String, layouts: [(id: String, name: String)], isLatinSide: Bool) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            Picker("", selection: Binding(
                get: {
                    let pair = KeyboardLayoutService.pair
                    return (isLatinSide ? pair?.enSourceID : pair?.ruSourceID) ?? ""
                },
                set: { newID in
                    guard let current = KeyboardLayoutService.pair else { return }
                    // Picked the same layout as the other side → SWAP THE SIDES instead of silently
                    // ignoring: the user clearly wants this layout here, and a pair of two identical
                    // sides is impossible (there would be nothing to switch to).
                    let updated: KeyboardLayoutPair? = isLatinSide
                        ? (newID == current.ruSourceID
                            ? KeyboardLayoutPair(enSourceID: newID, ruSourceID: current.enSourceID)
                            : KeyboardLayoutPair(enSourceID: newID, ruSourceID: current.ruSourceID))
                        : (newID == current.enSourceID
                            ? KeyboardLayoutPair(enSourceID: current.ruSourceID, ruSourceID: newID)
                            : KeyboardLayoutPair(enSourceID: current.enSourceID, ruSourceID: newID))
                    if let updated { KeyboardLayoutService.pair = updated }
                }
            )) {
                ForEach(layouts, id: \.id) { layout in
                    Text(layout.name).tag(layout.id)
                }
            }
            .labelsHidden()
            .fixedSize()   // see the language picker: fixed width breaks the right vertical alignment
        }
    }

    /// "How it works" — collapsed by default (doesn't bother experienced users; readiness status
    /// is on Overview). Numbering is calm monochrome, no accent fill (the accent stays rare).
    func tipsSection(tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // The WHOLE header row is clickable (not just the arrow).
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { tipsExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .rotationEffect(.degrees(tipsExpanded ? 90 : 0))
                    SectionLabel(text: "module.howItWorks".loc)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if tipsExpanded {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { idx, tip in
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Text("\(idx + 1)")
                                .font(Theme.Typography.mono(11, .semibold))
                                .foregroundStyle(Theme.Colors.fgDim)
                                .frame(width: 20, height: 20)
                                .background(Theme.Colors.surfaceHover, in: Circle())
                            Text(tip)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Whether the module has a hotkey set (for appLauncher — at least one).
    func moduleHasHotkey(_ module: ModuleKind) -> Bool {
        switch module {
        case .layoutSwitch: return customHotKeyData != nil
        case .errorFix: return customHotKeyErrorFixData != nil
        case .voiceToText: return customHotKeyVoiceData != nil
        case .appLauncher: return !appLaunchShortcuts.isEmpty
        }
    }

    func isModuleEnabled(_ module: ModuleKind) -> Bool {
        switch module {
        case .layoutSwitch: return layoutModuleEnabled
        case .errorFix:     return errorFixModuleEnabled
        case .voiceToText:  return voiceModuleEnabled
        case .appLauncher:  return appLauncherModuleEnabled
        }
    }

    /// Master switch binding: writes the flag (@AppStorage → reactive UI) and asks
    /// HotKeyManager to re-register hotkeys.
    func moduleEnabledBinding(_ module: ModuleKind) -> Binding<Bool> {
        let base: Binding<Bool>
        switch module {
        case .layoutSwitch: base = $layoutModuleEnabled
        case .errorFix:     base = $errorFixModuleEnabled
        case .voiceToText:  base = $voiceModuleEnabled
        case .appLauncher:  base = $appLauncherModuleEnabled
        }
        return Binding(
            get: { base.wrappedValue },
            set: { newValue in
                base.wrappedValue = newValue
                NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
            }
        )
    }

    /// "Active" = enabled by the master switch AND has a hotkey.
    func isModuleActive(_ module: ModuleKind) -> Bool {
        isModuleEnabled(module) && moduleHasHotkey(module)
    }

    /// Sidebar dot state. The rule lives in the pure `ModuleAttention` and is covered by
    /// tests: two different states used to merge into one dot with one caption.
    func moduleAttention(_ module: ModuleKind) -> ModuleAttention {
        ModuleAttention.resolve(isEnabled: isModuleEnabled(module),
                                hasHotKey: moduleHasHotkey(module),
                                needsKey: moduleNeedsKey(module),
                                hasKey: moduleHasKey(module))
    }

    func permissionCard(icon: String, title: String, message: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.Typography.title(17))
                .foregroundStyle(Theme.Colors.fg)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.fgMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)
            Button("common.allow".loc, action: action)
                .buttonStyle(KeylyPrimaryButtonStyle())
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 460)
        .background(Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .stroke(Theme.Colors.border, lineWidth: 1)
        )
    }

    func reportSizeIfNeeded(_ size: CGSize) {
        guard size != lastReportedSize else { return }
        lastReportedSize = size
        onSizeChange?(size)
    }
}
