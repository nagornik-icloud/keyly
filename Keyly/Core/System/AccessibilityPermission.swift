import ApplicationServices
import AppKit

/// Helper for checking and requesting Accessibility access.
public struct AccessibilityPermission {
    
    /// Checks whether the app is trusted for Accessibility and requests permission if needed.
    /// - Parameter prompt: Whether to show the system prompt for granting access
    /// - Returns: true if the app is trusted for Accessibility, otherwise false
    public static func ensurePermission(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            Log.info(.app, "AccessibilityPermission: Доступ предоставлен")
        } else {
            Log.info(.app, "AccessibilityPermission: Доступ не предоставлен")
        }
        return trusted
    }
    
    /// Whether the app has trusted Accessibility access, without showing a prompt.
    public static var isTrusted: Bool {
        return AXIsProcessTrusted()
    }
}

import AppKit

public extension AccessibilityPermission {
    /// Opens System Settings on the Accessibility section (if possible).
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
        }
    }

    /// Path to the current .app (if launched from an .app).
    static var appBundlePath: String? {
        Bundle.main.bundlePath
    }
}
