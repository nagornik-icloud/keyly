import SwiftUI
import AppKit

/// The `Settings` scene exists only for the system "Settings…" menu item (⌘,):
/// for a menu bar app without a `WindowGroup` this is the only way to get it.
///
/// It has no content of its own BY DESIGN. There used to be a SECOND, separate settings
/// screen here — a launch-at-login toggle and Accessibility status — and it drifted from the
/// real one: the main window long since gained keys, language, Dock icon, stats reset, while ⌘,
/// opened a window from a previous version of the app. Two settings screens are not a
/// "fallback path" but a place where the user changes the wrong setting and doesn't
/// understand why nothing changed.
///
/// So the scene acts as a redirect: it opens the real window on the "Settings" section
/// and immediately closes itself.
struct SettingsView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                (NSApp.delegate as? AppDelegate)?.showOnboarding(openSettings: true)
                // The scene window must be closed on the NEXT tick: during onAppear it is not yet
                // in the app's window list, and the lookup misses it.
                DispatchQueue.main.async {
                    NSApp.windows
                        .first { $0.identifier?.rawValue.contains("Settings") == true }?
                        .close()
                }
            }
    }
}
