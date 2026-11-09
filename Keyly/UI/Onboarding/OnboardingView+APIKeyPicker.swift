import SwiftUI
import AppKit

extension OnboardingView {
    /// Whether the "while speaking" mode is selected. Read here instead of passed as a
    /// parameter: the picker is used on four screens, and the extra argument would be noise everywhere.
    private var voiceModeIsLive: Bool {
        (VoiceRecognitionMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? "")
         ?? .default).isLive
    }

    private var voiceModeIsOnDevice: Bool {
        VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? ""
        ) == .onDevice
    }

    func apiKeyPicker(context: APIKeyContext, title: String) -> some View {
        let selection = apiKeyStore.currentSelection(for: context)
        let current = apiKeyStore.entry(for: selection)
        let subtitle = selection.provider.title
        let model = apiKeyStore.model(for: context)
        let availableModels = modelOptions(for: selection.provider, context: context, current: model)
        // The voice key is applicable along TWO axes, but was dimmed along only one. The matrix:
        // the on-device model transcribes by itself, and "As spoken" processing never calls the
        // model — so the key is used by NOTHING, yet the pricing block stayed live and read as
        // "the app is spending money right now". This is the default configuration, so every
        // new user saw the phantom.
        //
        // Dim ONLY when a key is already added: without a key the picker must stay live,
        // otherwise it is a dead loop — the "Polish" levels ask to add a key on this screen,
        // and the only place to do it is dimmed.
        let keyUnused = context == .voiceToText && voiceModeIsOnDevice
                        && !TextPolisher.level.requiresLLM && current != nil

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                SectionLabel(text: title)
                if current == nil {
                    // An empty picker is not a dead end. Previously a user without keys saw
                    // "Not selected" and "no key" and had to guess to open the menu to find
                    // "Add" there. The feature looked broken rather than unconfigured. Now the
                    // action is right in the row.
                    Button {
                        newKeyProvider = selection.provider
                        newKeyName = ""
                        newKeyValue = ""
                        showAddKeySheet = true
                    } label: {
                        Text(apiKeyStore.hasAnyKey ? "keys.picker.none".loc : "keys.picker.addFirst".loc)
                            .font(Theme.Typography.mono(10))
                            .foregroundStyle(Theme.Colors.warning)
                    }
                    .buttonStyle(.plain)
                    .help("keys.picker.required".loc)
                }
            }
            // TOP alignment: the caption under the model picker makes its column taller, and
            // with centering the key picker slid down — two adjacent controls of one row
            // sat at different heights.
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Menu {
                    ForEach(APIProvider.allCases, id: \.self) { provider in
                        Section(provider.title) {
                            let keys = apiKeyStore.availableKeys(for: provider)
                            ForEach(keys) { key in
                                Button {
                                    let sel = APIKeySelection(provider: provider, keyId: key.id, model: key.model ?? defaultModel(for: provider))
                                    apiKeyStore.select(context: context, selection: sel)
                                } label: {
                                    Label(key.name, systemImage: selection.provider == provider && selection.keyId == key.id ? "checkmark" : "key")
                                }
                            }
                            Button {
                                newKeyProvider = provider
                                newKeyName = ""
                                newKeyValue = ""
                                showAddKeySheet = true
                            } label: {
                                Label("keys.picker.add".loc, systemImage: "plus")
                            }
                        }
                    }
                } label: {
                    pickerField(text: current?.name ?? "keys.picker.notSelected".loc,
                                subtitle: current == nil ? nil : subtitle,
                                isPlaceholder: current == nil)
                }
                .buttonStyle(.plain)
                // Width by TOKEN, like all pickers. This one had no limit of its own — it took
                // whatever was left of the row and measured 155pt versus 200 for its neighbor.
                // Two adjacent pickers of the same kind differing by 45pt is the most visible
                // vertical misalignment on the screen.
                .frame(minWidth: Theme.Size.picker, maxWidth: .infinity)
                .keylyInapplicable(when: keyUnused, reason: "keys.picker.notNeeded".loc)

                // The text PROCESSING model picker is live in ALL three transcription modes.
                // The transcription model lives in a separate `transcriptionModelBlock` block,
                // and the two must not be confused.
                //
                // The same defect was fixed twice, each time for one branch of the matrix only. First,
                // with the on-device model the picker was dimmed with "Only needed for cloud modes" —
                // which was false: processing goes to the cloud in every mode. That was fixed, but in
                // "while speaking" mode the PROCESSING picker was still replaced by a
                // "gpt-realtime-whisper" stub captioned "only this one is available in this mode" —
                // a substituted control from a neighboring topic, so users still could not pick a model.
                // Processing does work in this mode and costs money: `polish.afterStop` explicitly
                // promises the text is rewritten after stopping.
                if context == .voiceToText {
                    // The picker selects the text PROCESSING model; the app picks the transcription
                    // model itself and says so in the line below — otherwise the disappearance of the
                    // previous choice would read as a lost setting.
                    VStack(alignment: .leading, spacing: 2) {
                        Menu {
                            ForEach(availableModels, id: \.self) { option in
                                Button {
                                    apiKeyStore.updateModel(for: context, model: option)
                                } label: {
                                    Label(modelMenuTitle(option),
                                          systemImage: option == model ? "checkmark" : "cpu")
                                }
                            }
                        } label: {
                            pickerField(text: model,
                                        subtitle: ModelPricing.perCall(for: model).map { "pricing.perCall".loc($0) },
                                        isPlaceholder: false)
                        }
                        .buttonStyle(.plain)
                        // The job description is shown ONLY when there is a job. Otherwise two mutually
                        // exclusive captions appeared under the picker in a row:
                        // "Processes text after transcription" and then "Not used: text processing is
                        // off". That is the default configuration (`verbatim`), so every new user saw the
                        // contradiction, and it read as "new caption added, old one forgotten".
                        if TextPolisher.level.requiresLLM {
                            Text("voice.model.processesText".loc)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(minWidth: Theme.Size.picker, maxWidth: .infinity)
                    // A PHANTOM control, and in the DEFAULT configuration: `TextPolishLevel.default`
                    // is `.verbatim`, and `TextPolisher.apply` returns on it BEFORE calling the model.
                    // The picker was still drawn live with "Processes text after transcription" —
                    // the caption promised work that does not happen in this mode. This file already
                    // applies dim-with-reason to two other dependencies; this branch was left open.
                    .keylyInapplicable(when: !TextPolisher.level.requiresLLM,
                                       reason: "voice.model.needsPolish".loc)
                } else if availableModels.count > 1 {
                    Menu {
                        ForEach(availableModels, id: \.self) { option in
                            Button {
                                apiKeyStore.updateModel(for: context, model: option)
                            } label: {
                                Label(modelMenuTitle(option),
                                      systemImage: option == model ? "checkmark" : "cpu")
                            }
                        }
                    } label: {
                        pickerField(text: model,
                                    subtitle: ModelPricing.perCall(for: model).map { "pricing.perCall".loc($0) },
                                    isPlaceholder: false)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: Theme.Size.picker, maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            normalizeModelSelectionIfNeeded(context: context, provider: selection.provider)
        }
        .onChange(of: selection.provider) { _, newProvider in
            normalizeModelSelectionIfNeeded(context: context, provider: newProvider)
        }
    }

    /// Menu item title: model name plus price, if known.
    ///
    /// The price used to appear ONLY next to the selected model — i.e. exactly when the
    /// choice was already made, while at the moment of choosing there was nothing to compare.
    /// Ten slugs differing in price more than tenfold, with no hint at all. Models without
    /// a known price keep a bare name — making one up is not allowed.
    func modelMenuTitle(_ model: String) -> String {
        guard let usd = ModelPricing.perCall(for: model) else { return model }
        return "\(model)   ≈ \(usd)"
    }

    func pickerField(text: String, subtitle: String?, isPlaceholder: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(isPlaceholder ? Theme.Colors.fgDim : Theme.Colors.fg)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.mono(10))
                    .foregroundStyle(Theme.Colors.fgDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.Size.control)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .stroke(Theme.Colors.border, lineWidth: 1)
        )
    }
}
