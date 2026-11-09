import SwiftUI

/// Triggers as chips, not a column of input fields.
///
/// A column of fields misrepresented the data: it looked like a form where each field is a
/// separate setting, whereas triggers are a SET of equal short words. Five triggers took
/// five rows of editor height, and adding one required first pressing "＋", then hitting
/// the new empty field with the cursor.
struct TriggerTokenField: View {
    @Binding var triggers: [String]
    /// Check before adding. Returns the rejection reason, or `nil` if allowed.
    var validate: (String) -> String?

    @State private var draft: String = ""
    @State private var rejection: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            chips
            if let rejection {
                Text(rejection)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chips: some View {
        KeylyFlowLayout(spacing: 6) {
            ForEach(Array(triggers.enumerated()), id: \.offset) { index, trigger in
                chip(trigger, at: index)
            }
            input
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(isFocused ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1)
                )
        )
        // The whole frame is clickable and focuses the field: hitting the narrow input line
        // next to the chips with the mouse is hard, and a miss on empty space did nothing.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private func chip(_ trigger: String, at index: Int) -> some View {
        HStack(spacing: 4) {
            Text(trigger)
                .font(Theme.Typography.mono(11))
                .foregroundStyle(Theme.Colors.fg)
            Button {
                guard index < triggers.count else { return }
                triggers.remove(at: index)
                rejection = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.Colors.fgDim)
            }
            .buttonStyle(.borderless)
            .help("snippets.editor.removeTrigger".loc)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.Colors.accent.opacity(0.16)))
    }

    private var input: some View {
        TextField("snippets.editor.triggerPlaceholder".loc, text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.Typography.mono(11))
            .frame(minWidth: 90)
            .focused($isFocused)
            .onSubmit { commit() }
            // A space completes the trigger instead of going into it: a trigger with a space will
            // NEVER fire — the typed sequence breaks into two words.
            .onChange(of: draft) { _, value in
                guard value.contains(" ") else { return }
                draft = value.replacingOccurrences(of: " ", with: "")
                commit()
            }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let reason = validate(value) {
            rejection = reason
            return
        }
        rejection = nil
        triggers.append(value)
        draft = ""
    }
}

/// Flow layout: chips wrap to the next line when the width runs out.
///
/// Custom because `LazyVGrid` needs a known number of columns, while chips have different
/// widths: in a fixed grid a short "@@" would take as much space as a long
/// "workaddress", and the row would fall apart into gaps.
struct KeylyFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
