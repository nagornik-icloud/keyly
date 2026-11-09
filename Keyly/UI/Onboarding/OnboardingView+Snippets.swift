import SwiftUI
import UniformTypeIdentifiers
import AppKit

extension OnboardingView {
    /// Snippets screen — three panes: sidebar + list + editor.
    ///
    /// It used to be a single-column accordion: to add text a card had to be expanded first,
    /// and comparing two snippets meant expanding both and losing sight of them. The snippet
    /// text is the main object of the screen, and it gets the full height, not 80pt inside an
    /// expanded card.
    var snippetsContent: some View {
        HStack(spacing: 0) {
            snippetListPane
                .frame(width: 260)
            Divider().overlay(Theme.Colors.border)
            snippetEditorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Do not reload from the store while editing is in progress.
            if expandedSnippetId == nil {
                snippets = SnippetStore.load()
            }
            // Open the first snippet right away: an empty right pane on a screen with a
            // list on the left reads as "the editor failed to load", not as an invitation
            // to choose. The selection changes with one click anyway.
            if expandedSnippetId == nil { expandedSnippetId = snippets.first?.id }
        }
    }

    // MARK: - Left pane: list

    private var snippetListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Text("snippets.title".loc)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fg)
                Spacer(minLength: 0)
                Button {
                    let created = createSnippet()
                    expandedSnippetId = created.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .iconHitArea("snippets.add".loc)
                }
                .buttonStyle(.borderless)
                .tint(Theme.Colors.accent)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)

            // Search ABOVE the list. Ranking is SnippetSearch.rank, the same type as in the
            // palette: two independent searches over the same data would diverge in order,
            // and people would get used to different behavior.
            searchField
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.m)

            // The palette is the second way to insert a snippet, and the app used to mention it
            // NOWHERE: neither here nor on "Overview". People assigned it a combo in settings
            // without ever seeing what it is — and it cannot be opened other than by hotkey.
            Button {
                SnippetPaletteController.shared.toggle()
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.fgDim)
                    Text("snippets.palette.hint".loc(paletteComboText))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("snippets.palette.help".loc)
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.m)

            Divider().overlay(Theme.Colors.border)

            if snippets.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array($snippets.enumerated()), id: \.element.id) { index, $snippet in
                            if matchesQuery(snippet) {
                                // Drag-and-drop is DISABLED while searching: only part of the list
                                // is visible, and "to second place" means second among the VISIBLE
                                // ones — while a different order would be saved.
                                if isSearching {
                                    snippetListRow(snippet: $snippet)
                                } else {
                                    snippetListRow(snippet: $snippet)
                                        .keylyReorderTarget(index: index,
                                                            id: snippet.id,
                                                            items: $snippets,
                                                            draggingId: $draggingSnippetId,
                                                            onReorder: persistSnippets)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The current palette combo or the word "not assigned": if the user cleared the hotkey,
    /// the hint "press ⌥⌘S" would be a plain lie — they have no other way to open the palette.
    private var paletteComboText: String {
        decodeCombo(customHotKeyPaletteData)?.description ?? "overview.chip.unset".loc
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.fgDim)
            TextField("snippets.search".loc, text: $snippetQuery)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
            if !snippetQuery.isEmpty {
                Button {
                    snippetQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.fgDim)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.Size.control)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1))
        )
    }

    private var emptyListState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.Colors.fgDim)
            Text("snippets.empty.title".loc)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fgMuted)
            Text("snippets.empty.hint".loc)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, 48)
    }

    /// List row: name or start of the text in large type, trigger small on the second line.
    private func snippetListRow(snippet: Binding<Snippet>) -> some View {
        let s = snippet.wrappedValue
        let isSelected = expandedSnippetId == s.id
        return HStack(spacing: 8) {
            // The handle is the ONLY drag source: the whole row contains a toggle and a
            // menu, and a drag started from it went anywhere but into reordering.
            KeylyDragHandle()
                .keylyDragSource(id: s.id, draggingId: $draggingSnippetId)
                .opacity(isSearching ? 0.25 : 1)
                .disabled(isSearching)
                .help(isSearching ? "snippets.reorder.disabledBySearch".loc : "reorder.handle".loc)

            Button {
                expandedSnippetId = s.id
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(collapsedLabel(for: s))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.Colors.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        if let line = triggerLine(for: s) {
                            Text(line)
                                .font(Theme.Typography.mono(10))
                                .foregroundStyle(Theme.Colors.fgDim)
                                .lineLimit(1)
                        }
                        if s.hotKey != nil {
                            Image(systemName: "keyboard")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.fgDim)
                                .help("snippets.row.hasHotkey".loc)
                        }
                    }
                }
                .opacity(s.isEnabled ? 1 : 0.45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keyly.snippet.\(s.id).open")

            Toggle("", isOn: snippet.isEnabled)
                .toggleStyle(KeylyToggleStyle())
                .labelsHidden()
                .controlSize(.small)
                .help(s.isEnabled ? "snippets.row.toggleOn".loc : "snippets.row.toggleOff".loc)
                .accessibilityIdentifier("keyly.snippet.\(s.id).enabled")
                .onChange(of: snippet.wrappedValue.isEnabled) { persistSnippets() }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, 9)
        .background(
            // Selection is a full-width row fill, as in macOS lists.
            isSelected ? Theme.Colors.surfaceHover : Color.clear
        )
        // Hover only on a NON-selected row: under the selection the highlight is unreadable,
        // but it makes it look as if the selection followed the cursor.
        .modifier(HoverIfNotSelected(isSelected: isSelected))
        .contentShape(Rectangle())
    }

    // MARK: - Right pane: document editor


    @ViewBuilder
    private var snippetEditorPane: some View {
        if let id = expandedSnippetId,
           let index = snippets.firstIndex(where: { $0.id == id }) {
            snippetEditor(snippet: $snippets[index])
                .id(id)
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.Colors.fgDim)
                Text(snippets.isEmpty ? "snippets.editor.emptyNoSnippets".loc
                                      : "snippets.editor.emptyPickOne".loc)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Single snippet editor

    /// "Document with a pinned bottom": the text takes the full height, the trigger block is
    /// pinned at the bottom. The text is the main object of the screen and must not share its
    /// height with settings touched once in a lifetime.
    private func snippetEditor(snippet: Binding<Snippet>) -> some View {
        let snippetId = snippet.wrappedValue.id
        // The text field height is computed FROM THE AVAILABLE space, not taken from its own
        // ideal. `TextEditor` reports upward a height for all possible text (measured:
        // 1257pt), and the pane grew taller than the window: the trigger block slid below the
        // bottom edge, and snapshot capture refused to take a frame one and a half screens tall.
        // `GeometryReader` takes EXACTLY what is offered and asks for nothing more.
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                editorHeader(snippet: snippet)
                Divider().overlay(Theme.Colors.border)
                placeholderChips(snippet: snippet)
                contentEditor(snippet: snippet)
                    .frame(maxHeight: .infinity)
                Divider().overlay(Theme.Colors.border)
                triggerFooter(snippet: snippet, snippetId: snippetId)
            }
            // Height is PINNED to the available space. Without it `TextEditor` reports upward a
            // height for all possible text (measured: 1257pt), the pane grows taller than the
            // window, and the trigger block slides below the bottom edge. `GeometryReader` takes
            // exactly what is offered, and the text field takes the rest.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onChange(of: snippet.wrappedValue) { persistSnippets() }
    }

    private func editorHeader(snippet: Binding<Snippet>) -> some View {
        let s = snippet.wrappedValue
        return HStack(spacing: Theme.Space.m) {
            // The name is optional, so this is an unlabeled field with a placeholder,
            // not a required form row.
            TextField("snippets.editor.namePlaceholder".loc, text: Binding(
                get: { snippet.wrappedValue.name ?? "" },
                set: { snippet.wrappedValue.name = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.Colors.fg)

            Toggle("", isOn: snippet.isEnabled)
                .toggleStyle(KeylyToggleStyle())
                .labelsHidden()
                .controlSize(.small)
                .help(s.isEnabled ? "snippets.row.toggleOn".loc : "snippets.row.toggleOff".loc)

            Menu {
                Button("snippets.menu.duplicate".loc) { duplicateSnippet(id: s.id) }
                Divider()
                Button("common.delete".loc, role: .destructive) { confirmDeleteSnippet(id: s.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.Colors.fgDim)
                    .font(.caption)
                    .iconHitArea("snippets.menu.label".loc)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    /// Placeholder chip buttons ABOVE the text field.
    private func placeholderChips(snippet: Binding<Snippet>) -> some View {
        HStack(spacing: 6) {
            ForEach(SnippetPlaceholders.Token.allCases, id: \.rawValue) { token in
                let spelling = SnippetPlaceholders.Token.preferred(
                    token, language: Locale.preferredLanguages.first ?? "en")
                Button {
                    snippet.wrappedValue.content += spelling
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: token.icon).font(.system(size: 9))
                        Text(token.titleKey.loc).font(Theme.Typography.mono(10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Colors.surfaceHover))
                    .foregroundStyle(Theme.Colors.fgMuted)
                }
                .buttonStyle(.plain)
                .help("snippets.placeholder.hint".loc(spelling))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
    }

    private func contentEditor(snippet: Binding<Snippet>) -> some View {
        TextEditor(text: snippet.content)
            .font(Theme.Typography.body)
            .scrollContentBackground(.hidden)
            .padding(Theme.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surfaceHover)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1))
            )
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.m)
            .frame(maxWidth: .infinity)
    }

    /// Pinned bottom "trigger" block: triggers, timing and hotkey.
    private func triggerFooter(snippet: Binding<Snippet>, snippetId: UUID) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel(text: "snippets.editor.triggers".loc)
                    TriggerTokenField(
                        triggers: snippet.triggers,
                        validate: { candidate in
                            // Overlaps are REJECTED at input instead of being flagged after the fact:
                            // while overlaps are possible, firing a short trigger has to be delayed,
                            // and the behavior becomes unpredictable.
                            guard SnippetSearch.triggerIsAllowed(candidate, existing: snippets,
                                                                 excluding: snippetId) else {
                                return "snippets.trigger.overlaps".loc(candidate)
                            }
                            return nil
                        }
                    )
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel(text: "snippets.editor.hotkey".loc)
                    KeylyHotKeyField(keyCombo: hotKeyBinding(
                        fieldID: HotKeyFieldID.snippet(snippetId),
                        get: { snippet.wrappedValue.hotKey },
                        ignoringSnippetId: snippetId,
                        assign: { combo in snippet.wrappedValue.hotKey = combo }
                    ), width: KeylyHotKeyField.Size.inRow,
                       conflict: hotKeyConflictBanner(HotKeyFieldID.snippet(snippetId)),
                       fieldID: HotKeyFieldID.snippet(snippetId),
                       // As on the launcher: without `onClear` there was no clear button, and an assigned
                       // hotkey could only be removed by clicking the field and pressing Esc, which is documented nowhere.
                       onClear: { snippet.wrappedValue.hotKey = nil },
                       // The message is placed by the FOOTER, not the column: inside the column it
                       // stretched it to its 360pt and took 120pt away from the trigger field
                       // (measured on a pair of snippet-footer-* frames).
                       rendersBareKeyNotice: false)
                }
            }

            // The bare-key warning goes UNDER the row, across the full footer width: inside the
            // column it took 120pt away from the trigger field.
            //
            // But the wide row brought its own problem: it sits under the TRIGGERS column while
            // belonging to the HOTKEY column, which is 850px to the right. The user reads "«]»
            // will stop typing" under a field with the "@@" trigger and doesn't see what "]"
            // has to do with it. So the message NAMES its field — the target is not inferred from
            // position, it is spelled out.
            if let message = BareKeyNoticeStatus.shared.message(
                fieldID: HotKeyFieldID.snippet(snippetId),
                combo: snippet.wrappedValue.hotKey) {
                BareKeyNoticeView(message: "snippets.editor.hotkey.notice".loc(message))
            }

            // The conflict validator is wired to the editor: the app used to silently allow
            // two snippets with the same trigger and prefix overlaps — "addr" shadows
            // "address", and the user simply never finishes typing the longer one.
            ForEach(triggerProblems(for: snippet.wrappedValue), id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Firing moment is PER snippet. "@@email" naturally fires immediately,
            // "address" only once the word is complete: otherwise it would fire inside
            // "addressee".
            //
            // Segments, not a pair of captioned cards: the cards needed ~280pt in a block
            // that is PINNED TO THE BOTTOM, and took it from the text — the main object of
            // the screen. The explanation remains, as one line under the selected mode.
            if !snippet.wrappedValue.triggers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    // Our own `KeylySegmented`, not the system `Picker(.segmented)`.
                    //
                    // Measured: in the system one the selected segment was #3B3B3B on
                    // #1F1F1F — a delta of 28 versus 214 for our component on the neighboring screen.
                    // So on this screen you simply could NOT SEE which trigger mode was on,
                    // although exactly this choice decides whether the snippet fires inside a word.
                    // Plus the same control looked two different ways across the app.
                    KeylySegmented(
                        selection: Binding(
                            get: { snippet.wrappedValue.triggerMode },
                            set: { snippet.wrappedValue.triggerMode = $0; persistSnippets() }
                        ),
                        options: [(.afterSeparator, "snippets.mode.afterSeparator".loc),
                                  (.immediate, "snippets.mode.immediate".loc)]
                    )
                    // FULL column width, like the other footer controls.
                    //
                    // With a fixed 360pt the footer's right edge was a staircase: the hint
                    // reached 1967, the row with ✕ 1916, the segmented control 1762 — a 102pt spread. On
                    // the neighboring screen the same control spans the full width; the same
                    // element must not be stretched in one place and hugging its content in another.
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(snippet.wrappedValue.triggerMode == .afterSeparator
                         ? "snippets.mode.afterSeparator.hint".loc
                         : "snippets.mode.immediate.hint".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.Colors.surface)
    }

    /// Trigger problems of THIS snippet: conflicts with others and violations of the
    /// trigger's own rules.
    ///
    /// Shown in the editor, not only on save: snippets are saved on the fly, and
    /// "you'll find out on save" here would mean "you'll never find out".
    func triggerProblems(for snippet: Snippet) -> [String] {
        var out: [String] = []

        // The trigger's own rules: empty and single-character ones don't work, a space
        // breaks the typed sequence, and such a trigger will NEVER fire — staying silent about it is not acceptable.
        for t in snippet.triggers where !t.isEmpty {
            if t.count < 2 {
                out.append("snippets.warn.tooShort".loc(t))
            } else if t.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                out.append("snippets.warn.hasSpace".loc(t))
            }
        }

        // Conflicts with OTHER snippets. Computed over the whole list, otherwise an overlap
        // is visible from one side only.
        for c in SnippetSearch.triggerConflicts(in: snippets) {
            guard snippet.triggers.contains(where: { $0.lowercased() == c.trigger }) else { continue }
            out.append(c.isExactDuplicate
                       ? "snippets.warn.duplicate".loc(c.trigger)
                       : "snippets.warn.overlap".loc(c.trigger, c.conflictsWith))
        }
        return out
    }

    /// List row title: the name if present, otherwise the start of the text — via
    /// `Snippet.displayTitle`, the only home of this fallback. The trigger goes SEPARATELY and small,
    /// not glued with an arrow: the row used to look like `"" → address` because the trigger
    /// was printed as is and there was no name at all — and a punctuation trigger (literally two
    /// quotes) read as empty space.
    private func collapsedLabel(for s: Snippet) -> String { s.displayTitle.loc }

    /// Triggers on the second line, small mono. Empty → no line at all, not "(empty)".
    private func triggerLine(for s: Snippet) -> String? {
        let triggers = s.triggers.filter { !$0.isEmpty }
        return triggers.isEmpty ? nil : triggers.joined(separator: " · ")
    }

    // MARK: - Actions

    @discardableResult
    func createSnippet() -> Snippet {
        // The name is NOT assigned automatically: it is optional, and "New snippet" is a
        // name the user did not choose. The list shows the start of the text instead, and as
        // soon as text appears the row becomes meaningful by itself.
        let snippet = Snippet(name: nil, content: "")
        snippets.append(snippet)
        // Persist right away — otherwise a new snippet lived only in memory and was lost on
        // leaving the screen / reloading (one of the causes of "snippets don't work").
        persistSnippets()
        return snippet
    }

    /// Duplicate — WITHOUT triggers and without a hotkey.
    ///
    /// A copy with the same triggers is born invalid (exact duplicate) and unsaveable,
    /// i.e. the action would lead to a dead end. Same reason for the hotkey: two snippets
    /// on one combo is a conflict the user would not learn about here.
    @discardableResult
    func duplicateSnippet(id: UUID) -> Snippet? {
        guard let source = snippets.first(where: { $0.id == id }) else { return nil }
        let copy = Snippet(name: source.name.map { "snippets.copySuffix".loc($0) },
                           content: source.content,
                           hotKey: nil,
                           triggers: [],
                           isEnabled: source.isEnabled)
        snippets.append(copy)
        persistSnippets()
        expandedSnippetId = copy.id
        return copy
    }

    func confirmDeleteSnippet(id: UUID) {
        let alert = NSAlert()
        alert.messageText = "snippets.delete.title".loc
        alert.informativeText = "snippets.delete.body".loc
        // "Cancel" FIRST — it becomes the default button, so Enter cancels rather than
        // deletes. Previously in all three alerts of the app Enter meant "Delete": a habit
        // of clicking through dialogs would cost the user a configured snippet, module
        // or key.
        alert.addButton(withTitle: "common.cancel".loc)
        alert.addButton(withTitle: "common.delete".loc)
        if alert.runModal() == .alertSecondButtonReturn {
            if expandedSnippetId == id { expandedSnippetId = nil }
            snippetBeforeEdit.removeValue(forKey: id)
            unsavedSnippetIds.remove(id)
            snippets.removeAll { $0.id == id }
            persistSnippets()
        }
    }

    /// Whether a search is in progress. A separate property because it affects not only
    /// the filter but also whether drag-and-drop is available.
    ///
    /// Filtering goes through `SnippetSearch.rank`, not a custom comparison: the palette
    /// searches with the same type, and two independent searches over the same data would
    /// diverge in order and rules.
    var isSearching: Bool {
        !snippetQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matchesQuery(_ snippet: Snippet) -> Bool {
        let query = snippetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return SnippetSearch.score(snippet, query: query.lowercased()) != nil
    }

    func persistSnippets() {
        // Empty triggers are dropped HERE, not in the UI: they never fire, but remain in the
        // data from the old editor (where "＋" added an empty field) and show up in the list
        // row as quotes instead of a trigger.
        for index in snippets.indices {
            let cleaned = snippets[index].triggers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleaned != snippets[index].triggers { snippets[index].triggers = cleaned }
        }
        SnippetStore.save(snippets)
    }
}
