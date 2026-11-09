import UniformTypeIdentifiers
import SwiftUI
import AppKit

extension OnboardingView {
    var appLaunchersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionLabel(text: "launcher.section".loc)
                Spacer()
                Button {
                    pickApplication { url in
                        let newShortcut = AppLaunchShortcut(
                            appPath: url.path,
                            appName: url.deletingPathExtension().lastPathComponent,
                            keyCombo: nil,
                            bookmark: AppLaunchShortcut.makeBookmark(for: url)
                        )
                        appLaunchShortcuts.append(newShortcut)
                        persistAppLaunchShortcuts()
                    }
                } label: {
                    Label("launcher.add".loc, systemImage: "plus")
                        .font(Theme.Typography.caption)
                }
                .buttonStyle(.borderless)
                .tint(Theme.Colors.fgMuted)  // lime stays rare — a routine "add" is not a CTA
            }

            // Third way to add — paste a link. The file picker cannot pick a link at all, yet
            // a launcher target can be a link: "open a playlist" is the same one-key scenario
            // as "open an app".
            linkField

            if appLaunchShortcuts.isEmpty {
                Text("launcher.empty".loc)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.l)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.Colors.border)
                    )
            } else {
                // Same drag-and-drop mechanism as snippets (see ReorderDropDelegate).
                // There used to be List + onMove here — visibly different behavior for the same
                // action.
                VStack(spacing: 10) {
                    ForEach(Array(appLaunchShortcuts.enumerated()), id: \.element.id) { index, shortcut in
                        appLauncherRow(for: index)
                            // The drag source is the WHOLE row (see keylyDragSource).
                            .keylyDragSource(id: shortcut.id, draggingId: $draggingShortcutId)
                            .keylyReorderTarget(index: index,
                                                id: shortcut.id,
                                                items: $appLaunchShortcuts,
                                                draggingId: $draggingShortcutId,
                                                onReorder: persistAppLaunchShortcuts)
                    }
                }

            }
        }
        // Drop is accepted on the WHOLE section, not just empty space: a list of four
        // targets leaves almost no empty space, and a drop zone tied to it would only
        // work for people with no targets yet.
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            acceptDroppedTargets(providers)
        }
    }

    /// "Paste a link" field. The value is validated BEFORE adding: a string that cannot be
    /// opened would land in the list as a working-looking target and do nothing when the
    /// hotkey is pressed.
    private var linkField: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "link")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.fgDim)
            // A field with its own border and a short example placeholder: inside the shared
            // hint line it was indistinguishable from static text, and the third way to add
            // simply went unnoticed.
            TextField("launcher.link.placeholder".loc, text: $launcherLinkDraft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: Theme.Size.control - 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Colors.bg)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1))
                )
                .onSubmit { addLinkTarget() }
            Button("launcher.link.add".loc) { addLinkTarget() }
                .buttonStyle(.borderless)
                .tint(Theme.Colors.accent)
                .disabled(LaunchTarget.resolve(launcherLinkDraft) == nil)
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

    private func addLinkTarget() {
        let raw = launcherLinkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LaunchTarget.resolve(raw) != nil else { return }
        appLaunchShortcuts.append(AppLaunchShortcut(appPath: raw,
                                                    appName: LaunchTarget.suggestedName(for: raw),
                                                    keyCombo: nil))
        persistAppLaunchShortcuts()
        launcherLinkDraft = ""
    }

    /// Dragging an item from Finder straight into the list. The second way to add is not
    /// cosmetic: the app is usually already visible in Finder or the Dock, and "drag it" is
    /// shorter than "open picker → find folder → select".
    func acceptDroppedTargets(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    // No duplicates: a second row for the same app silently steals the first one's
                    // hotkey on the next registration.
                    guard !appLaunchShortcuts.contains(where: { $0.appPath == url.path }) else { return }
                    appLaunchShortcuts.append(AppLaunchShortcut(
                        appPath: url.path,
                        appName: LaunchTarget.suggestedName(for: url.path),
                        keyCombo: nil,
                        bookmark: AppLaunchShortcut.makeBookmark(for: url)))
                    persistAppLaunchShortcuts()
                }
            }
        }
        return accepted
    }

    /// Target icon side. Square: an app icon is square by nature, but its height used to come
    /// from `Theme.Size.control` with width 32 — the image was stretched into a rectangle, and
    /// the list looked squashed.
    static var launcherIconSize: CGFloat { 42 }

    func appLauncherRow(for index: Int) -> some View {
        let shortcut = appLaunchShortcuts[index]
        let icon = NSWorkspace.shared.icon(forFile: shortcut.appPath)
        return HStack(spacing: 10) {
            KeylyDragHandle()
            // SQUARE. An app icon is square by nature, but its height used to come from
            // `Theme.Size.control` (38) with width 32 — `.resizable()` stretched it into a
            // rectangle, and the whole list looked squashed horizontally. The control size
            // token does not apply here: it is about input field height, not image
            // proportions.
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.launcherIconSize, height: Self.launcherIconSize)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                // The name is editable in place: people call "Google Chrome" "browser", and
                // renaming must be easier than deleting and re-adding — the only path that
                // existed before.
                TextField("", text: Binding(
                    get: { appLaunchShortcuts[index].appName },
                    set: { newValue in
                        appLaunchShortcuts[index].appName = newValue.isEmpty
                            ? LaunchTarget.suggestedName(for: appLaunchShortcuts[index].appPath)
                            : newValue
                        persistAppLaunchShortcuts()
                    }
                ))
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fg)
                // The path is noise: name + icon identify the app. The full path is in the tooltip.
                //
                // EVERY entry has this line, always with real text.
                //
                // Earlier it was missing for standard /Applications, so the name in those rows
                // sat at the card center while in rows with a path it sat higher: measured
                // insets were 26/19/26/19pt. The first fix made the line invisible — the zigzag
                // went away but something WORSE appeared: the name moved up while the icon and
                // hotkey field stayed centered, and the name's center drifted 7.5pt from its own
                // hotkey. That fixed the "eye down the column" axis and broke the "eye right
                // from name to its key" axis.
                //
                // An invisible placeholder is no solution: it gives a two-line structure but
                // strips the second line of meaning. A real caption gives both.
                Text(folderCaption(shortcut.appPath))
                    .font(Theme.Typography.mono(10))
                    .foregroundStyle(Theme.Colors.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(shortcut.appPath)

            Spacer()

            KeylyHotKeyField(keyCombo: hotKeyBinding(
                fieldID: HotKeyFieldID.app(shortcut.id),
                get: { appLaunchShortcuts[index].keyCombo },
                ignoringAppID: shortcut.id,
                assign: { combo in
                    appLaunchShortcuts[index].keyCombo = combo
                    persistAppLaunchShortcuts()
                }
            ), width: KeylyHotKeyField.Size.inRow,
               conflict: hotKeyConflictBanner(HotKeyFieldID.app(shortcut.id)),
               fieldID: HotKeyFieldID.app(shortcut.id),
               // ✕ was not drawn here at all: `onClear` was not passed. This is exactly the
               // screen where four bare keys can sit in a row — and there was nothing to clear
               // a combo with; the nearest button deleted the APP itself.
               onClear: {
                   appLaunchShortcuts[index].keyCombo = nil
                   persistAppLaunchShortcuts()
               },
               // The field sits at the RIGHT edge of the row — pin it there, otherwise an
               // appearing message drags it left from under the cursor.
               fieldEdge: .trailing)

            Button {
                // Confirmation: the trash button sat right in the row and deleted instantly —
                // one mis-click and the configured combo vanished along with its target.
                let alert = NSAlert()
                alert.messageText = "launcher.delete.title".loc(shortcut.appName)
                alert.informativeText = "launcher.delete.body".loc
                alert.addButton(withTitle: "common.cancel".loc)
                alert.addButton(withTitle: "common.delete".loc)
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                appLaunchShortcuts.remove(at: index)
                persistAppLaunchShortcuts()
            } label: {
                Image(systemName: "trash")
                    .iconHitArea("launcher.delete.icon".loc)
            }
            .buttonStyle(.borderless)
            // Hover tooltip. `iconHitArea` only provides `accessibilityLabel` — audible to
            // VoiceOver, invisible to the eye. The trash sits 18pt from the "clear hotkey" ✕,
            // both unlabeled: hovering is the only way to tell which is which BEFORE
            // clicking.
            .help("launcher.delete.help".loc(shortcut.appName))
            .foregroundColor(Theme.Colors.fgDim)  // quiet, not 4 red spots at rest
        }
        // Row height follows the TALLEST content. The icon (42pt) is taller than the hotkey
        // field (`Size.control`, 38pt), and a row pinned to 38 would declare a height it does
        // not have: content overflows the declared frame and eats the card padding.
        .frame(height: max(Theme.Size.control, Self.launcherIconSize))
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Colors.border, lineWidth: 1)
        )
    }

    /// Caption under the name: where the app lives. The full path stays in the row tooltip.
    ///
    /// For standard /Applications we write "Applications" instead of hiding the line: the
    /// path is no news there, but the row STRUCTURE must be the same for all entries —
    /// otherwise the list either zigzags or misaligns with the trailing items (both happened).
    private func folderCaption(_ path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        if folder == "/Applications" { return "launcher.folder.applications".loc }
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    /// Reads and writes go through `AppLauncherStore` — the ONLY home of this data.
    ///
    /// The screen used to decode the raw array from `UserDefaults` directly, while the store
    /// wrote an envelope with a schema and a backup. While nobody touched the store, the
    /// screen worked; as soon as any code accessed `AppLauncherStore.shared`, the data was
    /// rewritten as an envelope and the screen could no longer read it: the target list went
    /// EMPTY although everything was in storage. Two readers of the same data always diverge.
    func reloadAppLaunchShortcutsFromDefaults() {
        appLaunchShortcuts = AppLauncherStore.shared.shortcuts
    }

    func persistAppLaunchShortcuts() {
        AppLauncherStore.shared.replace(all: appLaunchShortcuts)
    }

    func pickApplication(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                completion(url)
            }
        }
    }
}
