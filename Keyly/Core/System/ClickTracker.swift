import AppKit

/// Passive monitor of the last mouse click — input for the caret hit test in `CaretProbe`.
///
/// Listens to global mouse-down via `NSEvent.addGlobalMonitorForEvents`. This is a PASSIVE
/// monitor: it neither swallows nor posts events, so it cannot cause event-tap re-entrancy
/// (our own synthetic events do not come through it as input).
///
/// `NSEvent.mouseLocation` is in Cocoa screen coordinates (origin bottom-left). Accessibility
/// (`AXUIElementCopyElementAtPosition`) expects top-left coordinates — `CaretProbe` converts
/// using the height of the screen containing this point.
@MainActor
final class ClickTracker {
    static let shared = ClickTracker()

    private var monitor: Any?
    private(set) var lastClickPoint: CGPoint?
    private(set) var lastClickAt: Date?
    private(set) var lastClickPID: pid_t?   // app under the click — so we don't hit-test some other window after Cmd+Tab

    private init() {}

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // The callback arrives on the main thread; hop to @MainActor via Task so stored props are never touched outside the actor.
            let point = NSEvent.mouseLocation
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            Task { @MainActor in
                self?.lastClickPoint = point
                self?.lastClickAt = Date()
                self?.lastClickPID = pid
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// A recent click (younger than `maxAge`) in exactly the app `pid` — otherwise it is useless
    /// or even harmful for hit testing (a click in another app before Cmd+Tab → coordinates belong
    /// to a different window).
    func recentClickPoint(inPID pid: pid_t, maxAge: TimeInterval = 8.0) -> CGPoint? {
        guard let at = lastClickAt, Date().timeIntervalSince(at) < maxAge,
              let clickPID = lastClickPID, clickPID == pid else { return nil }
        return lastClickPoint
    }
}
