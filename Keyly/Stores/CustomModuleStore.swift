import Foundation

extension Notification.Name {
    static let customAIModulesChanged = Notification.Name("CustomAIModulesChanged")
}

enum CustomModuleStore {

    /// Schema version, backup copy, write latch.
    private static let store = VersionedStore<CustomAIModule>(key: SettingsKeys.customModules,
                                                              name: "customModules")

    static func load() -> [CustomAIModule] { store.load() }

    /// `false` means the write was rejected by the latch: reading this store failed earlier,
    /// and saving would overwrite the user's prompts. The notification is sent only when a write actually happens.
    @discardableResult
    static func save(_ modules: [CustomAIModule]) -> Bool {
        guard store.save(modules) else { return false }
        NotificationCenter.default.post(name: .customAIModulesChanged, object: nil)
        return true
    }
}
