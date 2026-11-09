import Foundation

/// One place for every identifier the app is known by to the system.
enum AppIdentity {
    nonisolated static let bundleID = "app.keyly.Keyly"
    /// The Debug configuration's id: separate settings, same hotkeys — so the two builds must
    /// still never run at once (see `SingleInstanceGuard`).
    nonisolated static let debugBundleID = "app.keyly.Keyly.debug"
    /// The id used before the rename to Keyly; settings are migrated from its domain once.
    nonisolated static let legacyBundleID = "personal.punto-switcher"
    nonisolated static let logSubsystem = bundleID
    /// Debug builds run under `app.keyly.Keyly.debug` (see the Debug configuration) and keep
    /// their keys in a separate Keychain item, so a test run can never read or overwrite the
    /// user's real keys.
    #if DEBUG
    nonisolated static let keychainService = "Keyly.debug"
    #else
    nonisolated static let keychainService = "Keyly"
    #endif

    /// True only in the build that owns the user's real data (release id).
    nonisolated static var isReleaseIdentity: Bool { Bundle.main.bundleIdentifier == bundleID }
}
