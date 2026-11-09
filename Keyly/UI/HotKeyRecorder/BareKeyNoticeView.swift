import SwiftUI

/// The "this key will stop working in other apps" line, shown EXACTLY at the moment a bare
/// key is assigned.
///
/// Extracted into a standalone view per the project rule: the state is transient — it lives
/// until the user leaves the screen — and a static screen dump won't catch it. Single source
/// of truth with the real field (`KeylyHotKeyField` draws exactly this view), so the gallery
/// captures what the user sees, without drift.
///
/// The tone is deliberately CALM: not danger. A bare key is allowed, and for layout switching
/// it is an established habit — the user made a legitimate choice and should learn its cost, not
/// get an error. Only two neighbors shout in red here: a taken shortcut and a registration
/// failure, where the product won't work without the user's action.
struct BareKeyNoticeView: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.warning)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}
