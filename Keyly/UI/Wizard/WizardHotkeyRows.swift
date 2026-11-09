import SwiftUI

/// The three main hotkeys on wizard step 4: layout · voice · typos.
/// They can be changed right here: the recorder is the same as on the module screens, so recording
/// behavior and conflict resolution live in one place instead of being duplicated for the wizard.
struct WizardHotkeyRows: View {

    /// `true` in a QA snapshot: `ImageRenderer` does not capture `NSViewRepresentable` (the recorder comes out
    /// as a yellow placeholder), so there we draw a keycap with the current combination; the step becomes
    /// actually checkable, not "nominally captured".
    var snapshot: Bool = false

    @AppStorage(SettingsKeys.layoutHotKey) private var layoutData: Data?
    @AppStorage(SettingsKeys.errorFixHotKey) private var errorFixData: Data?
    @AppStorage(SettingsKeys.voiceHotKey) private var voiceData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            row("wizard.hotkeys.layout".loc, binding(for: $layoutData))
            row("wizard.hotkeys.voice".loc, binding(for: $voiceData))
            row("wizard.hotkeys.errorFix".loc, binding(for: $errorFixData))
        }
    }

    private func row(_ title: String, _ combo: Binding<KeyCombo?>) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.fg)
            Spacer(minLength: Theme.Space.m)
            if snapshot {
                Group {
                    if let description = combo.wrappedValue?.description {
                        HotkeyChip(text: description)
                    } else {
                        Text("overview.noHotkey".loc)
                            .font(Theme.Typography.mono(10))
                            .foregroundStyle(Theme.Colors.fgDim)
                    }
                }
                .frame(width: KeylyHotKeyField.Size.inRow, height: Theme.Size.control, alignment: .trailing)
            } else {
                KeylyHotKeyField(keyCombo: combo, width: KeylyHotKeyField.Size.inRow)
            }
        }
    }

    /// `KeyCombo` is stored encoded in `UserDefaults`; the wizard reads and writes it the same
    /// way as other screens so the values do not diverge in format.
    private func binding(for data: Binding<Data?>) -> Binding<KeyCombo?> {
        Binding(
            get: {
                guard let raw = data.wrappedValue else { return nil }
                return try? JSONDecoder().decode(KeyCombo.self, from: raw)
            },
            set: { combo in
                data.wrappedValue = combo.flatMap { try? JSONEncoder().encode($0) }
                NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
            }
        )
    }
}
