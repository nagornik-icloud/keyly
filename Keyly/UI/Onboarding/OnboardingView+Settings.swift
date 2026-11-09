import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

extension OnboardingView {

    /// Anchor that "Advanced" scrolls to when expanded.
    static let advancedAnchor = "settings.advanced.anchor"

    var settingsContent: some View {
        ScrollView {
            ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                // Unified screen header. Trailing is empty — Settings has no screen-level action;
                // that is a conscious cost: consistency matters more than density.
                KeylyScreenHeader(icon: "gearshape",
                                  title: "settings.title".loc,
                                  subtitle: "settings.subtitle".loc)
                    .keylyCard()

                // Permissions (Accessibility/microphone) are NOT duplicated here — they are on the
                // "Overview" dashboard (setupChecklist) with actions. Settings = system + keys.
                settingsSectionGeneral
                settingsSectionAPIKeys
                settingsSectionAdvanced
                    .id(Self.advancedAnchor)
                settingsSectionAbout
                menuBarHideAlert
            }
            // One column of cards + width cap: side-by-side gave cards of different
            // heights and a "black hole" next to the shorter one.
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // "Advanced" expanded — scroll to it. Without this the section expanded
            // BEYOND the window edge: at 1040×860 the user saw two fields of three and
            // was sure there were two. There is no scroll bar and no edge fade (rejected
            // as visual noise), so there is no hint of continuation at all, and content
            // must come to the user by itself.
            .onChange(of: advancedExpanded) { _, expanded in
                guard expanded else { return }
                withAnimation(KeylyMotion.standard) {
                    proxy.scrollTo(Self.advancedAnchor, anchor: .top)
                }
            }
            // Snapshot capture expands the section via the INITIAL `@State` value, not a click —
            // so the `onChange` above does not fire. Frame `screen-07b` showed the section exactly
            // where it would be WITHOUT scrolling: the first of three global combos cut off by the
            // bottom edge, the other two missing entirely. Users never see that state, yet the
            // frame was judged "screen broken" — i.e. the frame was judged as the product.
            //
            // General lesson: a QA flag that sets an END state while bypassing the transition that
            // normally accompanies it captures something that does not exist in the app.
            #if DEBUG
            .onAppear {
                guard ProcessInfo.processInfo.environment["KEYLY_QA_ADVANCED"] == "1" else { return }
                // Delayed: `onAppear` arrives before the ScrollView knows its content height,
                // and the scroll silently does nothing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    proxy.scrollTo(Self.advancedAnchor, anchor: .bottom)
                }
            }
            #endif
            }
        }
        // The app has no scroll bars. No fade at the bottom edge either: it was tried and
        // rejected as "a foreign black bar covering content" (see OnboardingView.swift). The
        // previous comment here claimed the opposite ("indicator is NOT hidden") right above
        // the line that hides it.
        //
        // "Expanded it and didn't see the section continues" is solved not by a hint but at
        // the cause: expanding scrolls the content to the expanded block by itself.
        .scrollIndicators(.hidden)
    }

    /// "All hotkeys" — the full picture of assignments with a "where configured" jump.
    ///
    /// NOT included in the screen layout: the block was removed from Settings because
    /// the same table is on Overview. That became true once the Overview cheatsheet got the
    /// "Global" section it was missing.
    ///
    /// The type is kept on purpose: it carries the `openHotKeySource` jump and the
    /// `HotKeyInventory.duplicates` check, and the inventory is the only place that counts
    /// assignment completeness. Deleting it would throw away the contract along with the view.
    var settingsSectionAllHotKeys: some View {
        let entries = HotKeyInventory.build()
        return AllHotKeysView(entries: entries,
                              duplicates: HotKeyInventory.duplicates(in: entries),
                              onOpen: { source in openHotKeySource(source) })
            .frame(maxWidth: .infinity, alignment: .leading)
            .keylyCard()
    }

    /// "Where configured" jump. This is why the inventory carries the source: a "⌥⌘L taken" row
    /// with no path to the setting forces walking through screens by hand — exactly what the
    /// "All hotkeys" screen should spare the user.
    private func openHotKeySource(_ source: HotKeyInventory.Source) {
        switch source {
        case .module(.layoutSwitch): selection = .module(.layoutSwitch)
        case .module(.errorFix):     selection = .module(.errorFix)
        case .module(.voiceToText):  selection = .module(.voiceToText)
        case .app:                   selection = .module(.appLauncher)
        case .customModule(let id):  selection = .custom(id)
        case .snippet:               selection = .snippets
        // The three global combos are configured right here — expand "Advanced", where
        // their fields REALLY live. The promise used to be empty: the section expanded,
        // but contained no hotkey fields at all.
        case .undo, .snippetPalette, .cheatsheet: advancedExpanded = true
        }
    }

    /// "Advanced" — rare and dangerous actions. Collapsed on EVERY screen opening: it holds
    /// stats reset, hotkey reset and an import that replaces everything. A remembered
    /// "expanded" state would one day expose them to an accidental click.
    var settingsSectionAdvanced: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Same custom header as on the "Voice" screen: the whole header width is clickable.
            // There was a button here before, but its hit area shrank to the content —
            // you had to hit a narrow strip of text.
            keylyDisclosureHeader(title: "settings.advanced".loc, isExpanded: $advancedExpanded)

            if advancedExpanded {
                globalHotKeysRows
                Divider().overlay(Theme.Colors.border)
                settingsSectionBackup
                Divider().overlay(Theme.Colors.border)
                hotkeyResetRow
                Divider().overlay(Theme.Colors.border)
                showWizardRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .keylyCard()
    }

    /// Combos that belong to no module: undo, palette, cheatsheet.
    ///
    /// They live exactly here because `openHotKeySource` from the "All hotkeys" row leads here:
    /// it used to expand "Advanced" and the user found nothing. The cheatsheet was added to the
    /// two promised ones: its combo (⌥⌘/) was named nowhere in the app, so there was no way to
    /// even learn the feature exists.
    private var globalHotKeysRows: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "settings.globalHotkeys".loc)
            globalHotKeyRow(title: "menu.undo".loc,
                            fieldID: HotKeyFieldID.undo,
                            kind: .undo, fallback: "⌥⌘Z",
                            data: $customHotKeyUndoData)
            globalHotKeyRow(title: "cheatsheet.palette".loc,
                            fieldID: HotKeyFieldID.snippetPalette,
                            kind: .snippetPalette, fallback: "⌥⌘S",
                            data: $customHotKeyPaletteData)
            globalHotKeyRow(title: "settings.globalHotkeys.cheatsheet".loc,
                            fieldID: HotKeyFieldID.cheatsheet,
                            kind: .cheatsheet, fallback: "⌥⌘/",
                            data: $customHotKeyCheatsheetData)
        }
    }

    private func globalHotKeyRow(title: String,
                                 fieldID: String,
                                 kind: HotKeyConflictOwner.Global,
                                 fallback: String,
                                 data: Binding<Data?>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.Colors.fg)
                // The default is named OUT LOUD: ✕ clears the combo silently, and the knowledge of
                // "what was here" was lost with it — the only way back was resetting all hotkeys.
                Text("settings.globalHotkeys.default".loc(fallback))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            Spacer(minLength: Theme.Space.m)
            KeylyHotKeyField(keyCombo: hotKeyBinding(
                fieldID: fieldID,
                get: { decodeCombo(data.wrappedValue) },
                ignoringGlobal: kind,
                assign: { combo in
                    data.wrappedValue = combo.flatMap { try? JSONEncoder().encode($0) }
                    NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
                }
            ), width: KeylyHotKeyField.Size.standalone,
               conflict: hotKeyConflictBanner(fieldID),
               fieldID: fieldID,
               onClear: {
                   data.wrappedValue = nil
                   NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
               },
               // The field sits at the right edge of the row — pin it there so the bare-key warning
               // does not drag it left (measured: it was 200pt on the launcher).
               fieldEdge: .trailing)
        }
    }

    /// Reset hotkeys to defaults. Irreversible for configured combos — hence the
    /// confirmation, where Enter cancels.
    private var hotkeyResetRow: some View {
        HStack {
            Text("settings.resetHotkeys".loc)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            Button("common.reset".loc) { showHotkeyResetConfirm = true }
                .buttonStyle(KeylySecondaryButtonStyle())
        }
        .confirmationDialog("settings.resetHotkeys.title".loc,
                            isPresented: $showHotkeyResetConfirm, titleVisibility: .visible) {
            Button("common.cancel".loc, role: .cancel) { }
            Button("common.reset".loc, role: .destructive) {
                HotKeyManager.shared.resetHotKeysToDefaults()
            }
        } message: {
            Text("settings.resetHotkeys.body".loc)
        }
    }

    /// Re-show onboarding: the wizard runs ONCE, and someone who closed it by accident
    /// would never again see the feature explanations or the "What else it can do" step.
    private var showWizardRow: some View {
        HStack {
            Text("settings.showWizard".loc)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            Button("settings.showWizard.action".loc) {
                UserDefaults.standard.set(false, forKey: SettingsKeys.wizardCompleted)
                NotificationCenter.default.post(name: .showWizardAgain, object: nil)
            }
            .buttonStyle(KeylySecondaryButtonStyle())
        }
    }

    /// Settings export and import.
    var settingsSectionBackup: some View {
        settingsCard(title: "backup.title".loc) {
            Text("backup.hint".loc)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
                Button("backup.export".loc) { exportSettings() }
                    .buttonStyle(KeylySecondaryButtonStyle())
                Button("backup.import".loc) { importSettings() }
                    .buttonStyle(KeylySecondaryButtonStyle())
                // Log export lives here too: it is also "a file going out", and a separate
                // section for one button would be noise.
                Button("backup.exportLog".loc) { exportLog() }
                    .buttonStyle(KeylySecondaryButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    /// Last 24 hours of log to a file — for bug reports. An empty result is reported too:
    /// people read silence as "the button doesn't work".
    private func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogExport.suggestedFileName(now: Date())
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let lines = try LogExport.write(to: url)
            let done = NSAlert()
            done.messageText = "backup.log.done".loc
            done.informativeText = "backup.log.done.body".loc(lines)
            done.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "backup.log.failed".loc
            alert.informativeText = "backup.log.failed.body".loc
            alert.runModal()
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "keyly-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackupService.write(SettingsBackupService.makeBundle(), to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch SettingsBackupService.read(from: url) {
        case .failure(let outcome):
            let alert = NSAlert()
            alert.messageText = "backup.import.refused".loc
            alert.informativeText = Self.refusalText(outcome)
            alert.runModal()

        case .success(let bundle):
            // Import is IRREVERSIBLE and replaces everything — confirmation is mandatory,
            // with "Cancel" first, i.e. the default.
            let alert = NSAlert()
            alert.messageText = "backup.import.confirm".loc
            alert.informativeText = "backup.import.confirm.body".loc(
                bundle.snippets.count, bundle.customModules.count, bundle.appLaunchShortcuts.count)
            alert.addButton(withTitle: "common.cancel".loc)
            alert.addButton(withTitle: "backup.import.replace".loc)
            guard alert.runModal() == .alertSecondButtonReturn else { return }

            if SettingsBackupService.apply(bundle) == .backupFailed {
                let failed = NSAlert()
                failed.messageText = "backup.import.refused".loc
                failed.informativeText = Self.refusalText(.backupFailed)
                failed.runModal()
                return
            }
            snippets = SnippetStore.load()
            customModules = CustomModuleStore.load()

            // Show the way back RIGHT AWAY: the backup is made automatically, but the user does
            // not know about it, and a minute later won't remember what exactly was replaced.
            let done = NSAlert()
            done.messageText = "backup.import.done".loc
            done.informativeText = "backup.import.done.body".loc
            done.addButton(withTitle: "common.ok".loc)
            done.addButton(withTitle: "backup.revert".loc)
            if done.runModal() == .alertSecondButtonReturn {
                SettingsBackupService.revertToAutoBackup()
                snippets = SnippetStore.load()
                customModules = CustomModuleStore.load()
            }
        }
    }

    private static func refusalText(_ outcome: SettingsBackupService.ImportOutcome) -> String {
        switch outcome {
        case .unreadable:
            return "backup.import.unreadable".loc
        case .refused(.schemaTooNew(let fileSchema, let supported)):
            return "backup.import.tooNew".loc(fileSchema, supported)
        case .refused(.schemaUnknown):
            return "backup.import.unreadable".loc
        case .backupFailed:
            return "backup.import.backupFailed".loc
        case .replaced:
            return ""
        }
    }

    var settingsSectionGeneral: some View {
        settingsCard(title: "settings.general".loc) {
            // Switches right-aligned in one vertical line (label left, Toggle right), not right
            // after the text — otherwise the right edge wanders with the label length.
            settingsSwitchRow("settings.general.launchAtLogin".loc, isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    setLaunchAtLogin(enabled: newValue)
                    launchAtLogin = newValue
                }
            ))
            settingsSwitchRow("settings.general.menuBarIcon".loc, isOn: Binding(
                get: { showMenuBarIcon },
                set: { newValue in
                    // Self-lockout: with no menu bar icon AND no Dock icon there is nothing to
                    // open the window with — the app runs, but can only be reached via Launchpad,
                    // which nobody thinks of at that moment.
                    if !newValue, !showDockIcon {
                        menuBarHideWarning = true
                        return
                    }
                    showMenuBarIcon = newValue
                    NotificationCenter.default.post(name: .uiVisibilityChanged, object: nil)
                }
            ))
            settingsSwitchRow("settings.general.dockIcon".loc, isOn: Binding(
                get: { showDockIcon },
                set: { showDockIcon = $0; NotificationCenter.default.post(name: .uiVisibilityChanged, object: nil) }
            ))
            languageRow
                .settingsRowSeparator(isLast: false)
            // Stats reset belongs in "Advanced". Until "Advanced" is built it stays here:
            // the button the dashboard hint refers to must exist — otherwise the hint
            // lies.
            statsResetRow
                .settingsRowSeparator(isLast: true)
        }
    }

    /// Self-lockout warning. Not a ban: the user may hide both icons, but must know the cost
    /// and see the way back.
    var menuBarHideAlert: some View {
        EmptyView()
            .alert("settings.hideBoth.title".loc, isPresented: $menuBarHideWarning) {
                Button("common.cancel".loc, role: .cancel) { }
                Button("settings.hideBoth.showDock".loc) {
                    showDockIcon = true
                    showMenuBarIcon = false
                    NotificationCenter.default.post(name: .uiVisibilityChanged, object: nil)
                }
                Button("settings.hideBoth.confirm".loc, role: .destructive) {
                    showMenuBarIcon = false
                    NotificationCenter.default.post(name: .uiVisibilityChanged, object: nil)
                }
            } message: {
                Text("settings.hideBoth.body".loc)
            }
    }

    private var statsResetRow: some View {
        HStack {
            Text("stats.reset".loc)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            Button("stats.reset.action".loc) { showStatsResetConfirm = true }
                .buttonStyle(KeylySecondaryButtonStyle())
                .controlSize(.small)
                .buttonStyle(KeylySecondaryButtonStyle())
        }
        // An irreversible action in the same row as everyday toggles ("Dock icon") — the cost
        // of an accidental click is out of proportion with its neighbors, hence the confirmation.
        .confirmationDialog("stats.reset.confirm.title".loc,
                            isPresented: $showStatsResetConfirm, titleVisibility: .visible) {
            // Button order sets the default: "Cancel" first and with role .cancel — Enter
            // cancels rather than deletes. Other alerts in the app currently do the
            // opposite; that is tracked separately.
            Button("common.cancel".loc, role: .cancel) { }
            Button("common.reset".loc, role: .destructive) { UsageStatsStore.shared.reset() }
        } message: {
            Text("stats.reset.confirm.body".loc)
        }
    }

    /// UI language picker. The change applies IMMEDIATELY, no restart: a utility lives for
    /// weeks, and "restart the app" in its settings is a poor answer.
    private var languageRow: some View {
        HStack {
            Text("settings.general.language".loc)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            // A custom menu instead of the native `Picker`: the system control came out light
            // and broke the app's dark look — the only white spot on the screen.
            // "System default" is a localizable string; language names are in their own language
            // (a native name, not the English one): people scan the list for a familiar word.
            Menu {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button {
                        languageManager.set(language)
                    } label: {
                        Label(language == .system ? "language.system".loc : language.nativeName,
                              systemImage: language == languageManager.language ? "checkmark" : "globe")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(languageManager.language == .system
                         ? "language.system".loc : languageManager.language.nativeName)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Colors.fg)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.fgDim)
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(height: Theme.Size.control - 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Colors.surfaceHover)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    /// Switch row. `isLast` removes the separator from the last row — otherwise the line
    /// hangs over empty space.
    ///
    /// Separators were added because "General" was the only list in the app with no row
    /// separation at all, while on "Overview" exactly the same rows use hairlines.
    /// The styling rule lives in `KeylyRow`.
    private func settingsSwitchRow(_ title: String, isOn: Binding<Bool>,
                                   isLast: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(KeylyToggleStyle())
        }
        .settingsRowSeparator(isLast: isLast)
    }

    // "About" is a quiet footer (Keyly + version + tagline), not a full card section.
    var settingsSectionAbout: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyly")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fgMuted)
                Text("about.tagline".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            Spacer(minLength: Theme.Space.m)
            Text(appVersionString())
                .font(Theme.Typography.mono(11))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        // Same horizontal axis as card content (`keylyCard` puts `Space.l` inside):
        // the version line used to sit on a THIRD axis — left of the content and
        // right of the border — and on the right overflowed the card by 29 px.
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Same SectionLabel as on other screens: this one screen used to host
            // THREE label systems — SF Pro bold card headers, mono UPPERCASE dim and
            // mono mixed-case provider names.
            SectionLabel(text: title)
            content()
        }
        // Switches, not default macOS checkboxes: without this the Toggle in "General" rendered
        // as a square checkbox and broke from the toggle style of the rest of the app.
        .toggleStyle(KeylyToggleStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .keylyCard()
    }

    func appVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "v\(version) (\(build))"
    }

    func setLaunchAtLogin(enabled: Bool) {
        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = false
            }
        }
    }
}
