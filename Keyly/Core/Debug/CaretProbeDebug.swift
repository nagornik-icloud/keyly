#if DEBUG
import AppKit
import Carbon.HIToolbox
import OSLog

/// Manual runtime check of `CaretProbe` without running a feature. Enabled with `KEYLY_CARET_DEBUG=1`
/// (Xcode → scheme → Run → Arguments → Environment). DEBUG only. Two passive triggers:
///
/// 1. **⌃⌥⌘P** over a field — forces one verdict on demand. BUT: over a secure field (password) macOS
///    turns on Secure Input Mode (`EnableSecureEventInput`), which blocks keyboard observation for
///    ALL processes — both CGEventTap and the `NSEvent` global monitor. So the hotkey does NOT reach
///    the probe there and there is no verdict. This is an OS limitation, not CaretProbe's.
///
/// 2. **Auto-stream on focus change** — a ~1.2s timer reads the AX tree (Secure Input Mode does NOT
///    block it, only the keyboard is blocked) and logs a verdict ONLY when the app or the focused
///    element changed. This way a password field is visible too: click into it — one `◆` line arrives.
///
/// Both monitors are passive — they don't swallow input and don't touch event tap re-entrancy.
@MainActor
enum CaretProbeDebug {
    private static var keyMonitor: Any?
    private static var pollTimer: Timer?
    private static var lastFocusKey = ""
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "CaretProbeDebug")

    static func installIfEnabled() {
        guard ProcessInfo.processInfo.environment["KEYLY_CARET_DEBUG"] == "1", keyMonitor == nil else { return }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
            guard mods == [.control, .option, .command], event.keyCode == UInt16(kVK_ANSI_P) else { return }
            Task { @MainActor in probe(marker: "▸", beep: true) }
        }

        // Auto-stream: deduplicated by (app + focused element), so the log means "verdict changed", not spam.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            Task { @MainActor in pollFocusChange() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        log.notice("CaretProbeDebug активен — ⌃⌥⌘P форсит вердикт; смена фокуса логируется автоматически (◆).")
    }

    /// Cheap focus key WITHOUT a full resolve: frontmost app bundleID + identity of the
    /// system-wide focused element. The full CaretProbe runs only when the key changes.
    private static func focusKey() -> String {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let elementID: String
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            elementID = String(Int(bitPattern: CFHash(unsafeBitCast(focused, to: AXUIElement.self))))
        } else {
            elementID = "nil"
        }
        return "\(bundle)#\(elementID)"
    }

    private static func pollFocusChange() {
        let key = focusKey()
        guard key != lastFocusKey else { return }
        lastFocusKey = key
        probe(marker: "◆", beep: false)
    }

    private static func probe(marker: String, beep: Bool) {
        let r = CaretProbe.resolve(context: "debug")
        let rect = r.caretRect.map { "\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))×\(Int($0.height))" } ?? "nil"
        log.notice("\(marker, privacy: .public) \(String(describing: r.confidence), privacy: .public) | editable=\(r.isEditable) | caret=\(rect, privacy: .public) | \(r.signals.joined(separator: " | "), privacy: .public)")
        if beep { NSSound.beep() }
    }
}
#endif
