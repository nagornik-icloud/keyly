import Foundation

/// Collecting cheatsheet rows: what is actually assigned right now.
///
/// Separate from the view because the source is four different stores, and they must be collected
/// THE SAME WAY as the Overview shows them: two builds of one list would drift apart, and the
/// cheatsheet would promise a shortcut that doesn't exist.
@MainActor
enum CheatsheetRows {

    static func build() -> [CheatsheetView.Row] {
        var rows: [CheatsheetView.Row] = []

        func add(_ key: String, _ titleKey: String) {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return }
            rows.append(.init(combo: combo.description, title: titleKey.loc))
        }

        // Built-in modules — only ENABLED ones: a disabled module doesn't react to its hotkey,
        // and promising it in the cheatsheet would be a lie.
        if UserDefaults.standard.object(forKey: SettingsKeys.layoutEnabled) as? Bool ?? true {
            add(SettingsKeys.layoutHotKey, "module.layoutSwitch.title")
        }
        if UserDefaults.standard.object(forKey: SettingsKeys.errorFixEnabled) as? Bool ?? true {
            add(SettingsKeys.errorFixHotKey, "module.errorFix.title")
        }
        if UserDefaults.standard.object(forKey: SettingsKeys.voiceEnabled) as? Bool ?? true {
            add(SettingsKeys.voiceHotKey, "module.voiceToText.title")
        }
        add(SettingsKeys.undoHotKey, "menu.undo")
        add(SettingsKeys.snippetPaletteHotKey, "cheatsheet.palette")
        // The cheatsheet didn't list its OWN shortcut: the window answering "what have I assigned"
        // was silent about exactly the combination that opened it. It is also the only place
        // where ⌥⌘/ is shown to the user at all.
        add(SettingsKeys.cheatsheetHotKey, "settings.globalHotkeys.cheatsheet")

        for module in CustomModuleStore.load() where module.isEnabled {
            if let combo = module.hotKey {
                rows.append(.init(combo: combo.description, title: module.name))
            }
        }
        for shortcut in AppLauncherStore.shared.shortcuts {
            if let combo = shortcut.keyCombo {
                rows.append(.init(combo: combo.description, title: shortcut.displayName))
            }
        }
        for snippet in SnippetStore.load() where snippet.isEnabled {
            if let combo = snippet.hotKey {
                rows.append(.init(combo: combo.description, title: snippet.displayTitle.loc))
            }
        }
        return rows
    }
}
