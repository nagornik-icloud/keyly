import AppKit
import Foundation

/// Export and import of settings as a file.
///
/// Import REPLACES everything — it does not merge. Merging two settings sets raises questions
/// with no good answer ("two snippets with the same trigger — which wins?"), and the user ends
/// up not knowing what they have.
///
/// That's why an automatic backup is made before replacing: an irreversible action must have
/// a way back, and that way must not depend on whether the user thought to make a copy first.
@MainActor
enum SettingsBackupService {

    static weak var badgePresenter: BadgePresenting?

    /// Where the automatic pre-import backup goes.
    static var autoBackupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keyly", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings-backup.keyly.json")
    }

    // MARK: - Export

    static func makeBundle() -> SettingsBundle {
        let defaults = UserDefaults.standard
        var flat: [String: String] = [:]
        for key in SettingsBundle.exportedDefaultKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            flat[key] = SettingsBundle.encodeValue(value, forKey: key)
        }
        return SettingsBundle(
            schemaVersion: SettingsBundle.currentSchema,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            exportedAt: Date(),
            snippets: SnippetStore.load(),
            customModules: CustomModuleStore.load(),
            appLaunchShortcuts: AppLauncherStore.shared.shortcuts,
            defaults: flat
        )
    }

    static func write(_ bundle: SettingsBundle, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(bundle).write(to: url, options: .atomic)
        Log.info(.app, "Экспорт настроек: сниппетов \(bundle.snippets.count), модулей \(bundle.customModules.count), целей \(bundle.appLaunchShortcuts.count)")
    }

    // MARK: - Import

    enum ImportOutcome: Equatable, Error {
        case replaced(snippets: Int, modules: Int, shortcuts: Int)
        case refused(SettingsBundle.ImportRefusal)
        case unreadable
        /// The safety copy of the current settings could not be written — nothing was changed.
        case backupFailed
    }

    static func read(from url: URL) -> Result<SettingsBundle, ImportOutcome> {
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(SettingsBundle.self, from: data) else {
            return .failure(.unreadable)
        }
        if let refusal = SettingsBundle.refusal(forSchema: bundle.schemaVersion) {
            return .failure(.refused(refusal))
        }
        return .success(bundle)
    }

    /// Replaces settings with the file's contents. The backup of the current state is made
    /// BEFORE the first write — otherwise there would be nothing to revert to.
    /// `backingUp: false` is only for reverting to that very backup: writing a new one
    /// first would overwrite the copy being restored.
    @discardableResult
    static func apply(_ bundle: SettingsBundle, backingUp: Bool = true) -> ImportOutcome {
        if backingUp {
            do {
                try write(makeBundle(), to: autoBackupURL)
            } catch {
                Log.error(.app, "Import cancelled: safety backup could not be written")
                return .backupFailed
            }
        }

        _ = SnippetStore.save(bundle.snippets)
        _ = CustomModuleStore.save(bundle.customModules)
        AppLauncherStore.shared.replace(all: bundle.appLaunchShortcuts)

        let defaults = UserDefaults.standard
        for key in SettingsBundle.exportedDefaultKeys {
            guard let value = bundle.defaults[key] else {
                defaults.removeObject(forKey: key)
                continue
            }
            guard let typed = SettingsBundle.decodeValue(value, forKey: key) else {
                Log.warn(.app, "Import: unreadable value for \(key), kept the current one")
                continue
            }
            defaults.set(typed, forKey: key)
        }

        // Module links to API keys are cleared: the file has no keys, and a saved link would
        // point to a key from another machine.
        // Reverting to our own backup restores this Mac's state, where the links were valid.
        if backingUp { APIKeyStore.shared.clearAllSelections() }

        NotificationCenter.default.post(name: .snippetsChanged, object: nil)
        NotificationCenter.default.post(name: .customAIModulesChanged, object: nil)
        NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
        NotificationCenter.default.post(name: .uiVisibilityChanged, object: nil)

        Log.info(.app, "Импорт настроек применён, прежнее состояние сохранено в бэкап")
        return .replaced(snippets: bundle.snippets.count,
                         modules: bundle.customModules.count,
                         shortcuts: bundle.appLaunchShortcuts.count)
    }

    /// Reverts to the automatic backup made before the last import.
    @discardableResult
    static func revertToAutoBackup() -> Bool {
        guard case .success(let backup) = read(from: autoBackupURL) else {
            Log.warn(.app, "Откат импорта: бэкапа нет или он не читается")
            return false
        }
        return apply(backup, backingUp: false) != .backupFailed
    }
}
