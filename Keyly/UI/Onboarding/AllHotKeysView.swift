import SwiftUI

/// "All hotkeys" screen: what is assigned, what it does, where it is configured.
///
/// Before it, shortcuts lived on four screens and "what is already taken" had no answer
/// anywhere — people found out a combo was taken only when they tried to assign it twice.
///
/// Both failure cases are shown here too: a combo the system refused to grant, and a
/// duplicate that came in via settings import, bypassing the conflict check.
struct AllHotKeysView: View {
    let entries: [HotKeyInventory.Entry]
    let duplicates: Set<String>
    let onOpen: (HotKeyInventory.Source) -> Void

    @ObservedObject private var registration = HotKeyRegistrationStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "hotkeys.all.title".loc)

            if entries.isEmpty {
                Text("hotkeys.all.empty".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.m)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.Colors.border) }
                        row(entry)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Colors.surface)
                )
            }
        }
    }

    private func row(_ entry: HotKeyInventory.Entry) -> some View {
        Button {
            onOpen(entry.source)
        } label: {
            HStack(spacing: Theme.Space.m) {
                Text(entry.combo.description)
                    .font(Theme.Typography.keys(12))
                    .foregroundStyle(Theme.Colors.fg)
                    .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(entry.isActive ? Theme.Colors.fg : Theme.Colors.fgDim)
                        .lineLimit(1)
                    Text(entry.source.placeKey.loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Space.m)

                problems(entry)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keylyHoverHighlight(cornerRadius: 0)
        .help("hotkeys.all.open".loc)
    }

    @ViewBuilder
    private func problems(_ entry: HotKeyInventory.Entry) -> some View {
        HStack(spacing: Theme.Space.s) {
            if !entry.isActive {
                // A disabled module still OCCUPIES its shortcut — otherwise it is unclear
                // why that combo cannot be assigned elsewhere.
                tag("hotkeys.all.off".loc, color: Theme.Colors.fgDim)
            }
            if duplicates.contains(entry.fieldID) {
                tag("hotkeys.all.duplicate".loc, color: Theme.Colors.warning)
            }
            if registration.isFailed(entry.fieldID) {
                tag("hotkeys.all.notWorking".loc, color: Theme.Colors.danger)
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.Typography.mono(10))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(color.opacity(0.14))
            )
    }
}
