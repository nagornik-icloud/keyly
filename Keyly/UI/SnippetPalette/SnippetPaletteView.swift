import SwiftUI

/// Snippet palette content: search on top, list below, Enter inserts.
/// Ranking lives in `SnippetSearch` (pure logic, covered by tests).
struct SnippetPaletteView: View {

    let snippets: [Snippet]
    let onPick: (Snippet) -> Void
    let onCancel: () -> Void
    /// `true` in a QA snapshot: `ImageRenderer` does not capture a live `TextField`.
    var snapshot: Bool = false
    var snapshotQuery: String = ""

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var results: [Snippet] {
        SnippetSearch.rank(snippets, query: snapshot ? snapshotQuery : query)
    }

    /// Open the snippet in the main window editor (⌘↩).
    var onEdit: ((Snippet) -> Void)?
    /// Create the first snippet from an empty palette.
    var onCreateSnippet: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.Colors.border)
            if results.isEmpty {
                emptyState
            } else {
                // List and preview side by side. A one-line preview inside the list row does
                // not answer the question the palette is opened for: "this snippet or the next
                // one?" — three-paragraph snippets share their first words, and picking was
                // guesswork.
                HStack(spacing: 0) {
                    list
                        .frame(width: 320)
                    Divider().overlay(Theme.Colors.border)
                    previewPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider().overlay(Theme.Colors.border)
            // Hints ARE AWARE of emptiness. "↑↓ select" and "↵ insert" used to be lit at the
            // same brightness (measured 138 in all states), while `onMoveCommand` returns
            // immediately on an empty result: the keys are dead while the line promises the
            // opposite. A phantom control disguised as a hint is the same lie as an active
            // button that does nothing.
            hints(hasResults: !results.isEmpty)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.borderStrong, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onAppear { searchFocused = true }
        // The hints at the bottom promise ↑↓ and Esc — a promise the interface must keep.
        // Arrows are intercepted here, not in the search field: there they would move the text caret.
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            switch direction {
            case .up:   selectedIndex = max(0, selectedIndex - 1)
            case .down: selectedIndex = min(results.count - 1, selectedIndex + 1)
            default:    break
            }
        }
        .onExitCommand { onCancel() }
        // ⌘↩ — open the selected one in the editor. The palette is where the user
        // remembers the snippet; it is natural to fix it from here, rather than search for it again
        // in the settings list.
        .background(
            Button("") {
                guard results.indices.contains(selectedIndex) else { return }
                onEdit?(results[selectedIndex])
            }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
        )
        // Reset the selection when the query changes: otherwise after narrowing the list the
        // "selected" one stays at the old index, and Enter inserts something other than what the user is looking at.
        .onChange(of: query) { selectedIndex = 0 }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.fgDim)
            Group {
                if snapshot {
                    Text(snapshotQuery.isEmpty ? "palette.search".loc : snapshotQuery)
                        .foregroundStyle(snapshotQuery.isEmpty ? Theme.Colors.fgDim : Theme.Colors.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("palette.search".loc, text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit { pickSelected() }
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.Colors.fg)
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(height: 48)
    }

    @ViewBuilder
    private var list: some View {
        if snapshot {
            // In a snapshot the scroll container is BYPASSED: `ScrollView` does not lay out content
            // in an offscreen render — the frame showed an empty list next to a "4 items" counter, i.e.
            // the palette looked broken where it works. The rows are the same.
            VStack(spacing: 0) { rows }
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // VStack, not LazyVStack: there are dozens of snippets, laziness saves nothing but
                    // breaks list height measurement.
                    VStack(spacing: 0) { rows }
                }
                .onChange(of: selectedIndex) { _, new in proxy.scrollTo(new, anchor: .center) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Full text of the selected snippet. Not editable — the palette is about choosing, not
    /// editing (⌘↩ is for editing).
    @ViewBuilder
    private var previewPane: some View {
        if results.indices.contains(selectedIndex) {
            let snippet = results[selectedIndex]
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                // Header: name and triggers together. Triggers at the bottom of the pane were torn
                // from what they belong to and left a dead area between them and the text.
                if let name = snippet.name, !name.isEmpty {
                    Text(name)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Colors.fg)
                        .lineLimit(1)
                }
                if !snippet.triggers.isEmpty {
                    Text(snippet.triggers.joined(separator: " · "))
                        .font(Theme.Typography.mono(10))
                        .foregroundStyle(Theme.Colors.fgDim)
                        .lineLimit(1)
                }
                previewBody(snippet.content)
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func previewBody(_ content: String) -> some View {
        let text = Text(content)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.fgMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        if snapshot {
            // A scroll container does not lay out content in an offscreen render — the frame
            // showed an EMPTY preview for the selected snippet, i.e. the pane looked
            // broken where it works. Exactly the same cause as with the list.
            text
        } else {
            ScrollView { text.textSelection(.enabled) }
        }
    }

    private var rows: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { index, snippet in
            row(snippet, isSelected: index == selectedIndex)
                .id(index)
                .onTapGesture { onPick(snippet) }
        }
    }

    private func row(_ snippet: Snippet, isSelected: Bool) -> some View {
        KeylyRow(trailingWidth: 140, showsSeparator: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: snippet))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fg)
                    .lineLimit(1)
                // EVERY entry has a second line, always with text.
                //
                // It used to be missing for an unnamed snippet (its title is already the start of the
                // text, and a repeat read as a defect) — which made the title spacing wander
                // 49 → 36 → 46pt. An invisible placeholder removed the zigzag but shifted the title
                // 7.5pt away from its own trigger keycap. So an unnamed snippet shows not a
                // repeat but the CONTINUATION: what did not fit into the title.
                Text(secondLine(for: snippet))
                    .font(Theme.Typography.mono(10))
                    .foregroundStyle(Theme.Colors.fgDim)
                    .lineLimit(1)
            }
        } trailing: {
            // Triggers as keycaps: the snippet is invoked by them, so they are more useful than the tail of the text.
            HStack(spacing: 4) {
                ForEach(snippet.triggers.prefix(2), id: \.self) { HotkeyChip(text: $0, kind: .literal) }
            }
        }
        .background(isSelected ? Theme.Colors.accentSoft : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.Colors.accent)
                    .frame(width: 2.5)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
    }

    /// Empty is also a state of the app. A palette with no snippets silently showed
    /// a "no snippets" line: someone pressing the hotkey for the first time saw an empty
    /// window and understood neither what it is for nor what to do next.
    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: snippets.isEmpty ? "text.badge.plus" : "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.Colors.fgDim)
            Text(snippets.isEmpty ? "palette.noSnippets".loc : "palette.nothingFound".loc)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fgMuted)
            if snippets.isEmpty {
                Text("palette.noSnippets.hint".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("palette.createSnippet".loc) { onCreateSnippet?() }
                    .buttonStyle(KeylySecondaryButtonStyle())
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Key hints: the palette is keyboard-only, and without them it is not obvious
    /// that the arrows work and Esc closes it.
    private func hints(hasResults: Bool) -> some View {
        HStack(spacing: Theme.Space.l) {
            // Navigation and insertion are shown ONLY when there is something to choose: with no
            // results both keys do nothing, and promising them would be a lie.
            if hasResults {
                hint("↑↓", "palette.hint.navigate".loc)
                hint("↩", "palette.hint.insert".loc)
            }
            hint("esc", "palette.hint.close".loc)
            Spacer(minLength: 0)
            Text("palette.count".loc(results.count))
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(height: 34)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                // The mono font squeezes key glyphs (`↑↓`, `↩`) just like modifiers: 12.4pt
                // versus 16.1pt and 6.0 versus 10.0. The arrow loses its shaft, `↩` its hook.
                .font(Theme.Typography.keys(10))
                .foregroundStyle(Theme.Colors.fgMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                        .stroke(Theme.Colors.borderStrong, lineWidth: 1)
                )
            Text(text)
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
        }
    }

    // MARK: - Row data

    /// Name if present, otherwise the start of the text (the name is optional).
    private func title(for snippet: Snippet) -> String {
        snippet.displayTitle.loc
    }

    /// Second line of an entry. For a named snippet — the start of the text; for an unnamed one
    /// that start already serves as the title, so take the CONTINUATION, not a repeat.
    private func secondLine(for snippet: Snippet) -> String {
        let full = preview(for: snippet)
        guard (snippet.name ?? "").isEmpty else { return full }
        // Skip as much text as already went into the title.
        let head = title(for: snippet)
        guard full.hasPrefix(head), full.count > head.count else { return full }
        return String(full.dropFirst(head.count)).trimmingCharacters(in: .whitespaces)
    }

    private func preview(for snippet: Snippet) -> String {
        let flat = snippet.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? "palette.emptySnippet".loc : flat
    }

    private func pickSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onPick(results[selectedIndex])
    }
}
