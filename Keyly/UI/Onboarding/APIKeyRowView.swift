import SwiftUI

/// One saved API key entry — a COMPACT ROW (not a heavy card with 40 dots):
/// `[health label] name · key tail · [Select / Active] · [⋯ menu]`. All features are kept
/// (name, multiple keys, check, choosing the active one, deletion) — but presented as a clean row.
/// Single source of truth for the real screen (`apiKeyRow` delegates here) and the QA gallery.
///
/// `snapshot=true` is a static render for `ImageRenderer` (it doesn't capture live TextField/Menu):
/// the name is drawn as `Text`, the menu as a bare icon.
struct APIKeyRowView: View {
    @Binding var name: String
    @Binding var keyValue: String
    let validation: ValidationState
    /// The row's key — needed to get the time of the last check.
    var keyId: UUID = UUID()
    let isSelected: Bool
    var snapshot: Bool = false
    var onValidate: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSelect: () -> Void = {}
    /// Assign the key to ONE module.
    var onSelectFor: (APIKeyContext) -> Void = { _ in }
    /// Open the module screen where the model is chosen. Needed exactly for the "wrong model"
    /// status: the error text sends the user there, while the only button nearby was called
    /// "Select" and assigned the key to a module — i.e. didn't do what was promised.
    var onOpenModuleForModel: (() -> Void)?
    /// Rotation: replacing the key's VALUE without losing references. There used to be no such
    /// item anywhere, and an expired key had to be deleted and re-added — which reset the selection
    /// in every module referring to it.
    var onRotate: () -> Void = {}
    /// Who uses the key. An empty list means the key is set up but assigned nowhere: that is
    /// useful to know too, so the row doesn't stay silent but says "not used".
    var usedIn: [String] = []
    /// Open the consumer's screen by its index in `usedIn`.
    var onOpenConsumer: ((Int) -> Void)?

    /// How many consumer names are shown in full; the rest as an "and N more" counter.
    private static let visibleConsumers = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            failureExplanation
        }
    }

    /// The refusal reason — as a VISIBLE line, not a tooltip.
    ///
    /// The explanation used to live only in `.help` over the status label: after pasting a key that
    /// was known to be wrong, all you saw was the word "error" and nothing more — "I don't see a
    /// message, just a key with an error". A hover hint doesn't work as a carrier of the reason:
    /// you have to find it first, and there is nothing to look for — nothing on screen hints that
    /// there is text somewhere.
    @ViewBuilder
    private var failureExplanation: some View {
        if case .failure(let why) = validation {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                // The "wrong model" reason is fixed on the module screen — that's where we lead.
                // Previously the only button nearby was "Select", which assigns the key to a
                // module: the user pressed it and fixed nothing.
                if why == .badModel, let onOpenModuleForModel {
                    Button("keys.status.badModel.action".loc, action: onOpenModuleForModel)
                        .buttonStyle(.link)
                        .font(Theme.Typography.caption)
                }
            }
            // Aligned to the key NAME, not the edge: the reason belongs to the key, and a line
            // indented to the right reads as a caption for the value mask.
            .padding(.leading, Theme.Space.m)
        }
    }

    private var row: some View {
        HStack(spacing: Theme.Space.m) {
            // The status is a MONO LABEL, not a colored dot. Four colored dots in one window were
            // the only rainbow in a monochrome system, and a red dot on a merely UNCHECKED key read
            // as "everything is broken". Color remains only for errors — the only state that needs
            // attention; the others are distinguishable by word without color.
            // COLUMN width, not text width. There used to be a `fixedSize` here, and the cell
            // stretched to its line: "ok · 2 min ago" and "checking…" had different widths, so in a
            // list of two keys the names, tails and consumers started at different verticals — a
            // table without a single axis.
            Text(statusWithAge)
                .font(Theme.Typography.mono(10))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 116, alignment: .leading)
                .help(statusText)

            nameField
                .frame(width: 150, alignment: .leading)

            // Key tail — recognizable (••••a1b2), not 40 meaningless dots.
            VStack(alignment: .leading, spacing: 1) {
                Text(maskedTail)
                    .font(Theme.Typography.mono(11))
                    .foregroundStyle(Theme.Colors.fgDim)
                    .lineLimit(1)
                if usedIn.isEmpty {
                    Text("keys.row.unused".loc)
                        .font(Theme.Typography.mono(9))
                        .foregroundStyle(Theme.Colors.fgDim)
                        .help("keys.row.unused.help".loc)
                } else {
                    // Each consumer is a LINK to its screen. The list said what would break when the
                    // key was deleted, but there was no way to get from it to the module: the user
                    // read the names and went looking for them in the sidebar by hand.
                    // Show A FEW names in full and the rest as a number.
                    //
                    // Two earlier attempts were worse: tail truncation turned "Translate to Russian"
                    // and "Translate to English" into two indistinguishable "Translate to…", and
                    // middle truncation into "Trans…ssian · Trans…glish", i.e. a cipher that has to be
                    // decoded. The line answers "where is this key used" — so the names in it must be
                    // readable, not squeezed in at any cost.
                    HStack(spacing: 4) {
                        ForEach(Array(usedIn.prefix(Self.visibleConsumers).enumerated()),
                                id: \.offset) { index, name in
                            if index > 0 {
                                Text("·").font(Theme.Typography.mono(9))
                                    .foregroundStyle(Theme.Colors.fgDim)
                            }
                            Button(name) { onOpenConsumer?(index) }
                                .buttonStyle(.plain)
                                .font(Theme.Typography.mono(9))
                                .foregroundStyle(Theme.Colors.accent)
                                .help("keys.row.openConsumer".loc(name))
                        }
                        if usedIn.count > Self.visibleConsumers {
                            Text("keys.row.moreConsumers".loc(usedIn.count - Self.visibleConsumers))
                                .font(Theme.Typography.mono(9))
                                .foregroundStyle(Theme.Colors.fgDim)
                                .help(usedIn.joined(separator: ", "))
                        }
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Space.s)

            // "Active" is a quiet status, NOT a button. An inactive key gets a "Select" button.
            // No checkmark: the word and the checkmark carried the SAME signal twice, and the mono
            // health label is already on the left — three marks for one thing.
            //
            // THE EMPHASIS IS INVERTED. It used to be the other way round: "Active" in gray
            // 138/255, and "Select" on an UNUSED key in white 237. Scanning the list, the eye found
            // inactive keys first, while the user's question is exactly the opposite: "which one
            // is working now".
            //
            // The status gets weight and the accent dot, the action gets a quiet look. "Active"
            // still doesn't become a button: it has neither a frame nor a fill.
            if isSelected {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("key.active".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fg)
                }
            } else {
                // A menu, not a single button. "Select" with one press reassigned the key to BOTH
                // typos and voice at once — i.e. took it away from the two modules listed one line
                // above, and the user found out when the second module stopped working.
                if snapshot {
                    // `ImageRenderer` doesn't capture a live menu — draw its look as text.
                    // Otherwise the "no key selected" state arrives in the gallery as a yellow
                    // placeholder, and a surface nobody has actually seen gets judged.
                    HStack(spacing: 4) {
                        Text("key.select".loc)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(Theme.Typography.caption)
                    // Quieter than the status: the action is always available, while which key is
                    // working is information people look for.
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Colors.surfaceHover)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .stroke(Theme.Colors.border, lineWidth: 1))
                    )
                } else {
                    Menu("key.select".loc) {
                        Button("key.select.errorFix".loc) { onSelectFor(.errorFix) }
                        Button("key.select.voice".loc) { onSelectFor(.voiceToText) }
                        Divider()
                        Button("key.select.both".loc) { onSelect() }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            keyMenu
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(isSelected ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder private var nameField: some View {
        if snapshot {
            Text(name.isEmpty ? "keys.row.untitled".loc : name)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(name.isEmpty ? Theme.Colors.fgDim : Theme.Colors.fg)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            TextField("keys.row.name".loc, text: $name)
                .textFieldStyle(.plain)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fg)
                .lineLimit(1)
        }
    }

    /// Actions (check/delete) live in one "⋯" menu instead of three icons outside.
    @ViewBuilder private var keyMenu: some View {
        let glyph = Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.Colors.fgMuted)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        if snapshot {
            glyph
        } else {
            Menu {
                Button("keys.row.validate".loc, action: onValidate)
                Button("keys.row.rotate".loc, action: onRotate)
                Divider()
                Button("keys.row.delete".loc, role: .destructive, action: onDelete)
            } label: {
                glyph
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("keys.row.menu".loc)
            .accessibilityLabel("keys.row.menu.a11y".loc(name))
        }
    }

    private var maskedTail: String {
        let v = keyValue.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return "key.status.unknown".loc }
        if v.count <= 4 { return String(repeating: "•", count: v.count) }
        return "••••" + v.suffix(4)
    }

    /// Short label in the list. The full wording is in `statusText` (hover hint).
    private var statusLabel: String {
        switch validation {
        case .unknown:  return "key.status.unknown".loc
        case .checking: return "key.status.checking".loc
        case .success:  return "key.status.ok".loc
        case .failure(let why):  return why.short
        }
    }

    /// Status together with how fresh the check is. Age is added only to a check that
    /// ACTUALLY HAPPENED: "not checked" and "checking…" have no age by definition.
    private var statusWithAge: String {
        switch validation {
        case .success, .failure:
            guard let checked = KeyCheckLog.lastCheck(keyId: keyId) else { return statusLabel }
            return "\(statusLabel) · \(KeyCheckLog.humanized(checked))"
        case .unknown, .checking:
            return statusLabel
        }
    }

    private var statusColor: Color {
        switch validation {
        // Color is for errors ONLY. "ok" and "checking…" read as words, and the monochrome stays intact.
        case .failure:  return Theme.Colors.danger
        case .checking: return Theme.Colors.fgMuted
        case .success:  return Theme.Colors.fgMuted
        case .unknown:  return Theme.Colors.fgDim
        }
    }

    private var statusText: String {
        switch validation {
        case .unknown:  return "key.status.unknown.full".loc
        case .checking: return "key.status.checking.full".loc
        case .success:  return "key.status.ok.full".loc
        case .failure(let why):  return why.full
        }
    }
}
