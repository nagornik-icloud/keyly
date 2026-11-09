import Foundation

/// The full list of assigned shortcuts — ONE for the whole app.
///
/// Hotkeys live in four stores and are configured on four screens, so "what's taken?" used to
/// have no answer anywhere: the cheatsheet built its own list, Overview its own, and nobody had
/// the full picture. The inventory is built HERE, and the surfaces (cheatsheet, "All hotkeys"
/// screen) only display it differently.
@MainActor
enum HotKeyInventory {

    /// Where the shortcut is configured — so the "All hotkeys" screen can link to where it's
    /// changed. A "taken" row with no path to the setting forces a manual search.
    enum Source: Equatable {
        case module(HotKeyConflictOwner.Builtin)
        case undo
        case snippetPalette
        case cheatsheet
        case customModule(id: UUID)
        case app(id: UUID)
        case snippet(id: UUID)

        /// Label key for "configured in".
        var placeKey: String {
            switch self {
            // The section, not the module name: the name is already on the first line, and the
            // second used to repeat it word for word — "Voice / Voice".
            case .module:                return "sidebar.modules"
            case .undo, .snippetPalette, .cheatsheet: return "sidebar.settings"
            case .customModule:          return "hotkeys.place.customModule"
            case .app:                   return "module.appLauncher.title"
            case .snippet:               return "sidebar.snippets"
            }
        }
    }

    struct Entry: Identifiable {
        var id: String { fieldID }
        let fieldID: String
        let combo: KeyCombo
        /// Ready action label: snippet and app names are user-defined and can't have a catalog
        /// key.
        let title: String
        let source: Source
        /// A disabled module/snippet doesn't react to its hotkey. Such rows are still shown —
        /// the shortcut is still TAKEN and can't be assigned twice — but marked.
        let isActive: Bool
    }

    static func build() -> [Entry] {
        var entries: [Entry] = []

        func decode(_ key: String) -> KeyCombo? {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(KeyCombo.self, from: data)
        }
        func enabled(_ key: String) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        func add(_ key: String, _ fieldID: String, _ titleKey: String,
                 _ source: Source, active: Bool) {
            guard let combo = decode(key) else { return }
            entries.append(.init(fieldID: fieldID, combo: combo, title: titleKey.loc,
                                 source: source, isActive: active))
        }

        add(SettingsKeys.layoutHotKey, HotKeyFieldID.layout, "module.layoutSwitch.title",
            .module(.layoutSwitch), active: enabled(SettingsKeys.layoutEnabled))
        add(SettingsKeys.errorFixHotKey, HotKeyFieldID.errorFix, "module.errorFix.title",
            .module(.errorFix), active: enabled(SettingsKeys.errorFixEnabled))
        add(SettingsKeys.voiceHotKey, HotKeyFieldID.voice, "module.voiceToText.title",
            .module(.voiceToText), active: enabled(SettingsKeys.voiceEnabled))
        add(SettingsKeys.undoHotKey, HotKeyFieldID.undo, "menu.undo", .undo, active: true)
        // Without this line `duplicates()` could never see a duplicate of ⌥⌘/ — the "ONE
        // inventory for the whole app" contract promised completeness that wasn't there.
        add(SettingsKeys.cheatsheetHotKey, HotKeyFieldID.cheatsheet,
            "settings.globalHotkeys.cheatsheet", .cheatsheet, active: true)
        add(SettingsKeys.snippetPaletteHotKey, HotKeyFieldID.snippetPalette,
            "cheatsheet.palette", .snippetPalette, active: true)

        for module in CustomModuleStore.load() {
            guard let combo = module.hotKey else { continue }
            entries.append(.init(fieldID: HotKeyFieldID.customModule(module.id), combo: combo,
                                 title: module.name, source: .customModule(id: module.id),
                                 isActive: module.isEnabled))
        }
        for shortcut in AppLauncherStore.shared.shortcuts {
            guard let combo = shortcut.keyCombo else { continue }
            entries.append(.init(fieldID: HotKeyFieldID.app(shortcut.id), combo: combo,
                                 title: shortcut.displayName, source: .app(id: shortcut.id),
                                 isActive: enabled(SettingsKeys.appLauncherEnabled)))
        }
        for snippet in SnippetStore.load() {
            guard let combo = snippet.hotKey else { continue }
            entries.append(.init(fieldID: HotKeyFieldID.snippet(snippet.id), combo: combo,
                                 title: snippet.displayTitle.loc, source: .snippet(id: snippet.id),
                                 isActive: snippet.isEnabled))
        }
        return entries
    }

    /// Shortcuts assigned more than once. This can't happen normally (conflicts are checked on
    /// recording), but pairs arrive via settings import and module reset — and then whoever
    /// registered first wins, with no explanation.
    static func duplicates(in entries: [Entry]) -> Set<String> {
        var seen: [KeyCombo: [String]] = [:]
        for entry in entries where entry.isActive {
            seen[entry.combo, default: []].append(entry.fieldID)
        }
        return Set(seen.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}
