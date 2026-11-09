import SwiftUI
import AppKit

extension OnboardingView {
    func customModuleCard(module: Binding<CustomAIModule>) -> some View {
        let moduleId = module.wrappedValue.id
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            // Header uses the same template as built-in modules: icon + title + status + delete.
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.fg)
                    .frame(width: 38, height: 38)
                    .background(Theme.Colors.surfaceHover,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                TextField("modules.custom.namePlaceholder".loc, text: module.name)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.title(17))
                    .foregroundStyle(Theme.Colors.fg)
                Spacer(minLength: Theme.Space.m)
                // Custom modules have no master switch — so NOT "active/off" (that would promise
                // a switch that does not exist), but an honest warning ONLY when it cannot run:
                // no hotkey. Hotkey set → no pill (it is visible in the "Module hotkey" field below).
                if module.wrappedValue.hotKey == nil {
                    Text("modules.custom.needsHotkey".loc)
                        .font(Theme.Typography.mono(9, .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Colors.warning.opacity(0.15)))
                        .foregroundStyle(Theme.Colors.warning)
                        .fixedSize()
                }
                // Master toggle — in THE SAME SLOT as on the four built-in modules. It used
                // to be missing: there was no way to disable a custom module, and someone
                // wanting to free the combo deleted their configured prompt.
                Toggle("", isOn: Binding(
                    get: { module.wrappedValue.isEnabled },
                    set: { module.wrappedValue.isEnabled = $0; persistCustomModules() }
                ))
                .toggleStyle(KeylyToggleStyle())
                .labelsHidden()
                .help(module.wrappedValue.isEnabled
                      ? "modules.custom.toggleOn".loc
                      : "modules.custom.toggleOff".loc)

                // Delete lives in the "…" menu, NOT as a red trash in the header. On four neighboring
                // screens this slot holds the master toggle: muscle memory led straight to
                // "delete", and the red trash was the brightest element on the screen.
                Menu {
                    Button("module.delete".loc, systemImage: "trash", role: .destructive) {
                        confirmDeleteCustomModule(id: moduleId, name: module.wrappedValue.name)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .iconHitArea("common.more".loc)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .keylyCard()

            // Body mirrors moduleCardLayout of built-ins: settings + instruction in one card.
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hotkeyRow(label: "modules.custom.hotkey".loc,
                          fieldID: HotKeyFieldID.customModule(moduleId),
                          keyCombo: hotKeyBinding(
                    fieldID: HotKeyFieldID.customModule(moduleId),
                    get: { module.wrappedValue.hotKey },
                    ignoringCustomModuleId: moduleId,
                    assign: { combo in
                        module.wrappedValue.hotKey = combo
                        persistCustomModules()
                    }
                ))
                apiKeyPicker(context: .customModule(moduleId), title: "keys.picker.title".loc)

                Divider().overlay(Theme.Colors.border)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel(text: "modules.custom.prompt".loc)
                    Text("modules.custom.promptHint".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                    TextEditor(text: module.prompt)
                        .font(Theme.Typography.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                        .padding(Theme.Space.s)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .fill(Theme.Colors.surfaceHover)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .stroke(Theme.Colors.border, lineWidth: 1)
                        )
                }

                Divider().overlay(Theme.Colors.border)

                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionLabel(text: "modules.custom.source".loc)
                        // Custom segment instead of the stock one: the stock one draws segments off
                        // palette and LIGHTER than the card, and selected differed from unselected by
                        // only +28 brightness — from a distance it is unclear what is selected.
                        KeylySegmented(selection: module.textSource, options: [
                            (.selected, "module.source.selected".loc),
                            (.wholeWindow, "module.source.window".loc),
                            (.clipboard, "module.source.clipboard".loc),
                        ])
                        Text(sourceHint(module.wrappedValue.textSource))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .top, spacing: Theme.Space.xl) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel(text: "modules.custom.result".loc)
                            // One choice (not two toggles): "nowhere" is impossible, no extra decision.
                            // Three outcomes in one choice. It used to be two toggles — four
                            // combinations, two of them meaningless, and the user could set any of
                            // them.
                            KeylySegmented(selection: module.output, options: [
                                (CustomOutput.insert, "module.result.insert".loc),
                                (CustomOutput.copy, "module.result.copy".loc),
                                (CustomOutput.panel, "module.result.panel".loc),
                            ])
                            Text(outputHint(module.wrappedValue.output))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider().overlay(Theme.Colors.border)

                // Prompt try-out right here: the user writes the prompt, and before this the
                // only way to test it was on real text in another app — a bad prompt ruined
                // whatever was there.
                ModuleTryOutSection(
                    kind: .custom(module.wrappedValue),
                    isReady: APIKeyStore.shared.entry(
                        for: APIKeyStore.shared.currentSelection(for: .customModule(moduleId))) != nil,
                    notReadyReason: "module.tryOut.needsKey".loc
                )
            }
            .font(Theme.Typography.body)
            .toggleStyle(KeylyToggleStyle())
            .keylyCard()
        }
        .onChange(of: module.wrappedValue) {
            persistCustomModules()
        }
    }

    /// What happens to the result — in words, under the choice itself.
    func outputHint(_ output: CustomOutput) -> String {
        switch output {
        case .insert: return "modules.custom.result.paste".loc
        case .copy:   return "modules.custom.result.clipboard".loc
        case .panel:  return "modules.custom.result.panel".loc
        }
    }

    /// Hint under the "Text source" segment — changes with the selection.
    func sourceHint(_ s: CustomTextSource) -> String {
        switch s {
        case .selected:    return "modules.custom.source.selected".loc
        case .wholeWindow: return "modules.custom.source.window".loc
        case .clipboard:   return "modules.custom.source.clipboard".loc
        }
    }

    @discardableResult
    func addCustomModule() -> CustomAIModule {
        let module = CustomAIModule(name: "modules.custom.new.name".loc, prompt: "modules.custom.new.prompt".loc)
        customModules.append(module)
        persistCustomModules()
        return module
    }

    func confirmDeleteCustomModule(id: UUID, name: String) {
        let alert = NSAlert()
        alert.messageText = "modules.custom.delete.title".loc
        alert.informativeText = "modules.custom.delete.body".loc(name)
        // "Cancel" FIRST — it becomes the default button, so Enter cancels rather than
        // deletes. Previously in all three alerts of the app Enter meant "Delete": a habit
        // of clicking through dialogs would cost the user a configured snippet, module
        // or key.
        alert.addButton(withTitle: "common.cancel".loc)
        alert.addButton(withTitle: "common.delete".loc)
        if alert.runModal() == .alertSecondButtonReturn {
            customModules.removeAll { $0.id == id }
            persistCustomModules()
        }
    }

    func persistCustomModules() {
        CustomModuleStore.save(customModules)
    }

    func bindingForModule(id: UUID) -> Binding<CustomAIModule>? {
        guard let index = customModules.firstIndex(where: { $0.id == id }) else { return nil }
        return $customModules[index]
    }
}
