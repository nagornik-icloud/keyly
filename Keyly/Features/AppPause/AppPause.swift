import Foundation

/// App pause: all hotkeys and text features off at once.
///
/// A separate type, not a bool in the menu controller: pause is checked from four places
/// (menu bar, hotkey manager, window, services), and four copies of the condition would drift —
/// one place would keep working while paused, which would look like a random glitch.
enum AppPause {

    /// Posted on state change. Everyone who must turn off or back on listens to it.
    static let changed = Notification.Name("appPauseChanged")

    static var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKeys.isPaused) }
        set {
            guard newValue != isPaused else { return }
            UserDefaults.standard.set(newValue, forKey: SettingsKeys.isPaused)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
