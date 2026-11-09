import SwiftUI

/// Hotkey recording field: recorder, reset button and problem messages.
///
/// The "bare" key warning no longer STAYS on screen: the yellow line "while Keyly is running, F5
/// will stop working in other apps" sat under every field and in every list row — the launcher
/// screen had four of them in a row. The fact is true, but people learn it once and would read it
/// every time they open the screen.
///
/// Removing the warning ENTIRELY was a mistake: the problem was the REPETITION, not the fact; after
/// removal a user would assign "]" and "]" silently stopped typing in all apps, without a single
/// hint as to why. The dead-code gate caught it: `BareKeyWarning` was still covered by seven tests
/// that guarded nothing, because the product never called it.
///
/// Now it is shown EXACTLY at the moment of assignment — while the user is looking at the field they
/// just pressed keys in — and disappears the next time the screen opens: `@State` lives no longer than
/// the view. Not a single permanent yellow triangle remains on screen.
///
/// The remaining messages require ACTION and therefore live right at the field: a taken shortcut
/// (can be taken over) and a registration failure (another one must be chosen).
struct KeylyHotKeyField: View {

    /// Message that the shortcut is already taken. Lives HERE, not in a modal window: the user is
    /// looking at the field they just pressed keys in, and the answer must be right there.
    struct Conflict {
        let message: String
        /// Take the shortcut away from whoever currently uses it. `nil` means there's no one to take it from (the system).
        let onReassign: (() -> Void)?
        let onDismiss: () -> Void
    }

    @Binding var keyCombo: KeyCombo?
    /// The field width comes from TWO sizes instead of a number at every call site.
    ///
    /// There used to be five different ones: 200 on module screens, 170 in Settings, 170 in the snippet
    /// editor, 160 in the launcher, 150 in the wizard. Unnoticeable individually, together they feel
    /// homemade: the same field is a slightly different size every time.
    /// There are two sizes because there really are two roles — a field on its own row and a field
    /// in a dense list row.
    enum Size {
        /// The field ON ITS OWN — in Settings and the wizard, where there is no horizontal strip next to it.
        ///
        /// 140, not the old 190. The number is not eyeballed: the widest state of the field is
        /// "Press a hotkey…" in both languages, 120.5pt plus 8+8 inner padding = 136.5pt.
        /// 140 fits the same text without truncation and leaves 50pt less of a gap.
        /// The width is FIXED here because there are neighbors on the right: a field sizing itself to
        /// its value would push them while recording. In the horizontal strip there are no neighbors on
        /// the right, so there the field hugs its value (see `fieldWithMenu`).
        static let standalone: CGFloat = 140
        /// In a list row next to a name, icon and actions.
        static let inRow: CGFloat = 160
    }

    var width: CGFloat = Size.standalone
    var conflict: Conflict?
    /// Field identifier (`HotKeyFieldID`) — used by the field to learn whether the system rejected
    /// the registration of this particular shortcut.
    var fieldID: String?
    /// Reset the shortcut. The button lives INSIDE the component: outside it ended up after the whole
    /// column, and the column is wider than the field because of messages — so the ✕ drifted a hundred
    /// and fifty points to the right of the field it belongs to.
    var onClear: (() -> Void)?
    /// Which edge the field ITSELF is pinned to inside the messages column.
    ///
    /// Messages are wider than the field (up to 360pt vs 160–200), so the column stretches to fit them.
    /// In a launcher row the field sits after a `Spacer()` — and at the moment of assignment it slid
    /// about 200pt left from under the cursor that had just clicked it. Pinning the field to the edge
    /// it lives at lets the message grow the other way: the field stays put, only the text moves.
    var fieldEdge: HorizontalAlignment = .leading

    /// The setting name INSIDE the row — then the field is drawn as a full-width horizontal strip.
    /// `nil` means a bare field, as in lists and the wizard.
    ///
    /// The strip solves exactly the complaint that started the redesign: "the hotkey is hidden
    /// somewhere on the right while taking up a huge width, even though it will literally contain one
    /// or two characters". The STRIP holds the row width, the field stays small and sits on the left,
    /// next to its name.
    var rowLabel: String?

    @ObservedObject private var registration = HotKeyRegistrationStatus.shared

    /// The "assigned just now" state lives in a shared object, not in `@State`: otherwise only the
    /// field itself could draw the message — and then it would inevitably widen the field's column.
    /// See `BareKeyNoticeStatus`.
    @ObservedObject private var bareKeyNotice = BareKeyNoticeStatus.shared

    /// Whether the field draws the warning ITSELF.
    ///
    /// `false` where a 360pt-wide message breaks the row layout: the caller then owns the layout
    /// and places `BareKeyNoticeRow` wherever it fits.
    var rendersBareKeyNotice = true

    /// What will break in the system because of the bare key just assigned, or `nil`.
    private var freshBareKeyWarning: String? {
        bareKeyNotice.message(fieldID: fieldID, combo: keyCombo)
    }

    private var registrationFailed: Bool {
        guard keyCombo != nil, let fieldID else { return false }
        return registration.isFailed(fieldID)
    }

    var body: some View {
        VStack(alignment: fieldEdge, spacing: 6) {
            // Messages (conflict, registration failure, bare key) go UNDER the strip, not inside it:
            // they are up to 360pt wide and would inflate the strip vertically on every taken shortcut.
            if let rowLabel {
                lyingRow(label: rowLabel)
            } else {
                fieldWithMenu
                    // Shrink to content so the "…" sits right next to the field instead of drifting
                    // to the edge of a wider detail (messages can be up to 360pt).
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity,
                           alignment: fieldEdge == .trailing ? .trailing : .leading)
            }

            if registrationFailed {
                // Separate from the conflict: a conflict is "taken inside Keyly, can be taken over",
                // here the shortcut is held by something outside, and the only option is to pick another.
                Label {
                    Text("hotkey.registrationFailed".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.danger)
                }
                .frame(maxWidth: 360, alignment: .leading)
            }

            if let conflict {
                conflictBanner(conflict)
            }

            if rendersBareKeyNotice, let freshBareKeyWarning {
                BareKeyNoticeView(message: freshBareKeyWarning)
                    .transition(.opacity)
            }
        }
        .animation(KeylyMotion.standard, value: freshBareKeyWarning)
        .onChange(of: keyCombo) { _, combo in
            // Mark ONLY the assignment. A reset (`nil`) removes the mark, otherwise assigning the
            // same key again wouldn't count as new.
            guard let fieldID else { return }
            bareKeyNotice.report(fieldID: fieldID, combo: combo)
        }
        .onDisappear {
            // "Learned once": forget when leaving the screen — next time it opens a saved bare key
            // stays silent.
            guard let fieldID else { return }
            bareKeyNotice.forget(fieldID: fieldID)
        }
    }

    @ViewBuilder
    private func conflictBanner(_ conflict: Conflict) -> some View {
        // The action goes on a SEPARATE LINE under the text, not inline in the sentence.
        //
        // "Reassign" used to be the next element of the same HStack as the message. The message
        // wraps (`fixedSize(vertical:)` at 360pt width), and the link ended up IN THE MIDDLE of the
        // sentence: "This combination is already used for [Reassign] / the Voice module." The user
        // reads nonsense and understands neither what the shortcut is taken by nor that "Reassign"
        // is a button.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.danger)
                Text(conflict.message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Button {
                    conflict.onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Colors.fgDim)
                }
                .buttonStyle(.borderless)
                .help("common.close".loc)
            }
            if let onReassign = conflict.onReassign {
                // NOT `.buttonStyle(.link)`: it draws in system blue, and in the conflict frame it is
                // the only colored spot in the whole monochrome product — it reads as a foreign
                // element rather than a Keyly action.
                Button(action: onReassign) {
                    Text("hotkey.conflict.reassign".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.danger.opacity(0.12))
        )
        .frame(maxWidth: 360, alignment: .leading)
    }

    /// The field and the actions menu. The menu is "…", not ✕: a cross to the right of the
    /// hotkey doesn't fit the style here.
    ///
    /// The menu belongs to the HOTKEY ROW, not the module. The first idea was to put removal into
    /// the module's "…" — but only custom modules have that menu (`OnboardingView+CustomModules`),
    /// while Layout, Typos, Voice and Launcher don't: removal would become unreachable on four
    /// screens out of five.
    @ViewBuilder
    private var fieldWithMenu: some View {
        let inRow = rowLabel != nil
        HStack(spacing: 6) {
            // In the strip the field hugs its value.
            //
            // This is the answer to "takes up a huge width even though it literally contains one or
            // two characters": the empty space used to be held by the FIELD ITSELF, with a 140–190pt
            // box around "F3"; now the box fits the value, and the empty space is just the strip
            // background.
            //
            // Locking the field into a fixed-width slot so the "…" wouldn't move while recording was
            // tried. The cure was worse than the disease: the "…" ended up 76pt from its field and
            // read as belonging to nothing. Better let it shift for the second of recording — the
            // field changes its look at that moment anyway (dashes, accent, "Press a hotkey…").
            field(inset: inRow)
            if keyCombo != nil, let onClear {
                Menu {
                    Button("hotkey.reset".loc, action: onClear)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.fgDim)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                // A project helper, not `.frame(width: 22)`: the target was 22×15pt vs 26×26pt for
                // the same "…" in the module header — the smallest clickable element on the screen
                // turned out to be the only entry point to the hotkey actions.
                .iconHitArea("hotkey.actions".loc)
                .help("hotkey.actions".loc)
                // Without an explicit name the AX tree called the button "More" — an English system
                // word in a Russian UI, and a blind user heard "more" without a hint of more WHAT.
                .accessibilityLabel("hotkey.actions".loc)
                .accessibilityIdentifier(fieldID.map { "keyly.hotkey.\($0).actions" }
                                         ?? "keyly.hotkey.actions")
            }
        }
    }

    /// Horizontal strip: the setting name and the field sit side by side, the strip holds the card width.
    ///
    /// There is NO permanent hint on the right ("press a shortcut while the field is active"), even
    /// though the mockup had one: 250pt of text that is true for exactly one second in the life of the
    /// setting and is always visible. The field itself already plays the hint's role — while recording
    /// it says "Press a hotkey…" and gets a dashed outline (`HotKeyRecorderNSView.updateLabel`).
    private func lyingRow(label: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            SectionLabel(text: label)
            fieldWithMenu
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
        // The plate HUGS its content instead of stretching to full width.
        //
        // A full-width strip moved the card's emptiness into the plate itself: a measurement showed
        // 581pt (78.6%) of bare fill, which read as a defect. Now to the right of the plate is the clean
        // card background, like any other block; the row as a whole still takes the full width, but
        // the empty space is no longer outlined and doesn't look like an unfilled container.
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// - Parameter inset: the field sits INSIDE the horizontal strip.
    ///   Then it is recessed (`bg`, the darkest tone) with an accented edge rather than filled with
    ///   the same `surfaceHover` as the strip. Otherwise "Layout" ended up with three nested frames
    ///   of almost the same tone around two characters — card, strip, field — a layout defect.
    private func field(inset: Bool) -> some View {
        // The test identifier is passed INSIDE, to the NSView itself: the SwiftUI modifier
        // `.accessibilityIdentifier` on a representable NSView doesn't reach the AX tree.
        HotKeyRecorderView(keyCombo: $keyCombo, fieldID: fieldID)
            // In the strip the field takes ITS OWN width (`fixedSize`), but no narrower than 64pt: a
            // 24pt box around a single "~" reads as a scrap rather than a field and is hard to hit
            // with the mouse.
            .fixedSize(horizontal: inset, vertical: false)
            .frame(minWidth: inset ? 64 : width,
                   maxWidth: inset ? nil : width,
                   minHeight: Theme.Size.control,
                   maxHeight: Theme.Size.control)
            .background(
                // The outline is mandatory: the fill matches the list row background, and without a
                // frame the hotkey field dissolves — "F4" reads as plain text.
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(inset ? Theme.Colors.bg : Theme.Colors.surfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .stroke(registrationFailed ? Theme.Colors.danger
                                    : inset ? Theme.Colors.borderStrong : Theme.Colors.border,
                                    lineWidth: 1)
                    )
            )
    }
}
