import Foundation
import Combine

/// Which shortcuts the system refused to give us.
///
/// Registration failures are common: the combo may be taken by Spotlight, Raycast, Alfred or
/// macOS itself. The failure used to go ONLY to the log: on screen the shortcut stayed
/// assigned, and pressing it did nothing. The user sees a configured hotkey, presses it and
/// concludes the app is broken — while the app was the only one that knew why.
@MainActor
final class HotKeyRegistrationStatus: ObservableObject {
    static let shared = HotKeyRegistrationStatus()

    /// Field ids (`HotKeyFieldID`) whose registration the system rejected.
    @Published private(set) var failed: Set<String> = []

    private init() {}

    func report(fieldID: String, succeeded: Bool) {
        if succeeded {
            guard failed.contains(fieldID) else { return }
            failed.remove(fieldID)
        } else {
            guard !failed.contains(fieldID) else { return }
            failed.insert(fieldID)
        }
    }

    /// Clears marks before re-registering the whole set: otherwise a deleted app or snippet
    /// would leave its red mark behind forever.
    func clear(prefix: String) {
        failed = failed.filter { !$0.hasPrefix(prefix) }
    }

    func isFailed(_ fieldID: String) -> Bool { failed.contains(fieldID) }
}
