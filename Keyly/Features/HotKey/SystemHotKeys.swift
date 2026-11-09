import AppKit
import Carbon.HIToolbox

/// Shortcuts that must NEVER be intercepted.
///
/// Intercepting ⌘Q or ⌘Tab breaks not one key but working with the system as a whole: the user
/// can no longer quit or switch apps — and doesn't connect it to Keyly, because it breaks
/// everywhere while they only configured one module.
///
/// A pure type: the rule is checked by a test, not by actually assigning ⌘Q to yourself.
enum SystemHotKeys {

    /// System-reserved shortcuts. The list is closed and deliberately short: only what makes
    /// the Mac unusable when intercepted, not everything macOS ever uses — otherwise there would
    /// be no free shortcuts left at all.
    private static let reserved: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)] = [
        (UInt16(kVK_ANSI_Q), [.command]),        // quit app
        (UInt16(kVK_ANSI_W), [.command]),        // close window
        (UInt16(kVK_Tab), [.command]),           // app switcher
        (UInt16(kVK_Space), [.command]),         // Spotlight
        (UInt16(kVK_ANSI_Comma), [.command]),    // app settings
        (UInt16(kVK_ANSI_H), [.command]),        // hide app
        (UInt16(kVK_Escape), [.command, .option]), // force quit
    ]

    static func isReserved(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let normalized = modifiers.intersection([.command, .option, .control, .shift])
        return reserved.contains { $0.keyCode == keyCode && $0.modifiers == normalized }
    }

    static func isReserved(_ combo: KeyCombo) -> Bool {
        isReserved(keyCode: combo.keyCode, modifiers: combo.modifiers)
    }
}
