import CoreGraphics
import AppKit

/// The third permission Keyly needs — Input Monitoring.
///
/// Why it is separate. Since macOS 10.15, intercepting the keyboard with `CGEventTap` needs
/// its OWN permission — `kTCCServiceListenEvent` — not Accessibility. The AX-tree permission
/// (`AXIsProcessTrusted`) and the permission to listen to keys are DIFFERENT toggles in
/// different panes of System Settings; granting one says nothing about the other.
///
/// What went wrong without it. The app used to check only two of three permissions at launch:
/// Accessibility and microphone. Input Monitoring was checked nowhere — not at launch, not on
/// the Readiness screen. When it is missing, `CGEventTap` is created but no keys arrive:
/// hotkeys and snippet triggers stay silent, while the app reports "all set" because both
/// permissions it knows about are granted. An indirect probe existed
/// (`PermissionStaleness.canCreateEventTap`), but only the wizard's permission step called it,
/// and it explained the failure as "restart needed" — sending the user to fix the wrong thing.
///
/// Replacing the binary is a separate trap. Permissions are tied to the code signature, and
/// after installing a fresh build over the old one this toggle is the one most likely to turn
/// off — with no visible sign: the app looks running and healthy.
enum InputMonitoringPermission {

    /// Whether access is granted. No prompt, no side effects.
    static var isGranted: Bool {
        #if DEBUG
        // Demo screenshots show the app as a set-up user sees it, without TCC grants for a
        // freshly built binary.
        if DemoContent.isActive { return true }
        #endif
        return CGPreflightListenEventAccess()
    }

    /// Ask the system. The dialog is shown only ONCE per install: after that macOS silently
    /// denies, and the only way is the toggle in System Settings.
    @discardableResult
    static func request() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Open the right settings pane. It must be `ListenEvent`, not `Accessibility`: a user sent
    /// to the wrong list finds a checkbox that is already on and no explanation.
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
