import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// The permission is granted, but the subsystem still doesn't work.
///
/// macOS does not pick up Accessibility on the fly if it was PREVIOUSLY denied: the checkbox in
/// System Settings is on, `AXIsProcessTrusted()` returns `true`, yet the event tap still can't be
/// created. The wizard used to unlock the step at that point and let the user into an app where
/// no hotkey worked — with nothing to explain why.
enum PermissionStaleness {

    /// Whether a restart is needed: permission granted, but event interception won't start.
    ///
    /// The check costs creating and immediately disabling a tap — tens of microseconds — and runs
    /// only on the permissions step, not on a hot path.
    static func accessibilityNeedsRestart() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        return !canCreateEventTap()
    }

    private static func canCreateEventTap() -> Bool {
        // A `listenOnly` tap is enough for the check and intercepts nothing: an active tap
        // would grab real input events for a fraction of a second.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    /// Relaunch ourselves. It must be a PROCESS restart — reopening the window doesn't help,
    /// the permission is picked up only at launch.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}

