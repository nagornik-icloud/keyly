import Foundation

/// What exactly breaks in the system if this key is assigned WITHOUT modifiers.
///
/// A bare key is allowed — for layout switching it's an established habit. But while Keyly is
/// running, such a key never reaches other apps: `HotKeyManager` swallows the event
/// (`return nil`). Someone who assigns "]" simply can no longer type "]" — anywhere, with no
/// hint of why.
///
/// A pure type: the warning text is a rule, not layout, and must be testable. The catalog key is
/// returned separately from the argument so the string can be translated.
enum BareKeyWarning {

    /// `nil` — the combo has modifiers, nothing breaks.
    ///
    /// Returns a catalog key and an argument; the UI layer resolves the key to a string. That
    /// keeps the text translatable, and the "what exactly breaks" rule lives in one place.
    /// `messageKey` is what to say, `actionKey` is the catalog key for the macOS action name
    /// (system keys only). A regular key's name does NOT come here: `KeyCombo` gets it via Text
    /// Input Services, which is impossible in a test process — the rule would be untestable.
    /// The UI layer fills in the label; it has the combo at hand.
    static func reason(for combo: KeyCombo?) -> (messageKey: String, actionKey: String?)? {
        guard let combo, combo.modifiers.isEmpty else { return nil }

        // System keys break an OS action, not typing — and that action is what must be named.
        if let action = systemAction(for: combo) {
            return ("hotkey.bare.system", action)
        }
        // A key that prints nothing (F-row, Esc, Enter, Tab, arrows) can't "stop typing". It used
        // to fall into the fallback and get exactly that phrase: "'F3' will stop typing" — F3
        // never typed anything, so the user either didn't understand or decided the warning was
        // nonsense and never learned the cost.
        // Any SYSTEM key, even one missing from the action table, prints nothing: "Eject will
        // stop typing" is just as false as for F3. The fallback must describe the class, not a
        // single case.
        if combo.isSystemKey || !printsCharacter(combo.keyCode) {
            return ("hotkey.bare.action", nil)
        }
        // A regular key: its character will stop being typed.
        return ("hotkey.bare.character", nil)
    }

    /// Whether to show the warning RIGHT NOW.
    ///
    /// The rule lives here, not in the view body, because it decides whether the user sees the
    /// warning at all — and logic inside `body` can't be tested. The permanent warning was
    /// removed as repetitive; the function survives because showing it is tied to the MOMENT of
    /// assignment, not to the field's value.
    ///
    /// - Parameters:
    ///   - current: what's in the field.
    ///   - justAssigned: what the user assigned during this screen's lifetime; `nil` — nothing.
    static func fresh(current: KeyCombo?,
                      justAssigned: KeyCombo?) -> (messageKey: String, actionKey: String?)? {
        // A bare key saved earlier stays quiet: the user learned about it when assigning.
        guard let current, current == justAssigned else { return nil }
        return reason(for: current)
    }

    /// Whether the key prints a character. The NON-printing list is complete for both code sets:
    /// the Mac's built-in keyboard and the standard virtual codes of an external one.
    private static func printsCharacter(_ code: UInt16) -> Bool {
        !nonPrintingCodes.contains(code)
    }

    private static let nonPrintingCodes: Set<UInt16> = [
        36,   // ⏎
        48,   // ⇥
        51,   // ⌫
        53,   // ⎋
        117,  // ⌦
        115, 119, 116, 121,           // Home, End, PageUp, PageDown
        123, 124, 125, 126,           // arrows
        122, 120,                     // F1, F2
        160, 99, 177, 118, 176, 96, 178, 97,   // F3–F6 in both code sets
        98, 100, 101, 109, 103, 111,  // F7–F12
        105, 107, 113, 106, 64, 79, 80,        // F13–F19
    ]

    /// CATALOG KEY for the macOS action bound to the key. The list is incomplete on purpose:
    /// we name only what the user will DEFINITELY recognize by name.
    ///
    /// The `guard combo.isSystemKey` check is GONE, and that mattered. F-row keys on the
    /// built-in keyboard arrive as a plain `keyDown` with `isSystemKey: false`
    /// (`HotKeyRecorderNSView`), so the guard kept out of the table exactly the keys it exists
    /// for. Result: for F3 the app said "'F3' will stop working" — restating what the user had
    /// just done — and never mentioned Mission Control.
    ///
    /// The key is looked up BY CODE and doesn't depend on `isSystemKey`: one physical key
    /// arrives with two codes (media variant and regular), and both must give the same name.
    private static func systemAction(for combo: KeyCombo) -> String? {
        switch combo.keyCode {
        // Catalog keys, not ready strings: the action name is inserted INTO the warning, so it
        // appears on screen and must be translated along with it.
        case NXKeyType.brightnessDown, NXKeyType.brightnessUp:     return "key.action.brightness"
        case NXKeyType.soundDown, NXKeyType.soundUp, NXKeyType.mute: return "key.action.volume"
        case NXKeyType.play, NXKeyType.next, NXKeyType.previous,
             NXKeyType.fastForward, NXKeyType.rewind:              return "key.action.player"
        case NXKeyType.launchpad:                                  return "key.action.launchpad"
        case NXKeyType.illuminationDown, NXKeyType.illuminationUp: return "key.action.backlight"
        // F3 and F4 — both codes for each: the built-in keyboard's media variant and an external
        // keyboard's regular virtual code (same pairs as in `KeyCodeEquivalents`).
        case 160, 99:                                              return "key.action.missionControl"
        case 177, 118:                                             return "key.action.search"
        // Raw 0x19/0x1A ("Dictation", "Focus") were REMOVED: they were guesses, and 0x19 = 25
        // matches the documented `NXKeyType.menu`. The same code showed as "Menu" in the chip
        // but was called "macOS Dictation" in the warning — two tables disagreed about the
        // key, and one of them was wrong. Naming the action wrongly is worse than not naming
        // it: the generic "will stop doing what it does in macOS" branch handles it.
        default:                                                   return nil
        }
    }
}
