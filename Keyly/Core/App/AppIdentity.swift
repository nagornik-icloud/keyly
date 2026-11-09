/// One place for every identifier the app is known by to the system.
enum AppIdentity {
    nonisolated static let bundleID = "app.keyly.Keyly"
    /// The id used before the rename to Keyly; settings are migrated from its domain once.
    nonisolated static let legacyBundleID = "personal.punto-switcher"
    nonisolated static let logSubsystem = bundleID
    nonisolated static let keychainService = "Keyly"
}
