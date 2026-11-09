import SwiftUI

@main
struct KeylyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // No WindowGroup — the app lives in the menu bar.
        Settings {
            SettingsView()
        }
    }
}
