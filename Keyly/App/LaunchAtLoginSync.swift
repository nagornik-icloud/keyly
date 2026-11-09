import ServiceManagement

/// The "launch at login" switch is stored in settings, but macOS keeps its own list.
/// After the bundle id changed, the stored "on" no longer had a system entry behind it,
/// so the switch showed "on" while Keyly did not start. Re-register on launch.
enum LaunchAtLoginSync {
    static func reconcile(defaults: UserDefaults = .standard) {
        #if DEBUG
        // Debug builds run from DerivedData; registering them would put a dev build
        // into the user's login items.
        return
        #else
        // Only a missing entry is repaired. `.requiresApproval` means the user switched
        // Keyly off in System Settings — re-registering every launch would fight that.
        guard defaults.bool(forKey: SettingsKeys.launchAtLogin) else { return }
        if SMAppService.mainApp.status == .requiresApproval {
            defaults.set(false, forKey: SettingsKeys.launchAtLogin)   // switch shows the truth
            return
        }
        guard SMAppService.mainApp.status == .notRegistered else { return }
        do {
            try SMAppService.mainApp.register()
            Log.info(.app, "Launch at login re-registered for this app")
        } catch {
            Log.error(.app, "Launch at login could not be registered: \(LogSanitizer.sanitize(error.localizedDescription))")
        }
        #endif
    }
}
