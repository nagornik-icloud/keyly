import SwiftUI

extension OnboardingView {
    /// Anchor of the last cheatsheet section — snapshot capture uses it to reach the bottom of the screen.
    static let overviewBottomAnchor = "overview.bottom"

    var overviewContent: some View {
        ScrollView {
            ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                dashboardHeader
                // Stats go RIGHT under the header (they must be at the very top), before readiness
                // and the cheatsheet.
                statsBlock
                // Readiness card — ONLY when there is something to fix. When all is well it
                // duplicated the "all set" chip from the header a hundred points away, and a
                // prominent block of the main screen announced "nothing to do".
                // Readiness ABOVE the changelog. The two blocks collide exactly in the update
                // scenario: "What's new" is shown once per version, and system permissions most
                // often drop after the .app is replaced — so the person whose hotkeys went silent
                // read the changelog first. Stats stay right under the header — readiness comes third.
                if !allReady || needsMic || needsInputMonitoring { setupChecklist }
                whatsNewCard
                hotkeyCheatsheet
            }
            // Width cap — otherwise cards stretch across the whole detail pane and the
            // dashboard looks sparse ("too wide").
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, Theme.Space.xs)
            // Capturing the bottom of the screen. The window is fixed at 1040×860, the dashboard
            // is taller — and everything below the fold made it into NO capture: a newly added
            // section would have shipped unseen. Only `qa-capture.sh` sets this; in the
            // app the variable is absent and no scrolling happens.
            .onAppear {
                guard ProcessInfo.processInfo.environment["KEYLY_QA_SCROLL"] == "bottom" else { return }
                // Delayed, not immediate: `onAppear` arrives BEFORE the ScrollView knows its
                // content height, and the scroll silently did nothing — the frame was
                // indistinguishable from an unscrolled one and gave a false check.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    proxy.scrollTo(Self.overviewBottomAnchor, anchor: .bottom)
                }
            }
            }
        }
        // The scroll indicator is NOT hidden: with it hidden, a section header with a
        // counter could sit at the very edge with no rows below it — and read as an
        // empty section, although the screen simply continued below.
        .scrollIndicators(.hidden)
    }

    // MARK: - State

    private var needsAccessibility: Bool { !hasAccessibilityAccess || qaAllPermissionsMissing }
    private var needsMic: Bool { !hasMicrophoneAccess || qaAllPermissionsMissing }

    /// Captures the "NOTHING granted" state. On the developer machine all three permissions
    /// are granted, and the section with all three rows never appeared in any capture, so this
    /// combination could not be checked at all.
    private var qaAllPermissionsMissing: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KEYLY_QA_NO_PERMISSIONS"] == "1"
        #else
        return false
        #endif
    }
    private var needsKey: Bool { !apiKeyStore.hasAnyKey }
    /// Whether something already CONFIGURED is broken.
    ///
    /// The difference from "not configured" is essential and had been lost. A missing key is
    /// not a breakage: AI modules ask for it lazily, in place, and should not scare people at
    /// startup. But a key that EXISTS and returns errors is a breakage, and the screen must say
    /// so: for someone whose setup has worked for months, what breaks is exactly the configured part.
    private var brokenKeys: [APIKeyEntry] {
        // Only REAL key failures. Being offline is not the key's fault, and raising a
        // "key not responding" row because of it would be lying in the other direction.
        apiKeyStore.keys.filter {
            if case .failure(let why) = validationStatus[$0.id] ?? .unknown {
                return why != .offline
            }
            return false
        }
    }

    /// Dead event tap: permission granted, but keystrokes do not arrive.
    private var tapIsDead: Bool { HotKeyManager.shared.tapIsUnhealthy }

    /// "All set" — only when NOTHING needs attention.
    ///
    /// This used to be `!needsAccessibility` — one condition of four. The chip printed
    /// "all set" next to a broken key and a missing model, i.e. lied in the most visible spot
    /// of the screen. It should be the opposite: in the normal state there is NO card, and
    /// resolved items disappear rather than turn green.
    private var allReady: Bool {
        !needsAccessibility && !needsInputMonitoring && brokenKeys.isEmpty
            && !tapIsDead && !voiceModeCannotStart
    }

    /// "Input Monitoring" is the third permission, and it used to be in no check at all.
    /// Without it the event tap gets no keys: hotkeys and snippet triggers are silent, while
    /// "Readiness" reported "all set" because it only knew about two permissions.
    private var needsInputMonitoring: Bool {
        // Read @State, not the system API directly: otherwise the row won't disappear after granting.
        #if DEBUG
        // The "permission not granted" state does not reproduce on the developer machine —
        // it is granted, and no capture would show the row. An unchecked row is no better
        // than a missing one: the conflict banner once shipped without ever being seen.
        let env = ProcessInfo.processInfo.environment
        if env["KEYLY_QA_NO_INPUT_MONITORING"] == "1" || env["KEYLY_QA_NO_PERMISSIONS"] == "1" {
            return true
        }
        #endif
        return !hasInputMonitoring
    }

    /// The selected recognition method cannot start.
    ///
    /// The comment above promised to account for a missing model, but the condition did not.
    /// On a fresh install the default mode is "On this Mac", the model is not there yet, and
    /// Overview printed "all set" exactly where the core feature does not work: the user pressed
    /// the hotkey and got a failure a minute after the promise.
    private var voiceModeCannotStart: Bool {
        guard isModuleEnabled(.voiceToText) else { return false }
        let mode = VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? ""
        ) ?? .default
        switch mode {
        case .onDevice:
            // Readiness is based on FILES on disk, not on "is the model loaded in memory":
            // memory is empty after every launch, and "Voice can't start" was lit for
            // someone with a long-downloaded model until they began dictating.
            return !LocalTranscriber.shared.isUsable
        case .cloudBatch, .cloudLive:
            return !moduleHasKey(.voiceToText)
        }
    }

    // MARK: - Header

    var dashboardHeader: some View {
        HStack(spacing: Theme.Space.m) {
            // One accent, and only for action, not decoration. The filled tile shouted
            // louder than the product title; in "Mono" it is a quiet surface with a hairline.
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.borderStrong, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "command")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Colors.fg)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyly")
                    .font(Theme.Typography.display(20))
                    .foregroundStyle(Theme.Colors.fg)
                Text("overview.tagline".loc)
                    .font(Theme.Typography.mono(11))
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            Spacer()
            statusPill
        }
        .keylyCard()
    }

    private var statusPill: some View {
        let ok = allReady
        return HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(ok ? "overview.ready".loc : "overview.needsSetup".loc)
                .font(Theme.Typography.mono(10, .semibold))
        }
        // A quiet chip of the same shape in both states; the STATE is carried by the glyph color,
        // not the fill — otherwise "all set" would be louder than the product name.
        .foregroundStyle(ok ? Theme.Colors.success : Theme.Colors.warning)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.Colors.surfaceHover)
                .overlay(Capsule().stroke(Theme.Colors.border, lineWidth: 1))
        )
    }

    // MARK: - Readiness

    /// "What's new" after an update. Shown ONCE per version and dismissed with a click:
    /// a card that comes back after every launch is an ad you cannot get rid of.
    @ViewBuilder
    var whatsNewCard: some View {
        if showWhatsNew {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("whatsNew.title".loc(appVersionString()))
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Colors.fg)
                    Spacer(minLength: Theme.Space.m)
                    Button {
                        dismissWhatsNew()
                    } label: {
                        Image(systemName: "xmark")
                            .iconHitArea("whatsNew.dismiss".loc)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.Colors.fgDim)
                }
                Text("whatsNew.body".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .keylyCard()
        }
    }

    func dismissWhatsNew() {
        seenVersion = WhatsNew.versionToRemember(currentVersion: appVersionString())
        showWhatsNew = false
    }

    var setupChecklist: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "overview.checklist".loc)
            if needsInputMonitoring {
                checklistRow(icon: "keyboard.badge.ellipsis",
                             title: "overview.check.inputMonitoring".loc,
                             hint: "overview.check.inputMonitoring.hint".loc,
                             ok: false, action: "common.open".loc) {
                    InputMonitoringPermission.openSettings()
                    InputMonitoringPermission.request()
                }
            }
            if needsAccessibility || needsMic {
                checklistRow(icon: "lock.shield", title: "overview.check.ax".loc,
                             hint: "overview.check.ax.hint".loc,
                             ok: !needsAccessibility, action: "common.open".loc) {
                    AccessibilityPermission.openAccessibilitySettings()
                    _ = AccessibilityPermission.ensurePermission(prompt: true)
                }
                checklistRow(icon: "mic", title: "overview.check.mic".loc,
                             hint: "overview.check.mic.hint".loc,
                             ok: !needsMic, action: "common.open".loc) {
                    MicrophonePermission.ensurePermission(prompt: true) { granted in
                        hasMicrophoneAccess = granted
                    }
                }
            }
            // The API key is intentionally NOT in "Readiness" while it is simply MISSING — only
            // AI modules need it, and they ask lazily on their screens. The core (layout/snippets/launcher)
            // works without a key, and it should not scare people at startup.
            //
            // But a BROKEN key is different: it is configured, the user relies on it, and
            // staying silent about it no longer working leaves them guessing why the module
            // stopped responding.
            ForEach(brokenKeys, id: \.id) { key in
                checklistRow(icon: "key.slash", title: "overview.check.brokenKey".loc(key.name),
                             hint: "overview.check.brokenKey.hint".loc,
                             ok: false, action: "common.open".loc) {
                    selection = .settings
                }
            }
            if voiceModeCannotStart {
                checklistRow(icon: "mic.slash", title: "overview.check.voiceMode".loc,
                             hint: "overview.check.voiceMode.hint".loc,
                             ok: false, action: "common.open".loc) {
                    selection = .module(.voiceToText)
                }
            }
            if tapIsDead {
                checklistRow(icon: "exclamationmark.triangle", title: "overview.check.deadTap".loc,
                             hint: "overview.check.deadTap.hint".loc,
                             ok: false, action: "common.open".loc) {
                    AccessibilityPermission.openAccessibilitySettings()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // "Readiness" card spans the full width, like the others
        .keylyCard()
    }

    private func checklistRow(icon: String, title: String, hint: String,
                              ok: Bool, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.m) {
            // The readiness checkmark is neutral (NOT brand lime): lime stays rare, reserved for
            // the hero "all set" pill, the logo, actions and selection.
            Image(systemName: ok ? "checkmark.circle.fill" : icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ok ? Theme.Colors.fg : Theme.Colors.warning)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fg)
                Text(hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            Spacer()
            if ok {
                Text("overview.done".loc)
                    .font(Theme.Typography.mono(10, .semibold))
                    .foregroundStyle(Theme.Colors.fgMuted)
            } else {
                Button(action, action: perform)
                    .buttonStyle(KeylySecondaryButtonStyle())
            }
        }
    }

    // MARK: - Hotkey cheatsheet

    var hotkeyCheatsheet: some View {
        // Three sections with counters instead of one flat list: built-in modules get a
        // quick toggle in place, custom ones do NOT, because their screen has no master
        // switch — a toggle here would promise a switch that does not exist.
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            builtInSection
            customSection
            if !appLaunchShortcuts.isEmpty { appsSection }
            // Snippets with combos are hotkeys too. Without this section their combos were not
            // visible on the dashboard at all: someone who forgot an assignment went looking
            // for it on the fourth screen.
            if !snippetsWithHotKey.isEmpty { snippetsSection }
            // Three combos that belong to no module. Without this section NOT A SINGLE word in
            // the app led to them: "Snippets" does not mention the palette, they were not
            // here, and "Settings" does not contain the word "combo" at all — the field could
            // only be found by trial. This also makes true the justification for removing the
            // "All hotkeys" block from Settings: "the same table is on Overview".
            globalSection
                .id(Self.overviewBottomAnchor)
        }
        .keylyCard()
    }

    private var builtInSection: some View {
        let all = ModuleKind.allCases
        let on = all.filter { isModuleEnabled($0) }.count
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("overview.section.modules".loc, "\(on) / \(all.count)")
            ForEach(Array(all.enumerated()), id: \.element) { index, module in
                moduleRow(module, isLast: index == all.count - 1)
            }
        }
    }

    /// Undo, snippet palette and cheatsheet. The rows LEAD to "Settings → Advanced", where these
    /// combos are changed: a list with no path to the setting would force walking through
    /// screens by hand — exactly what the cheatsheet should spare the user.
    private var globalSection: some View {
        let rows: [(HotKeyConflictOwner.Global, String, String, KeyCombo?)] = [
            (.undo, "menu.undo", "arrow.uturn.backward", decodeCombo(customHotKeyUndoData)),
            (.snippetPalette, "cheatsheet.palette", "square.grid.2x2",
             decodeCombo(customHotKeyPaletteData)),
            (.cheatsheet, "settings.globalHotkeys.cheatsheet", "questionmark.circle",
             decodeCombo(customHotKeyCheatsheetData)),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("overview.section.global".loc, "\(rows.filter { $0.3 != nil }.count)")
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                cheatRow(.settings, row.1.loc, row.2, row.3?.description,
                         isLast: index == rows.count - 1,
                         alsoDo: { advancedExpanded = true })
            }
        }
    }

    private var customSection: some View {
        // Collapsing a long section: the dashboard answers "what do I have configured",
        // and a list of twenty modules turns it into a wall of text in which the
        // dashboard itself gets lost. "+ Add module" is EXCLUDED from collapsing —
        // otherwise the second creation point would vanish exactly when there are many modules.
        let visible = expandedOverviewSections.contains("custom")
            ? customModules
            : Array(customModules.prefix(Self.overviewSectionLimit))
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("overview.section.custom".loc, "\(customModules.count)")
            ForEach(visible) { module in
                cheatRow(.custom(module.id), module.name, "sparkles", module.hotKey?.description)
            }
            showAllRow(key: "custom", total: customModules.count)
            // Second module creation point — the first is in the sidebar.
            // Same path as in the sidebar: create the module and open it right away.
            Button {
                let created = addCustomModule()
                selection = .custom(created.id)
            } label: {
                KeylyRow(showsSeparator: false) {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.fg)
                            .frame(width: 20)
                        Text("overview.addModule".loc)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Colors.fg)
                    }
                } trailing: { EmptyView() }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    /// Snippets that HAVE a combo. The rest are irrelevant to the hotkey dashboard:
    /// they fire on a typed trigger, and a row without a combo would read as
    /// "the hotkey got lost".
    private var snippetsWithHotKey: [Snippet] {
        snippets.filter { $0.hotKey != nil }
    }

    private var snippetsSection: some View {
        let all = snippetsWithHotKey
        let visible = expandedOverviewSections.contains("snippets")
            ? all
            : Array(all.prefix(Self.overviewSectionLimit))
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("overview.section.snippets".loc, "\(all.count)")
            ForEach(Array(visible.enumerated()), id: \.offset) { index, snippet in
                cheatRow(.snippets, snippet.displayTitle.loc, "text.badge.plus",
                         snippet.hotKey?.description,
                         isLast: index == visible.count - 1)
            }
            showAllRow(key: "snippets", total: all.count)
        }
    }

    private var appsSection: some View {
        let visible = expandedOverviewSections.contains("apps")
            ? appLaunchShortcuts
            : Array(appLaunchShortcuts.prefix(Self.overviewSectionLimit))
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("overview.section.apps".loc, "\(appLaunchShortcuts.count)")
            ForEach(Array(visible.enumerated()), id: \.offset) { index, shortcut in
                cheatRow(.module(.appLauncher), shortcut.displayName, "app.badge",
                         shortcut.keyCombo?.description,
                         isLast: index == visible.count - 1)
            }
            showAllRow(key: "apps", total: appLaunchShortcuts.count)
        }
    }

    /// Collapse threshold for a dashboard section.
    static let overviewSectionLimit = 6

    /// "Show all (N)" / "Collapse" row. Appears only when there is something to hide:
    /// a button above a three-row list is noise, not control.
    @ViewBuilder
    private func showAllRow(key: String, total: Int) -> some View {
        if total > Self.overviewSectionLimit {
            let expanded = expandedOverviewSections.contains(key)
            Button {
                withAnimation(KeylyMotion.emphasis) {
                    if expanded { expandedOverviewSections.remove(key) }
                    else { expandedOverviewSections.insert(key) }
                }
            } label: {
                KeylyRow(showsSeparator: false) {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.fgMuted)
                            .frame(width: 20)
                        Text(expanded ? "overview.collapse".loc
                                      : "overview.showAll".loc(total))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                    }
                } trailing: { EmptyView() }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    /// Section label + counter on the right: shows at a glance "how many and how many enabled".
    private func sectionHead(_ title: String, _ counter: String) -> some View {
        HStack {
            SectionLabel(text: title)
            Spacer(minLength: Theme.Space.m)
            Text(counter)
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        // Same horizontal padding as inside `KeylyRow`. Without it the section counter
        // sat at 1998 while all trailing controls of the rows sat at 1969: the number
        // column stuck out to the right, and the right edge read as a staircase.
        .padding(.horizontal, 14)
        .padding(.bottom, Theme.Space.s)
    }

    /// Built-in module row: hotkey + quick toggle.
    private func moduleRow(_ module: ModuleKind, isLast: Bool) -> some View {
        KeylyRow(trailingWidth: 196, showsSeparator: !isLast) {
            Button { selection = .module(module) } label: {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: module.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .frame(width: 20)
                    Text(module.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.fg)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        } trailing: {
            HStack(spacing: Theme.Space.m) {
                // Keycap ONLY for a real combo. The launcher has no single hotkey
                // (each app has its own), and a number in a keycap read as the key "4".
                if module == .appLauncher {
                    Text(appLaunchShortcuts.isEmpty
                         ? "overview.noHotkey".loc
                         : "overview.appsCount".loc(appLaunchShortcuts.count))
                        .font(Theme.Typography.mono(10))
                        .foregroundStyle(Theme.Colors.fgDim)
                } else if let combo = hotkeyDescription(for: module) {
                    // The chip dims together with a disabled module: the hotkey is already
                    // unregistered, and showing it at full brightness would promise a combo
                    // that won't work.
                    HotkeyChip(text: combo)
                        .opacity(isModuleEnabled(module) ? 1 : 0.35)
                        .help(isModuleEnabled(module) ? "" : "overview.chip.moduleOff".loc)
                } else {
                    Text("overview.noHotkey".loc)
                        .font(Theme.Typography.mono(10))
                        .foregroundStyle(Theme.Colors.fgDim)
                }
                Toggle("", isOn: moduleEnabledBinding(module))
                    .toggleStyle(KeylyToggleStyle())
                    .labelsHidden()
                // Chevron on ALL rows that lead to a screen, and it sits in the
                // TRAILING position, not in the left block.
                //
                // It used to be glued to the title — and floated with its length: measured
                // 777pt for "Layout" and 897pt for "App launcher", i.e. a 120pt spread
                // within ONE section. In neighboring sections the same chevron is pinned at
                // 1969. The same "open" arrow lived in two grammars, and someone used to
                // clicking on the right could not find it in this section.
                // The chevron IS CLICKABLE. In the trailing position it lies outside the row
                // button, and one screen had 16 identical arrows, 12 of which open a screen
                // while the top 4 were dead: in the sections below the whole row lies inside
                // the button. Someone clicking the first four concludes that modules don't
                // open.
                Button { selection = .module(module) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.fgDim)
                }
                .buttonStyle(.plain)
                .iconHitArea("overview.open".loc)
            }
        }
    }

    private func hotkeyDescription(for module: ModuleKind) -> String? {
        switch module {
        case .layoutSwitch: return customHotKey?.description
        case .errorFix:     return customHotKeyErrorFix?.description
        case .voiceToText:  return customHotKeyVoice?.description
        case .appLauncher:  return appLaunchShortcuts.isEmpty ? nil : "\(appLaunchShortcuts.count)"
        }
    }

    private func cheatRow(_ item: NavItem, _ title: String, _ icon: String, _ hotkey: String?, isCount: Bool = false, isLast: Bool = false, alsoDo: (() -> Void)? = nil) -> some View {
        Button {
            selection = item
            // Global combos live in a collapsed Settings section — one navigation step
            // is not enough, it also has to be expanded, otherwise the row leads to a
            // screen where the target is not visible.
            alsoDo?()
        } label: {
            // Unified list row: height 44 and a hairline separator. The height used to be
            // set by the TRAILING content — the row with the "4 apps" counter was ~4pt shorter than the keycap row.
            KeylyRow(showsSeparator: !isLast) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .frame(width: 20)
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.fg)
                }
            } trailing: {
                HStack(spacing: Theme.Space.s) {
                    if let hotkey {
                        if isCount {
                            // The counter (e.g. "4 apps") is quiet text, NOT a keycap (otherwise it reads as a key).
                            Text(hotkey)
                                .font(Theme.Typography.mono(10))
                                .foregroundStyle(Theme.Colors.fgDim)
                        } else {
                            HotkeyChip(text: hotkey)
                        }
                    } else {
                        Text("overview.chip.unset".loc)
                            .font(Theme.Typography.mono(10))
                            .foregroundStyle(Theme.Colors.fgDim)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.fgDim)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Stats

    /// A QUIET row of four numbers, no tiles and no period switch.
    ///
    /// This reconciles two earlier conflicting requirements: the block stays high on the
    /// screen but stops being its loudest element. There is intentionally no switch — it
    /// produced pairs like "880 dictated / 0 fixed", which read as someone else's data.
    ///
    /// Captions name EVENTS, not items: "layout switches", not "layouts". The old
    /// "layouts" and "snippets" lied twice — wrong grammatical case and a swapped unit
    /// (the sidebar next to it says "Snippets 1", and "0 snippets" read as data loss).
    var statsBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
            // Captions are pluralized by number: "1 fix", "2 fixes", "5 fixes" (Russian
            // has three forms). An uninflected "992 words" reads as machine-assembled text
            // and undermines trust in the numbers themselves.
            ForEach(UsageMetric.allCases, id: \.self) { metric in
                statItem(metric)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xs)
    }

    /// Number and caption on ONE line, small mono. A tile with a 25pt number made stats the
    /// main thing seen on opening the window — while that should be the hotkey cheatsheet and open setup items.
    private func statItem(_ metric: UsageMetric) -> some View {
        let value = statsStore.value(metric, period: .allTime)
        let label = metric.label(for: value, language: languageManager.effective)
        return HStack(spacing: 5) {
            Text(formatted(value))
                .font(Theme.Typography.mono(11, .semibold))
                .foregroundStyle(Theme.Colors.fgMuted)
            Text(label)
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        .fixedSize()
    }

    /// Thousands are separated by a thin space: "3 480" reads at a glance, "3480" does not.
    private func formatted(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{2009}"
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

}
