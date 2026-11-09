import SwiftUI

/// Cheatsheet of active shortcuts.
///
/// The product is all about hotkeys, but the only way to recall an assignment was to open the window
/// and scroll through screens — exactly when your hands are busy with something else. A floating
/// window above all others shows everything at once and closes with the same keypress.
struct CheatsheetView: View {
    struct Row: Identifiable {
        let id = UUID()
        let combo: String
        let title: String
    }

    let rows: [Row]

    /// Gallery capture. `ImageRenderer` doesn't draw `ScrollView` content — it comes out empty,
    /// and the window in the frame looks like an empty frame with a title. Same class as with
    /// live `TextField` (see `APIKeyRowView`): the single source of truth with the real screen
    /// is kept, only the container is swapped.
    var snapshot = false

    @ViewBuilder
    private func scrollOrPlain<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if snapshot { content() } else { ScrollView { content() } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("cheatsheet.title".loc)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fg)
                Spacer(minLength: Theme.Space.m)
                Text("cheatsheet.close".loc)
                    .font(Theme.Typography.mono(10))
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)

            Divider().overlay(Theme.Colors.border)

            if rows.isEmpty {
                // An empty cheatsheet says so too: otherwise the window looks broken.
                Text("cheatsheet.empty".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                scrollOrPlain {
                    VStack(spacing: 0) {
                        // The row is laid out LIKE ON THE "OVERVIEW": name on the left, bright,
                        // key on the right in a keycap. It used to be the other way round.
                        //
                        // Three problems at once. (1) The shortcut was bare monospace, while
                        // EVERYWHERE else in the product a hotkey sits in a `HotkeyChip` frame;
                        // the cheatsheet, the only surface made entirely of hotkeys, was the only
                        // one where they didn't look like keys. (2) The emphasis was inverted:
                        // the key was #EDEDED (17:1) and the action name #8A8A8A (5.8:1) — people
                        // scan the names, and they were three times dimmer. (3) The 92pt column was
                        // never filled (the widest real shortcut is 72pt), leaving up to 91pt of
                        // empty space, while the labels got truncated.
                        ForEach(rows) { row in
                            HStack(spacing: Theme.Space.m) {
                                Text(row.title)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.fg)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: Theme.Space.m)
                                HotkeyChip(text: row.combo)
                            }
                            .padding(.horizontal, Theme.Space.l)
                            .frame(height: 32)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
        }
        .frame(width: 420)
        .frame(maxHeight: snapshot ? nil : 480)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.bg)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.borderStrong, lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
