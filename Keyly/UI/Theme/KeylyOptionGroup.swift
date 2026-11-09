import SwiftUI

/// One choice option: title, explanatory line, possible unavailability and a trailing slot.
struct KeylyOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    /// What you pay and what you get. Without this line the "local / cloud" choice cannot be made:
    /// the names alone say nothing about network, API key or disk space.
    let subtitle: String
    /// Why it cannot be selected. `nil` means available.
    ///
    /// An unavailable option is SHOWN with its reason, not hidden: users look for a vanished
    /// option and conclude the feature does not exist. We hide only what does not exist as a
    /// concept in this configuration.
    var disabledReason: String? = nil

    var id: Value { value }
}

/// Vertical list of mutually exclusive options, used where a segmented control does not fit:
/// each option has its own explanation, and sometimes a reason it is unavailable.
///
/// Replaces a "segment + toggle" pair that described one axis (recognition method)
/// but sat as independent controls and silently overrode each other.
struct KeylyOptionGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [KeylyOption<Value>]
    /// Extra block under an option: model status, nested settings, etc.
    ///
    /// Action on the RIGHT, inside the option row itself.
    ///
    /// Why: the "Model not downloaded / Download" line used to live as a separate inset UNDER
    /// the option and cost ~50pt of height for two words and a button, while half the width
    /// of the option row itself sat empty on the right. The inset stays for things that
    /// really need their own line (a download bar); a one-click action
    /// goes where people are already looking.
    var trailing: (Value) -> AnyView? = { _ in nil }

    /// Inset UNDER an option, for things that need their own line (download bar, file
    /// path). Asked of EVERY option, decided by the caller: by default the detail only
    /// makes sense under the selected one, but there is an exception, which is why the decision
    /// is left to the caller: for an UNAVAILABLE option the detail may be exactly what makes it
    /// available. Hide it and you get a dead end: "download the model" with no Download button.
    var detail: (Value) -> AnyView? = { _ in nil }

    /// Left edge of option text: row padding + marker + gap. Computed from the same
    /// constants as the row itself; otherwise changing padding in one place silently breaks
    /// the inset alignment in another.
    private static var detailInset: CGFloat { Theme.Space.m + markerSize + Theme.Space.s }
    /// Not `static let`: generic types cannot have static stored properties.
    private static var markerSize: CGFloat { 14 }

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ForEach(options) { option in
                VStack(spacing: 0) {
                    row(option)
                    if let detail = detail(option.value) {
                        // The inset aligns to its option's TEXT, not to the group edge.
                        // The padding used to be 26 pt with text at 34, so the inset sat
                        // LEFT of the label it belongs to, hung in the gap between
                        // two options and read as a separate block. In a real run the
                        // Download button was on screen, but the user did not connect it
                        // with the unavailable option and assumed a dead end.
                        detail
                            .padding(.leading, Self.detailInset)
                            .padding(.trailing, Theme.Space.m)
                            .padding(.vertical, Theme.Space.s)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                // `surfaceHover`, not `surface`: the inset sits INSIDE a card
                                // filled with exactly the same `surface`, so it effectively had
                                // no border. The "Model not downloaded / Download" line
                                // hung between options belonging to nothing, and the
                                // brightest button on screen belonged to an INACTIVE item.
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .fill(Theme.Colors.surfaceHover)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card,
                                                              style: .continuous)
                                        .stroke(Theme.Colors.border, lineWidth: 1))
                            )
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: selection)
    }

    private func row(_ option: KeylyOption<Value>) -> some View {
        let isOn = option.value == selection
        let disabled = option.disabledReason != nil
        // Only an UNselected option DIMS. The selected one stays high-contrast even when it
        // cannot be applied right now: otherwise the screen answers "what is turned on?"
        // backwards: the selection looks disabled and the unselected ones look bright.
        //
        // In voice settings this was the default state after install: "Local model"
        // selected and dimmed (model not downloaded), two paid cloud options bright.
        // People read it as "local is unavailable and I chose nothing", and the main line
        // of the screen, "works offline and without a key", got dimmed too.
        let dimmed = disabled && !isOn
        // The trailing action sits OUTSIDE the row button.
        //
        // A first version put it inside `label`, and it inherited `.disabled` from
        // the row. So the Download button of an unavailable option stopped working
        // exactly when it was the only thing that could make the option available: the dead end
        // that the comment on `detail` in this file forbids. It showed up as
        // a dimmed button in a screenshot.
        return HStack(spacing: Theme.Space.s) {
            optionButton(option, isOn: isOn, disabled: disabled, dimmed: dimmed)
            if let action = trailing(option.value) {
                action.padding(.trailing, Theme.Space.m)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isOn ? Theme.Colors.surfaceHover : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(isOn ? Theme.Colors.borderStrong : Color.clear, lineWidth: 1)
                )
        )
    }

    private func optionButton(_ option: KeylyOption<Value>,
                              isOn: Bool, disabled: Bool, dimmed: Bool) -> some View {
        Button {
            guard !disabled else { return }
            selection = option.value
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                marker(isOn: isOn, dimmed: dimmed)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(dimmed ? Theme.Colors.fgDim : Theme.Colors.fg)
                    // The unavailability reason ADDS to the explanation, it does not replace it.
                    // It used to replace it, and the "On this Mac" option stopped saying it
                    // weighs 1.2 GB and works offline exactly when the user
                    // is deciding whether to download it. An unavailable option must keep stating its
                    // cost: that is precisely why people pick it.
                    Text(option.subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if let reason = option.disabledReason {
                        Text(reason)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// We draw the selection circle ourselves: the system `Picker(.radioGroup)` brings its own font,
    /// padding and blue accent, and in "Mono" it looks like an insert from another system.
    private func marker(isOn: Bool, dimmed: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(dimmed ? Theme.Colors.border
                               : (isOn ? Theme.Colors.accent : Theme.Colors.borderStrong),
                        lineWidth: 1)
                .frame(width: Self.markerSize, height: Self.markerSize)
            if isOn {
                // The selected option's dot is ALWAYS accent-colored: it answers "what is
                // turned on", not "can this be applied right now". The yellow reason line
                // under the title covers the latter.
                Circle()
                    .fill(Theme.Colors.accent)
                    .frame(width: 7, height: 7)
            }
        }
    }
}
