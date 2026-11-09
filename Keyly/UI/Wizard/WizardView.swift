import Combine
import SwiftUI
import ServiceManagement

/// First-launch wizard. Order and transition rules live in `WizardFlow`
/// (pure logic, covered by tests); this file only has the screens.
struct WizardView: View {

    let onFinish: () -> Void

    @AppStorage(SettingsKeys.launchAtLogin) private var launchAtLogin = false
    @State private var step: WizardStep = .hello
    @State private var accessibilityGranted = AccessibilityPermission.isTrusted
    /// The permission is shown as granted, but the event tap fails to start.
    @State private var needsRestart = false
    @State private var microphoneGranted = MicrophonePermission.isAuthorized
    /// For the QA catalog only: permissions on the developer machine are already granted, and the
    /// "not granted" step, the one a new user sees, cannot be reproduced otherwise.
    ///
    /// `WizardStepPreview` itself is a plain enum available in any configuration;
    /// only its RENDERER lives under `#if DEBUG`. While the enum was DEBUG-only, the Release
    /// build did not compile at all ("cannot find type 'WizardStepPreview' in scope"), and nobody
    /// noticed because only Debug was ever built. Found on the first Release build.
    private var previewState: WizardStepPreview?
    @State private var trialText = ""

    /// The build has no local recognition model yet (the engine is still being chosen),
    /// so the step is hidden: a "download the model" screen with no way to download would lie.
    private let localModelAvailable = false

    private var steps: [WizardStep] { WizardFlow.steps(localModelAvailable: localModelAvailable) }

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        self.previewState = nil
    }

    init(onFinish: @escaping () -> Void, previewState: WizardStepPreview) {
        self.onFinish = onFinish
        self.previewState = previewState
        switch previewState {
        case .hello:              _step = State(initialValue: .hello)
        case .permissionsDenied:  _step = State(initialValue: .permissions)
                                  _accessibilityGranted = State(initialValue: false)
                                  _microphoneGranted = State(initialValue: false)
        case .permissionsGranted: _step = State(initialValue: .permissions)
                                  _accessibilityGranted = State(initialValue: true)
                                  _microphoneGranted = State(initialValue: true)
        case .hotkeys:            _step = State(initialValue: .hotkeys)
        case .done:               _step = State(initialValue: .done)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader
            Divider().overlay(Theme.Colors.border)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Theme.Space.xl)
            Divider().overlay(Theme.Colors.border)
            footer
        }
        .background(Theme.Colors.bg)
        .environment(\.colorScheme, .dark)
        // Permissions are granted in SYSTEM Settings, outside the app; the only way to notice is
        // polling. Without it the user grants access, comes back, and Next is still disabled.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // No polling in previews: it would overwrite the preset permission state.
            guard previewState == nil else { return }
            accessibilityGranted = AccessibilityPermission.isTrusted
            // Checked on the same tick as the permission itself: the "granted but not
            // working" state appears exactly when a previously denied permission is granted.
            needsRestart = previewState == nil && PermissionStaleness.accessibilityNeedsRestart()
            microphoneGranted = MicrophonePermission.isAuthorized
        }
    }

    // MARK: - Scaffold

    private var progressHeader: some View {
        let position = WizardFlow.position(of: step, in: steps)
        return HStack(spacing: Theme.Space.m) {
            Text("wizard.step".loc(position.index, position.total))
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
            // A step bar instead of "N of M": shows both how much is done and how much is left.
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index < position.index ? Theme.Colors.accent : Theme.Colors.border)
                        .frame(height: 3)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            if WizardFlow.previous(before: step, in: steps) != nil {
                Button("wizard.back".loc) { goBack() }
                    .buttonStyle(KeylySecondaryButtonStyle())
            }
            // "Skip" on every step except permissions. Without it, someone who has no time
            // for setup right now closes the window, and the wizard, shown ONCE,
            // never appears again: they never see the features from step 6.
            if step != .permissions, step != .more {
                // A custom style, not the stock `.borderless`: this was the ONLY button
                // in the product on the AppKit system style; live it is painted system blue
                // and falls out of the monochrome "Mono", and `ImageRenderer` does not capture it at all
                // (wizard screenshots showed a yellow placeholder in its place, so the button was
                // never actually seen in QA).
                Button("wizard.skip".loc) { goForward(force: true) }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .contentShape(Rectangle())
                    .keylyHoverHighlight()
            }
            Spacer(minLength: Theme.Space.m)
            if step == .more {
                Button("wizard.finish".loc) { onFinish() }
                    .buttonStyle(KeylyPrimaryButtonStyle())
            } else {
                Button("wizard.next".loc) { goForward() }
                    .buttonStyle(KeylyPrimaryButtonStyle())
                    .disabled(!canAdvance)
            }
        }
        .padding(Theme.Space.xl)
    }

    private var canAdvance: Bool {
        WizardFlow.canAdvance(from: step,
                              accessibilityGranted: accessibilityGranted,
                              microphoneGranted: microphoneGranted)
    }

    /// `force` is "Skip": the step is not done, but you may leave it.
    /// On the permissions step `force` is not offered at all; there `canAdvance` is the law.
    private func goForward(force: Bool = false) {
        guard force || canAdvance, let next = WizardFlow.next(after: step, in: steps) else { return }
        withAnimation(.easeOut(duration: 0.18)) { step = next }
    }

    private func goBack() {
        guard let previous = WizardFlow.previous(before: step, in: steps) else { return }
        withAnimation(.easeOut(duration: 0.18)) { step = previous }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hello:       helloStep
        case .permissions: permissionsStep
        case .model:       EmptyView()   // step hidden until there is a recognition engine
        case .hotkeys:     hotkeysStep
        case .done:        doneStep
        case .more:        moreStep
        }
    }

    private var helloStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stepTitle("wizard.hello.title".loc, "wizard.hello.subtitle".loc)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                featureRow("keyboard", "wizard.hello.layout".loc)
                featureRow("wand.and.stars", "wizard.hello.errorFix".loc)
                featureRow("mic", "wizard.hello.voice".loc)
                featureRow("text.badge.plus", "wizard.hello.snippets".loc)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stepTitle("wizard.permissions.title".loc, "wizard.permissions.subtitle".loc)
            permissionRow(granted: accessibilityGranted,
                          title: "wizard.permissions.accessibility".loc,
                          why: "wizard.permissions.accessibility.why".loc) {
                _ = AccessibilityPermission.ensurePermission(prompt: true)
                AccessibilityPermission.openAccessibilitySettings()
            }
            permissionRow(granted: microphoneGranted,
                          title: "wizard.permissions.microphone".loc,
                          why: "wizard.permissions.microphone.why".loc) {
                _ = MicrophonePermission.ensurePermission(prompt: true)
                MicrophonePermission.openMicrophoneSettings()
            }
            // Permission is granted but the event tap does not start: macOS does not pick up
            // Accessibility on the fly if the permission was PREVIOUSLY denied. Without this line
            // the step unlocked, and the user went into a product where not a single hotkey
            // works, with a checkmark in System Settings and no explanation at all.
            if needsRestart {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.warning)
                    Text("wizard.permissions.needsRestart".loc)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.m)
                    Button("wizard.permissions.restart".loc) {
                        PermissionStaleness.relaunch()
                    }
                    .buttonStyle(KeylyPrimaryButtonStyle())
                }
                .padding(Theme.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Colors.warning.opacity(0.12))
                )
            }

            if !canAdvance {
                // Explain WHY the button is unavailable: a disabled button with no reason
                // reads as broken.
                Text("wizard.permissions.blocked".loc)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
    }

    private var hotkeysStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stepTitle("wizard.hotkeys.title".loc, "wizard.hotkeys.subtitle".loc)
            // Combinations can be changed right here: the recorder is the same as in module
            // settings, so behavior and conflicts are already handled in one place.
            WizardHotkeyRows(snapshot: previewState != nil)
        }
    }

    /// "What else it can do" step. Without it, snippets, custom modules, the launcher and undo
    /// are not discovered at all: in the sidebar they look like settings sections, and someone
    /// who finished the wizard does not know the product can do anything beyond three hotkeys.
    private var moreStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stepTitle("wizard.more.title".loc, "wizard.more.subtitle".loc)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m),
                                GridItem(.flexible(), spacing: Theme.Space.m)],
                      spacing: Theme.Space.m) {
                moreCard("text.badge.plus", "wizard.more.snippets".loc, "wizard.more.snippets.hint".loc)
                moreCard("sparkles", "wizard.more.modules".loc, "wizard.more.modules.hint".loc)
                moreCard("square.on.square", "wizard.more.launcher".loc, "wizard.more.launcher.hint".loc)
                moreCard("arrow.uturn.backward", "wizard.more.undo".loc, "wizard.more.undo.hint".loc)
            }

            // Launch at login is offered HERE. Keyly is a background utility: if it does not
            // start with the system, it simply does not exist, and the user decides it is
            // broken. We ask on the last step, when it is already clear why it is needed.
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("wizard.more.launchAtLogin".loc)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Colors.fg)
                    Text("wizard.more.launchAtLogin.hint".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                }
            }
            .toggleStyle(KeylyToggleStyle())
            .onChange(of: launchAtLogin) { _, newValue in
                setLaunchAtLoginFromWizard(enabled: newValue)
            }
        }
    }

    /// Registers with the system. On error, log it and revert the toggle: promising a launch at login
    /// that will not happen is worse than not promising.
    private func setLaunchAtLoginFromWizard(enabled: Bool) {
        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.warn(.app, "Визард: не удалось изменить автозапуск — \(error.localizedDescription)")
                launchAtLogin = false
            }
        }
    }

    private func moreCard(_ icon: String, _ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fg)
            Text(hint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1))
        )
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stepTitle("wizard.done.title".loc, "wizard.done.subtitle".loc)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("wizard.done.tryIt".loc)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fgMuted)
                // Test field: layout switching always works, without a model, key or network,
                // so it is the one used to check that everything is alive.
                // In a snapshot, Text instead of TextField: ImageRenderer does not capture a live field.
                Group {
                    if previewState != nil {
                        Text("wizard.done.placeholder".loc)
                            .foregroundStyle(Theme.Colors.fgDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                    .fill(Theme.Colors.surfaceHover)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                        .stroke(Theme.Colors.border, lineWidth: 1))
                            )
                    } else {
                        TextField("wizard.done.placeholder".loc, text: $trialText)
                            .textFieldStyle(KeylyTextFieldStyle())
                    }
                }
                .font(Theme.Typography.body)
                .frame(maxWidth: 320)
            }
        }
    }

    // MARK: - Small blocks

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typography.title(20))
                .foregroundStyle(Theme.Colors.fg)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.fgMuted)
                .frame(width: 20)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(granted: Bool, title: String, why: String,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(granted ? Theme.Colors.success : Theme.Colors.fgDim)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fg)
                Text(why)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.m)
            if !granted {
                // The button is CENTERED in the card, not at its top.
                //
                // `HStack(alignment: .top)` is needed for the checkmark and the title: they must sit
                // on one line. But it pinned the button there too, while the explanation under
                // the title takes two lines: measured 24px of air above and 62px
                // below, so the card looked lopsided, with an empty rectangle
                // hanging under the button. The alignment is overridden locally rather than changing
                // the alignment of the whole row.
                Button("wizard.permissions.open".loc, action: action)
                    .buttonStyle(KeylySecondaryButtonStyle())
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }
}
