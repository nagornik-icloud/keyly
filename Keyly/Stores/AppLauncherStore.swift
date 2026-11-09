import Foundation
import Combine

@MainActor
final class AppLauncherStore: ObservableObject {
    
    static let shared = AppLauncherStore()

    @Published private(set) var shortcuts: [AppLaunchShortcut] = []

    private init() {
        shortcuts = Self.load()
    }

    func add(_ shortcut: AppLaunchShortcut) {
        shortcuts.append(shortcut)
        save()
    }

    func update(_ shortcut: AppLaunchShortcut) {
        guard let idx = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[idx] = shortcut
        save()
    }

    func delete(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        save()
    }

    func replace(all: [AppLaunchShortcut]) {
        shortcuts = all
        save()
    }

    /// Schema version, backup copy, write latch.
    private static let store = VersionedStore<AppLaunchShortcut>(key: SettingsKeys.appShortcuts,
                                                                 name: "appShortcuts")

    private func save() {
        guard Self.store.save(shortcuts) else { return }
        NotificationCenter.default.post(name: .appHotKeysChanged, object: nil)
    }

    private static func load() -> [AppLaunchShortcut] { store.load() }
}
