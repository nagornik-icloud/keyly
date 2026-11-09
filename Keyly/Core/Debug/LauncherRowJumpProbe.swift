#if DEBUG
import SwiftUI

/// Structural copy of the launcher row for measuring the hotkey field SHIFT.
///
/// The live `KeylyHotKeyField` can't be captured in two states: the warning lives in `@State`
/// and appears only after a real key press, which `ImageRenderer` doesn't do. So the row
/// LAYOUT is replicated here (name + `Spacer()` + field column) with the same right-edge
/// pinning, and the message is toggled by a flag.
///
/// What is checked: between the `launcher-row-quiet` and `launcher-row-notice` frames the
/// field's right edge must stay on the same pixel. The field used to jump left by about
/// 200pt — out from under the cursor that had just clicked it.
struct LauncherRowJumpProbe: View {
    let withNotice: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Text("Telegram")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fg)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                // Take the key name from the product, not a literal: while this said "Rew", the probe
                // frame survived the F-row renaming and showed a label the product no longer has.
                Text(KeyCombo(keyCode: NXKeyType.rewind, modifiers: [], isSystemKey: true).description)
                    .font(Theme.Typography.mono(12, .medium))
                    .frame(width: 160, height: Theme.Size.control)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Colors.surfaceHover)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1)))
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if withNotice {
                    BareKeyNoticeView(message: "hotkey.bare.system".loc("key.action.player".loc))
                }
            }
        }
        .padding(Theme.Space.m)
        .background(Theme.Colors.surface)
        .preferredColorScheme(.dark)
    }
}

/// Structural copy of the snippet editor footer — the second place suspected of a jump.
///
/// The layout differs: the hotkey field sits on the LEFT of its column, so it doesn't move
/// itself — but the column, growing for the message, steals width from its neighbour (the
/// triggers field). Measure the RIGHT edge of the triggers field: it shows whether the
/// neighbour shrank.
struct SnippetFooterJumpProbe: View {
    let withNotice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("ТРИГГЕРЫ").font(Theme.Typography.mono(9)).foregroundStyle(Theme.Colors.fgDim)
                HStack {
                    Text("@@").font(Theme.Typography.mono(11)).foregroundStyle(Theme.Colors.fg)
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(height: Theme.Size.control)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Colors.surfaceHover)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)))
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("ХОТКЕЙ").font(Theme.Typography.mono(9)).foregroundStyle(Theme.Colors.fgDim)
                VStack(alignment: .leading, spacing: 6) {
                    Text("F5")
                        .font(Theme.Typography.mono(12, .medium))
                        .frame(width: 170, height: Theme.Size.control)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Colors.surfaceHover)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .stroke(Theme.Colors.border, lineWidth: 1)))
                        .foregroundStyle(Theme.Colors.fg)
                        .fixedSize()
                }
            }
        }
        if withNotice {
            BareKeyNoticeView(message: "hotkey.bare.character".loc("]"))
        }
        }
        .padding(Theme.Space.m)
        .frame(width: 620)
        .background(Theme.Colors.surface)
        .preferredColorScheme(.dark)
    }
}
#endif
