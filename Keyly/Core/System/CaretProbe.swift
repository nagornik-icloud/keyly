import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// The single primitive for detecting an editable text field/caret.
///
/// Returns a CONFIDENCE LEVEL, not a bare bool — because missing caret coordinates
/// (Electron/web/secure fields) ≠ "not a field". Techniques taken from analyzing SuperDictate:
///   1. caret probe `AXBoundsForRange` / `AXBoundsForTextMarkerRange` → a rect = definitely text;
///   2. role/subrole/`AXEditable`/`AXUIElementIsAttributeSettable` (value is settable) → editable;
///   3. hit test at the last click (`AXUIElementCopyElementAtPosition`) — rescues Chrome/Electron;
///   4. BFS walk of the focus/window subtree within a time budget;
///   5. fallback: allowlist of known text apps + "recently typed".
///
/// Replaces `TextFieldDetector` (removed after consumers are migrated). The replacement
/// transport is not here: CaretProbe only FINDS and READS; writing is paste/typing.
///
/// TODO(Phase B): move the AX probe off the main actor (currently @MainActor with a strict timeout).
@MainActor
enum CaretProbe {

    /// The tier lives in `CaretTier` — a pure type without AppKit, covered by tests.
    /// Only an alias here: two independent enums with identical cases would drift apart on the
    /// first rules change.
    typealias Confidence = CaretTier.Confidence

    struct Resolution {
        let confidence: Confidence
        let element: AXUIElement?
        let caretRect: CGRect? // screen coordinates (top-left origin), if obtained
        let isEditable: Bool
        /// Secure context (password). Computed from the DIRECT focus + system Secure Input Mode,
        /// NOT from the element found by heuristics — see `isSecureNow()`.
        let isSecure: Bool
        let signals: [String]

        /// Convenience predicates for feature gates.
        var isField: Bool { confidence == .caret || confidence == .editable || confidence == .ambiguous }
        var isDefinitelyNotField: Bool { confidence == .none }
        /// Modules that EXTRACT text (copy/select-all → clipboard/LLM) must not go here — password leak.
        var blocksTextExtraction: Bool { isSecure }
    }


    // Budgets (SuperDictate: locator ~0.28s, timeout ~0.16s, cap ~900, depth ~20).
    private static let messagingTimeout: Float = 0.16
    private static let scanBudget: TimeInterval = 0.28
    private static let maxScanned = 900
    private static let maxDepth = 20

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, "AXSearchField", "AXComboBox"
    ]
    // AXContentList is NOT included: per Apple docs it's the subrole for content organized as a
    // list (mail list, feed) — a read-only container for reading, not an input field.
    private static let textSubroles: Set<String> = [
        "AXStandardTextArea", "AXSecureTextField", "AXSearchField"
    ]
    // Roles that are definitely NOT a field. AXWebArea is here on purpose: it always has a
    // document-level selected range, but that doesn't mean the user is in an <input>.
    private static let nonTextRoles: Set<String> = [
        "AXButton", "AXMenu", "AXMenuBar", "AXMenuBarItem", "AXMenuItem", "AXImage", "AXSlider",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXTabGroup", "AXTab", "AXWindow",
        "AXApplication", "AXDockItem", "AXOutline", "AXList", "AXTable", "AXColumn", "AXCell",
        "AXToolbar", "AXSheet", "AXDrawer", "AXScrollBar", "AXBusyIndicator", "AXProgressIndicator",
        "AXStaticText", "AXLink", "AXIncrementor", "AXValueIndicator", "AXSplitter",
        "AXDisclosureTriangle", "AXLayoutArea", "AXWebArea", "AXSplitGroup"
    ]
    private static let knownTextApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "ws.electron.cursor", "com.openai.chat", "com.anthropic.claudefordesktop", "notion.id",
        "ru.keepcoder.Telegram", "com.telegram.desktop", "net.whatsapp.WhatsApp", "com.hnc.Discord",
        "com.apple.Notes", "com.apple.mail", "com.apple.TextEdit", "com.apple.dt.Xcode",
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "md.obsidian", "com.bear-writer", "abnerworks.Typora"
    ]

    // MARK: - Public entry

    static func resolve(context: String) -> Resolution {
        var signals: [String] = []
        guard AXIsProcessTrusted() else {
            signals.append("ax_not_trusted")
            // System Secure Input Mode is readable WITHOUT AX trust — don't return a false `false` here.
            let secureNoAX = secureContext(focused: nil, signals: &signals)
            return finish(.none, nil, nil, false, secure: secureNoAX, signals, context)
        }

        let front = NSWorkspace.shared.frontmostApplication
        let bundleId = front?.bundleIdentifier ?? "(unknown)"
        signals.append("front=\(bundleId)")

        let pid = front?.processIdentifier
        let app: AXUIElement? = pid.map { AXUIElementCreateApplication($0) }
        if let app { AXUIElementSetMessagingTimeout(app, messagingTimeout) }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)

        let focused = focusedElement(app: app, system: system, signals: &signals)

        // Secure is computed ONCE from the DIRECT focus + system mode, not from the element the tiers
        // below find: hit test/BFS may return a different (non-secure) element, and a gate on it would lie.
        let secure = secureContext(focused: focused, signals: &signals)

        // From here the probe only COLLECTS signals. The decision is made by `CaretTier.resolve` —
        // a pure function without AppKit, covered by tests. The rules used to be spread across four
        // early `return`s here: they could only be checked by a real run in another app, and one such
        // run found that a caret on plain page text counted as proof of a field.
        var tier = CaretTier.Signals()
        var element: AXUIElement? = focused
        var caretRect: CGRect?

        // 1. Direct focus. ROLE VETO — FIRST: AXWebArea/AXButton return a document range and a
        // value, but are not input fields.
        if let focused {
            AXUIElementSetMessagingTimeout(focused, messagingTimeout)
            if isVetoed(focused) {
                tier.roleVetoed = true
                signals.append("✗focus_role_veto")
            } else {
                switch isTextInputElement(focused, signals: &signals) {
                case .yes:
                    tier.editability = .proven
                    caretRect = caretFrame(focused)
                    if caretRect != nil { signals.append("✓caret_rect") }
                case .denied:
                    tier.editability = .denied
                case .unknown:
                    break
                }
            }
        }

        // 2. Hit test at the last click IN THIS app (Chrome/Electron, where focused is unreliable).
        // Returns only an already PROVEN editable element.
        if tier.editability != .proven,
           let app, let pid, let hit = hitTest(app: app, pid: pid, signals: &signals) {
            tier.hitTestFoundEditable = true
            element = hit
            caretRect = caretFrame(hit)
            signals.append(caretRect != nil ? "✓caret_via_click" : "via_click")
        }

        // 3. BFS — ONLY if the focus is not vetoed and not rejected: otherwise a walk from AXWebArea
        // finds NON-focused inputs (a search box somewhere on the page) and falsely decides "editable".
        if tier.editability != .proven, !tier.hitTestFoundEditable,
           !tier.roleVetoed, tier.editability != .denied {
            let deadline = ProcessInfo.processInfo.systemUptime + scanBudget
            if let found = scan(root: focused ?? app, deadline: deadline, signals: &signals) {
                tier.scanFoundEditable = true
                element = found
                caretRect = caretFrame(found)
            }
        }

        tier.hasCaretRect = caretRect != nil
        tier.appInAllowlist = knownTextApps.contains(bundleId)
        tier.recentlyTyped = recentlyTyped()
        if tier.appInAllowlist { signals.append("app_in_list") }
        if tier.recentlyTyped { signals.append("recent_typing") }
        if tier.editability == .denied { signals.append("focus_denied") }

        let confidence = CaretTier.resolve(tier)
        let editable = CaretTier.isEditable(confidence)
        // Caret coordinates are returned only where they mean anything: with .ambiguous/.none
        // editability isn't proven, and a rect would be misleading.
        let rect = editable ? caretRect.map(toScreen) : nil
        return finish(confidence, editable ? element : focused, rect, editable,
                      secure: secure, signals, context)
    }

    // MARK: - Focus

    private static func focusedElement(app: AXUIElement?, system: AXUIElement, signals: inout [String]) -> AXUIElement? {
        if let app, let el = element(app, kAXFocusedUIElementAttribute as CFString) { signals.append("focus=app"); return el }
        if let el = element(system, kAXFocusedUIElementAttribute as CFString) { signals.append("focus=system"); return el }
        // via the focused window
        let root = app ?? system
        if let win = element(root, kAXFocusedWindowAttribute as CFString) ?? element(root, kAXMainWindowAttribute as CFString),
           let el = element(win, kAXFocusedUIElementAttribute as CFString) {
            signals.append("focus=window"); return el
        }
        signals.append("focus=none")
        return nil
    }

    // MARK: - Caret probe (the main signal)

    private static func caretFrame(_ element: AXUIElement) -> CGRect? {
        // marker range (more precise on the web)
        if let marker = copyValue(element, "AXSelectedTextMarkerRange" as CFString) {
            var raw: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, marker, &raw) == .success,
               let rect = cgRect(raw), isPlausibleCaret(rect) { return rect }
        }
        guard let rangeRaw = copyValue(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(rangeRaw) == AXValueGetTypeID() else { return nil }
        let rangeVal = unsafeDowncast(rangeRaw, to: AXValue.self)
        guard AXValueGetType(rangeVal) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeVal, .cfRange, &range) else { return nil }

        // Ask for a COLLAPSED range at the insertion point, NOT the whole selection: for a selection
        // of length N `AXBoundsForRange` returns the bounds of the whole selection (in Xcode this gave
        // 673×2286 at y=-1219 — the document bounds, not the caret; no place for the pill there).
        let probes = [
            CFRange(location: range.location, length: 0),
            CFRange(location: range.location, length: 1),
            CFRange(location: max(range.location - 1, 0), length: 1)
        ]
        for candidate in probes {
            var c = candidate
            guard let cVal = AXValueCreate(.cfRange, &c) else { continue }
            var raw: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, cVal, &raw) == .success,
               let rect = cgRect(raw), isPlausibleCaret(rect) { return rect }
        }
        return nil
    }

    /// A caret is a thin vertical bar one line tall. Anything bigger is the bounds of a
    /// selection/field/document: useless as an anchor for the pill and pushes it off screen.
    private static func isPlausibleCaret(_ rect: CGRect) -> Bool {
        rect.height > 0 && rect.height <= 200 && rect.width <= 60
    }

    // MARK: - "Is it a field" classification

    /// The role is definitely NON-text (AXWebArea/AXButton/…). Checked FIRST in all tiers.
    private static func isVetoed(_ element: AXUIElement) -> Bool {
        guard let role = copyString(element, kAXRoleAttribute as CFString) else { return false }
        return nonTextRoles.contains(role)
    }

    // MARK: - Secure context (password)

    /// Cheap check "focus is in a secure field right now" — WITHOUT hit test and BFS.
    ///
    /// Call **right before synthetic Cmd+A/Cmd+C/Cmd+V**, rather than relying on
    /// `Resolution.isSecure`: (a) an LLM request passes between `resolve()` and sending keys, and
    /// focus may have moved into a password field; (b) keys go to the OS's REAL keyboard focus, not
    /// to an element found by heuristics (a hit test at an old click/BFS may return a different,
    /// non-secure element — then a gate on it lies).
    ///
    /// Two independent signals, each best-effort on its own:
    /// 1. `IsSecureEventInputEnabled()` — the OS holds Secure Input Mode while focus is in a password
    ///    field. App-agnostic, covers web/Electron where the subrole isn't exposed. A false positive
    ///    is possible if another app left the mode on (then text extraction won't work — a deliberate
    ///    trade-off in favor of security; the log shows the `secure_input_mode` signal).
    /// 2. The `AXSecureTextField` AX subrole on the DIRECT focus — reliable for native `NSSecureTextField`.
    static func isSecureNow() -> Bool {
        var signals: [String] = []
        let secure = secureContext(focused: directFocus(), signals: &signals)
        // Log EXACTLY here: this is the real refusal point in all features, and on a complaint
        // "hotkeys stopped working" the log must show WHICH signal fired (see `stuck_mode`).
        if secure {
            Log.warn(.caret, "isSecureNow → BLOCK | \(signals.joined(separator: " | "))")
        }
        return secure
    }

    /// Watching for a "stuck" mode.
    ///
    /// A known browser bug: when a login form is closed with Enter, the system Secure Input Mode
    /// sometimes stays on until the browser restarts — and then ALL text features silently stop
    /// working IN ALL apps. For a real password field a silent refusal is right; for a stuck mode
    /// it reads as "Keyly is broken", and the user doesn't know what to fix.
    ///
    /// A single snapshot can't tell them apart: web and Electron password fields have no
    /// `AXSecureTextField` subrole, so "flag on, no subrole" is BOTH a stuck mode AND an honest
    /// password field in Chrome. The discriminator is TIME: a real password field lives in one
    /// app, while a stuck mode survives a frontmost app change.
    private struct SecureModeWatch {
        var firstSeenFront: String?
        var survivedFrontChange = false
    }
    nonisolated(unsafe) private static var secureWatch = SecureModeWatch()

    /// Whether it looks like a STUCK mode. Errs only toward the regular badge — saying "another
    /// app is to blame" when the user really is typing a password is worse.
    static func secureInputLooksStuck() -> Bool {
        guard IsSecureEventInputEnabled() else {
            secureWatch = SecureModeWatch()
            return false
        }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "(unknown)"
        if secureWatch.firstSeenFront == nil {
            secureWatch.firstSeenFront = front
        } else if secureWatch.firstSeenFront != front {
            secureWatch.survivedFrontChange = true
        }
        // Third signal: the direct focus is NOT a password field. If the subrole is secure — it's an honest field.
        if let focused = directFocus(),
           copyString(focused, kAXSubroleAttribute as CFString) == "AXSecureTextField" {
            return false
        }
        return secureWatch.survivedFrontChange
    }

    private static func secureContext(focused: AXUIElement?, signals: inout [String]) -> Bool {
        if IsSecureEventInputEnabled() {
            signals.append("secure_input_mode")
            // Who is frontmost is the key to diagnosing a "stuck" mode: another app (a known browser
            // bug) may have left Secure Input Mode on, and then we block EVERYTHING system-wide. If the
            // log's `front=` is an app without password fields, that's exactly the cause.
            // In `resolve()` front is already added by the caller — don't duplicate it.
            if !signals.contains(where: { $0.hasPrefix("front=") }) {
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "(unknown)"
                signals.append("front=\(front)")
            }
            return true
        }
        if let focused, copyString(focused, kAXSubroleAttribute as CFString) == "AXSecureTextField" {
            signals.append("secure_subrole"); return true
        }
        return false
    }

    /// The direct keyboard focus, without hit test/BFS heuristics — this is where synthetic keys
    /// go. Same tiers as `focusedElement()` (app → system-wide → via focused window): otherwise a
    /// field visible only via the window fallback wouldn't be checked for secure.
    private static func directFocus() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var app: AXUIElement?
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let a = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(a, messagingTimeout)
            app = a
        }
        var sink: [String] = [] // focus tier signals aren't needed here
        return focusedElement(app: app, system: system, signals: &sink)
    }

    /// Verdict for one element. `denied` — AX EXPLICITLY said "not writable": this is not "found no
    /// evidence" but evidence AGAINST, and it must stop the fallbacks (otherwise the app allowlist
    /// would override the system's direct answer).
    private enum InputVerdict { case yes, unknown, denied }

    /// The role is the control's CLASS, not its editability: `AXTextArea` is carried by ANY
    /// `NSTextView`, including read-only ones (Mail's reading pane, Xcode console, Console.app). So
    /// the role works as a filter, and the proof is whether the value is settable.
    private static func isTextInputElement(_ element: AXUIElement, signals: inout [String]) -> InputVerdict {
        let role = copyString(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = copyString(element, kAXSubroleAttribute as CFString) ?? ""
        let roleMatches = textRoles.contains(role) || textSubroles.contains(subrole)

        // 1. The explicit editability flag — the most direct answer, both ways.
        if let editable = copyBool(element, "AXEditable" as CFString) {
            if editable { signals.append("✓ax_editable"); return .yes }
            signals.append("✗ax_editable=false"); return .denied
        }

        // 2. Whether the VALUE is settable. That's exactly what distinguishes a field from read-only
        // text: both can be selected (so there's a caret and the range is settable), but only one is writable.
        switch settable(element, kAXValueAttribute as CFString) {
        case .some(true):
            signals.append("✓value_settable"); return .yes
        case .some(false):
            // A NEGATIVE counts ONLY for a text-like role: a read-only `AXTextArea` (Mail's reading
            // pane, Xcode console) is an honest "not writable". But for a CONTAINER (AXGroup/AXRow in
            // Electron) a non-settable value says nothing — it must not suppress the other tiers,
            // otherwise real fields under that container are lost.
            if roleMatches, copyValue(element, kAXValueAttribute as CFString) != nil {
                signals.append("✗value_readonly(role=\(role))"); return .denied
            }
        case nil:
            break // attribute not supported — can't judge by it
        }

        // 3. AX didn't answer (common in Electron/web) — accept the role as weak grounds.
        if roleMatches { signals.append("✓role=\(role)"); return .yes }
        if settable(element, kAXSelectedTextRangeAttribute as CFString) == true {
            signals.append("✓range_settable"); return .yes
        }
        return .unknown
    }

    // MARK: - Hit test at the click

    private static func hitTest(app: AXUIElement, pid: pid_t, signals: inout [String]) -> AXUIElement? {
        guard let cocoa = ClickTracker.shared.recentClickPoint(inPID: pid) else { return nil }
        let ax = cocoaToAX(cocoa)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(ax.x), Float(ax.y), &hit) == .success, var cur = hit else { return nil }
        signals.append("hit_test")
        // Deadline as for BFS: 8 climbs × ~7 AX calls × 0.16s timeout = up to ~10s of synchronous
        // main actor blocking if the target app hangs (and this tier targets exactly Chrome/Electron,
        // whose AX bridge hangs along with the renderer) — it would freeze all of Keyly.
        let deadline = ProcessInfo.processInfo.systemUptime + scanBudget
        for _ in 0..<8 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { signals.append("hit_test_timeout"); break }
            AXUIElementSetMessagingTimeout(cur, messagingTimeout)
            if !isVetoed(cur) {
                // IMPORTANT: a caret here is NOT accepted as proof. A caret rect means "there is a
                // text position here", not "this is writable": a click on plain page text in Safari
                // also returns a rect (the selection cursor position), and this used to falsely give
                // .caret — ErrorFix would do Cmd+A/Cmd+C on the WHOLE page and send it to the LLM. The
                // hit test walks NON-focused elements under the cursor, so editability must be proven
                // explicitly (as in the BFS tier).
                var s: [String] = []
                if isTextInputElement(cur, signals: &s) == .yes { signals.append(contentsOf: s); return cur }
            }
            guard let parent = element(cur, kAXParentAttribute as CFString), !CFEqual(parent, cur) else { break }
            cur = parent
        }
        return nil
    }

    // MARK: - Subtree BFS

    private static func scan(root: AXUIElement?, deadline: TimeInterval, signals: inout [String]) -> AXUIElement? {
        guard let root else { return nil }
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var idx = 0, scanned = 0
        var visited = Set<Int>()
        while idx < queue.count, scanned < maxScanned, ProcessInfo.processInfo.systemUptime < deadline {
            let (el, depth) = queue[idx]; idx += 1
            guard visited.insert(Int(bitPattern: CFHash(el))).inserted else { continue }
            scanned += 1
            AXUIElementSetMessagingTimeout(el, messagingTimeout)
            var s: [String] = []
            if !isVetoed(el), isTextInputElement(el, signals: &s) == .yes {
                signals.append(contentsOf: s); signals.append("scan_hit(\(scanned))"); return el
            }
            guard depth < maxDepth else { continue }
            for child in elementArray(el, kAXChildrenAttribute as CFString) { queue.append((child, depth + 1)) }
        }
        return nil
    }

    // MARK: - Recently typed (fallback)

    private static func recentlyTyped() -> Bool {
        guard let last = InputMonitor.shared.lastRelevantEvent(), last.kind == .character else { return false }
        return Date().timeIntervalSince(last.timestamp) < 3.0
    }

    // MARK: - Coordinates

    /// The AX rect is already in top-left-origin screen coordinates — return as is (validated by cgRect()).
    private static func toScreen(_ rect: CGRect) -> CGRect { rect }

    /// Cocoa (bottom-left, `NSEvent.mouseLocation`) → AX (top-left) using the main screen height.
    /// TODO: multi-monitor — use the screen containing the point.
    private static func cocoaToAX(_ p: CGPoint) -> CGPoint {
        let h = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        return CGPoint(x: p.x, y: h - p.y)
    }

    // MARK: - AX helpers

    private static func element(_ el: AXUIElement, _ attr: CFString) -> AXUIElement? {
        guard let raw = copyValue(el, attr), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }
    private static func elementArray(_ el: AXUIElement, _ attr: CFString) -> [AXUIElement] {
        guard let raw = copyValue(el, attr), CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
        let arr = raw as! [AnyObject]
        return arr.compactMap { $0 as! AXUIElement? }.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }
    }
    private static func copyValue(_ el: AXUIElement, _ attr: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr, &value) == .success ? value : nil
    }
    private static func copyString(_ el: AXUIElement, _ attr: CFString) -> String? { copyValue(el, attr) as? String }
    private static func copyBool(_ el: AXUIElement, _ attr: CFString) -> Bool? { copyValue(el, attr) as? Bool }
    /// `nil` = couldn't ask (attribute not supported / error). Distinguishing this from an honest
    /// `false` is critical: "not settable" proves read-only, "couldn't ask" proves nothing.
    private static func settable(_ el: AXUIElement, _ attr: CFString) -> Bool? {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(el, attr, &settable) == .success else { return nil }
        return settable.boolValue
    }
    private static func cgRect(_ raw: CFTypeRef?) -> CGRect? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let v = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetType(v) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v, .cgRect, &rect),
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect
    }

    private static func finish(_ c: Confidence, _ el: AXUIElement?, _ rect: CGRect?, _ editable: Bool,
                               secure: Bool, _ signals: [String], _ context: String) -> Resolution {
        Log.info(.caret, "[\(context)] \(c) | \(signals.joined(separator: " | "))")
        return Resolution(confidence: c, element: el, caretRect: rect, isEditable: editable, isSecure: secure, signals: signals)
    }
}
