import AppKit
import Carbon.HIToolbox

// MARK: - System key constants

let kNXSystemDefined: UInt32 = 14
let kNXSubtypeAuxControlButtons: Int16 = 8

enum NXKeyType {
    static let soundUp: UInt16 = 0
    static let soundDown: UInt16 = 1
    static let brightnessUp: UInt16 = 2
    static let brightnessDown: UInt16 = 3
    static let mute: UInt16 = 7
    static let illuminationUp: UInt16 = 21
    static let illuminationDown: UInt16 = 22
    static let illuminationToggle: UInt16 = 23
    static let play: UInt16 = 16
    static let next: UInt16 = 17
    static let previous: UInt16 = 18
    static let fastForward: UInt16 = 19
    static let rewind: UInt16 = 20
    static let launchpad: UInt16 = 13
    static let eject: UInt16 = 14
    static let videoMirror: UInt16 = 15
    static let menu: UInt16 = 25
}

// MARK: - Notification names

extension Notification.Name {
    static let customHotKeyChanged = Notification.Name("customHotKeyChanged")
    static let appHotKeysChanged = Notification.Name("appHotKeysChanged")
    static let uiVisibilityChanged = Notification.Name("uiVisibilityChanged")
    static let lastActionChanged = Notification.Name("lastActionChanged")
    static let snippetsChanged = Notification.Name("snippetsChanged")
    /// Open the window on snippets: `object` is the id of the snippet to expand, `nil` — create a new one.
    static let openSnippetInEditor = Notification.Name("openSnippetInEditor")
    /// Show the wizard again.
    static let showWizardAgain = Notification.Name("showWizardAgain")
}

// MARK: - KeyCombo

struct KeyCombo: Equatable, Hashable, Codable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var isSystemKey: Bool = false

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
        case isSystemKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encode(isSystemKey, forKey: .isSystemKey)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
        isSystemKey = try container.decodeIfPresent(Bool.self, forKey: .isSystemKey) ?? false
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isSystemKey: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isSystemKey = isSystemKey
    }
}

// MARK: - KeyCombo display

extension KeyCombo {
    /// Hand-written hash: `NSEvent.ModifierFlags` is an OptionSet with no synthesized conformance.
    /// Compare and hash by the same two fields as `==`, otherwise a dictionary keyed by combos
    /// (duplicate search in `HotKeyInventory`) would disagree with equality.
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    var description: String {
        // Modifier order — AS IN macOS: ⌃ ⌥ ⇧ ⌘, Command last.
        //
        // This used to be the exact reverse (⌘ ⌥ ⇧ ⌃), and every Keyly combo was printed differently
        // from how the system prints the same combo in its menus: the app showed "⌘⌥Z", System
        // Settings — "⌥⌘Z". Someone comparing taken combos with another program spent a second on
        // "is this the same?", and in a shared list Keyly's rows read as foreign.
        let mods = [
            modifiers.contains(.control) ? "⌃" : nil,
            modifiers.contains(.option) ? "⌥" : nil,
            modifiers.contains(.shift) ? "⇧" : nil,
            modifiers.contains(.command) ? "⌘" : nil
        ].compactMap { $0 }.joined()
        let keyString: String
        if isSystemKey {
            keyString = systemKeyName(for: keyCode) ?? keyName(for: keyCode) ?? "Key\(keyCode)"
        } else {
            keyString = keyName(for: keyCode) ?? "Key\(keyCode)"
        }
        return mods + keyString
    }

    func keyName(for code: UInt16) -> String? {
        switch code {
        case 36: return "⏎"
        case 49: return "␣"
        case 51: return "⌫"
        case 53: return "⎋"
        case UInt16(kVK_Tab): return "⇥"
        case UInt16(kVK_LeftArrow): return "←"
        case UInt16(kVK_RightArrow): return "→"
        case UInt16(kVK_UpArrow): return "↑"
        case UInt16(kVK_DownArrow): return "↓"
        // TWO sets of codes for one F-row. Upper — what the built-in MacBook keyboard sends,
        // lower — the standard virtual codes that come from an external keyboard and with
        // "Use F1, F2, etc. keys as standard function keys" turned on.
        //
        // The standard F3–F6 codes used to be missing from the table, and `keyName` returned an
        // EMPTY string for them: someone with an external keyboard assigned F3 and saw an empty
        // hotkey field, while the warning said "«» will stop typing". This can never be caught on
        // a built-in keyboard — it sends codes 160/177/176/178.
        case 122: return "F1"
        case 120: return "F2"
        case 160, 99:  return "F3"
        case 177, 118: return "F4"
        case 176, 96:  return "F5"
        case 178, 97:  return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        default:
            // An empty string is NOT ALLOWED: it turns both the hotkey chip and the warning into
            // silence. If the key can't be named — show its code; ugly, but honest and visible.
            if let translated = UCKeyTranslateKey(code), !translated.isEmpty {
                // The "no empty" rule didn't cover LOW-INK glyphs, which give exactly the same
                // result. Measured: "`" in the chip is a single ~8px tick near the top edge, and the
                // "remove hotkey" cross next to it is more visible than the hotkey itself; the main
                // module's field read as "unassigned". Such keys are named by a word — as the media
                // keys already are.
                if let named = lowInkKeyNames[translated] { return named }
                // The keycap letter is UPPERCASE, as macOS prints it (⌘Z, not ⌘z) and as it is
                // labeled on the key itself. `UCKeyTranslate` returns what the key types without
                // modifiers, i.e. lowercase; nobody noticed before because the product had no fields
                // with letter combos — they came with "General shortcuts". Case conversion is
                // locale-independent: the Turkish locale turns "i" into "İ".
                return translated.uppercased(with: Locale(identifier: "en_US_POSIX"))
            }
            return "Key\(code)"
        }
    }

    /// Glyphs with almost no body: in a chip they are indistinguishable from an empty field.
    ///
    /// Show the SECOND CHARACTER OF THE SAME PHYSICAL KEY — the bigger one people actually say
    /// out loud: "`" → "~", "'" → "\"", "." → ">", "," → "<".
    ///
    /// This used to show English words: Grave, Quote, Period, Comma. They fixed visibility but
    /// broke clarity — "Grave" meant nothing to users ("it's just a tilde"). A technical English
    /// term in a Russian UI answers the wrong question: people look for the symbol they see on
    /// the key, not the key code name.
    ///
    /// The class is "a fix on one axis that breaks another": fixing visibility without naming
    /// WHAT it was traded for.
    private var lowInkKeyNames: [String: String] {
        ["`": "~", "'": "\"", ".": ">", ",": "<", "-": "—", "=": "+"]
    }

    private func systemKeyName(for code: UInt16) -> String? {
        switch code {
        // THE WHOLE TOP ROW IS NAMED BY ITS F-KEY NUMBER, not by the action.
        //
        // Media keys like Rewind and Forward are effectively F7 and F9 and should look like the
        // rest. That holds for the whole row, not two keys: F3–F6 were already shown as numbers
        // (their codes go through `keyName`), while neighbours on the same physical row —
        // "Bright-", "Rew", "Vol+" — read as chips of a different kind. People assign the KEY they
        // look at; it has an icon printed on it, but they call it "F7". The action name answered
        // the wrong question.
        //
        // The action the key will stop performing isn't lost — the warning names it
        // (`BareKeyWarning`: "F7 will stop controlling the player"), and that's the right place
        // for it: there it is the actual subject.
        //
        // The number is used ONLY where the row position is the same on every Mac: brightness
        // F1/F2, player F7–F9, sound F10–F12. Keyboard backlight is NOT included: it lived on F5/F6
        // on 2016–2020 laptops, while on Apple silicon those are Dictation and Do Not Disturb —
        // a number would be a lie, not a hint.
        case NXKeyType.brightnessDown: return "F1"
        case NXKeyType.brightnessUp: return "F2"
        case NXKeyType.rewind: return "F7"
        case NXKeyType.play: return "F8"
        case NXKeyType.fastForward: return "F9"
        case NXKeyType.mute: return "F10"
        case NXKeyType.soundDown: return "F11"
        case NXKeyType.soundUp: return "F12"
        // Keys WITHOUT a fixed place in the F-row: they come from external keyboards and as
        // separate buttons, they have no number. Name them by action — without color emoji
        // (variation selector U+FE0F forces a glossy color presentation).
        case NXKeyType.illuminationDown: return "Light-"
        case NXKeyType.illuminationUp: return "Light+"
        case NXKeyType.illuminationToggle: return "Light·"
        case NXKeyType.next: return "Next"
        case NXKeyType.previous: return "Prev"
        case NXKeyType.launchpad: return "Launchpad"
        case NXKeyType.eject: return "Eject"
        case NXKeyType.videoMirror: return "Mirror"
        case NXKeyType.menu: return "Menu"
        default:
            // An HONEST TECHNICAL name, not "F\(code)".
            //
            // The previous fallback put the code into the F-key template and produced not only
            // meaningless "F160"/"F176", but codes 4–12 as "F4", "F5", "F8" — names of REAL keys,
            // indistinguishable in a chip from honest ones. People looked for an F8 on the keyboard
            // they never assigned. A made-up name lies more convincingly than emptiness. The sibling
            // `keyName` solves the same problem the same way ("ugly but honest") — the two functions
            // must not diverge.
            return "Key\(code)"
        }
    }

    static func fromSystemDefined(event: NSEvent) -> KeyCombo? {
        guard event.type == .systemDefined,
              event.subtype.rawValue == kNXSubtypeAuxControlButtons else { return nil }
        let data1 = event.data1
        let keyCode = UInt16((data1 & 0xffff0000) >> 16)
        let keyFlags = (data1 & 0x0000ffff)
        let keyState = (keyFlags & 0xff00) >> 8
        let isRepeat = (keyFlags & 0x1) != 0
        Log.info(.hotKey, "HotKeyRecorder: systemDefined data1=0x\(String(data1, radix: 16)) keyCode=\(keyCode) keyState=0x\(String(keyState, radix: 16)) repeat=\(isRepeat) flags=0x\(String(keyFlags, radix: 16))")
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return KeyCombo(keyCode: keyCode, modifiers: mods, isSystemKey: true)
    }
}

// MARK: - UCKeyTranslate helper

/// Key name tied to the PHYSICAL key, not to the current layout.
///
/// This used to use `TISCopyCurrentKeyboardLayoutInputSource`, and the hotkey label moved
/// with the layout: the same saved combo showed as "`" in English and as "]" in Russian.
/// For a product whose whole point is switching layouts this is doubly unacceptable: it
/// couldn't name its own key. Worse, the bare-key warning named ONE of the two characters,
/// while the whole physical key goes silent — i.e. both.
///
/// Use a Latin (ASCII-capable) layout: it always exists in the system and gives each
/// physical key one constant name.
/// Key name cache + a lock around Text Input Services.
///
/// TIS functions (`TISCreateInputSourceList`, `TISGetInputSourceProperty`) are NOT thread-safe:
/// called concurrently from several threads, the process crashes with signal 6. It never
/// surfaced in the product — `description` is called from the main actor; it showed up in
/// tests when five hotkey label checks ran in parallel. A crashed test runner is a cheap
/// signal here: the same function is called from `HotKeyManager`, which lives next to the
/// event tap callback, and "hasn't crashed yet" is no guarantee.
///
/// The cache also removes the cost: the layout doesn't change at runtime (we use a fixed
/// Latin one), while the source list was created on EVERY call — once per hotkey chip on
/// every screen redraw.
private let keyNameLock = NSLock()
private nonisolated(unsafe) var keyNameCache: [UInt16: String?] = [:]

func UCKeyTranslateKey(_ keyCode: UInt16) -> String? {
    keyNameLock.lock()
    defer { keyNameLock.unlock() }
    if let cached = keyNameCache[keyCode] { return cached }
    let result = translateUncached(keyCode)
    keyNameCache[keyCode] = result
    return result
}

private func translateUncached(_ keyCode: UInt16) -> String? {
    guard let layout = asciiCapableLayout(),
          let ptr = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let layoutData = unsafeBitCast(ptr, to: CFData.self)
    guard let rawPtr = CFDataGetBytePtr(layoutData) else { return nil }
    let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(rawPtr))
    var keysDown: UInt32 = 0
    var chars: [UniChar] = Array(repeating: 0, count: 4)
    var realLength: Int = 0
    let translateStatus = UCKeyTranslate(
        keyboardLayout,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &keysDown,
        chars.count,
        &realLength,
        &chars
    )
    guard translateStatus == noErr, realLength > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: realLength)
}

/// Latin layout for NAMING keys. Try exactly US first — it gives the familiar labels;
/// if it's not in the system, take any ASCII-capable one.
private func asciiCapableLayout() -> TISInputSource? {
    let criteria = [kTISPropertyInputSourceID as String: "com.apple.keylayout.US"] as CFDictionary
    if let list = TISCreateInputSourceList(criteria, true)?.takeRetainedValue() as? [TISInputSource],
       let us = list.first {
        return us
    }
    return TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
}

/// Equivalent codes of one physical key.
///
/// The F3–F6 row arrives with TWO different codes: the built-in MacBook keyboard sends
/// media codes (160/177/176/178), an external one — standard virtual codes (99/118/96/97).
/// Same physical key, same symbol on the keycap — and the product DRAWS them the same
/// (`keyName` knows both codes) but COMPARES strictly. Record a hotkey on the built-in
/// keyboard, connect an external one — "F5" is on screen, but pressing it does nothing.
///
/// Measured: the voice hotkey in settings stores code 176, a synthetic press of the same
/// key arrives with code 96 — no match, recording doesn't start.
enum KeyCodeEquivalents {
    private static let pairs: [Set<UInt16>] = [
        [160, 99],   // F3
        [177, 118],  // F4
        [176, 96],   // F5
        [178, 97],   // F6
    ]

    /// Whether two codes count as the same key.
    static func same(_ lhs: UInt16, _ rhs: UInt16) -> Bool {
        if lhs == rhs { return true }
        return pairs.contains { $0.contains(lhs) && $0.contains(rhs) }
    }

    // There used to be `all(for:)` — "all codes of a key, for Carbon: it registers a SPECIFIC
    // code, and the system won't deliver the hotkey for the other variant". The function was
    // removed: the hypothesis was wrong, and nobody called it.
    //
    // ALL codes in `pairs` are media keys, i.e. `isSystemKey`. `HotKeyManager` sends those to
    // the event tap BEFORE Carbon registration (see the `if combo.isSystemKey` branch before
    // `RegisterEventHotKey`), so a code with an equivalent can never reach Carbon. The real bug
    // (176 vs 96 for F5) is fixed by comparing via `same()` in the tap branch — and it is fixed there.
    //
    // Two green tests guarded code the user could never reach. Such tests prove the function
    // is correct and say nothing about the product not calling it.
}
