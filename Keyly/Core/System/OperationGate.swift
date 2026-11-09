import AppKit

/// One text operation at a time + cancel with Esc.
///
/// Why a shared lock. All six text services go through ONE shared resource — the clipboard and
/// synthetic Cmd+A/C/V sent to the current focus. Two overlapping operations are not just
/// "slower", they corrupt each other: the first snapshots the clipboard, the second writes its
/// own text there, the first restores — and the second one's text is gone. And hotkeys get
/// pressed twice all the time, because an LLM request takes seconds and looks like "didn't work".
///
/// Esc LIVES with the lock, not separately: the only operation worth cancelling is the one that
/// holds the lock, and the key monitor's lifetime matches that operation's lifetime.
@MainActor
enum OperationGate {

    /// What is running right now — for the log and for deciding whether it can be interrupted.
    enum Kind: String {
        case layout      = "раскладка"
        case errorFix    = "опечатки"
        case module      = "модуль"
        case voice       = "голос"
        case snippet     = "сниппет"
        case undo        = "отмена"
    }

    /// Lock ownership. Released automatically on deinit — a service only has to hold the token
    /// in `defer`, so forgetting `end()` is impossible.
    final class Token {
        let kind: Kind
        /// What to do on Esc. Operations that can stop immediately (voice recording) set a
        /// handler here; those that can only "finish and discard the result" poll
        /// `cancelledNow()` between steps instead.
        var onCancel: (() -> Void)?
        private var released = false
        init(kind: Kind) { self.kind = kind }
        func release() {
            guard !released else { return }
            released = true
            MainActor.assumeIsolated { OperationGate.finish(self) }
        }
        deinit { if !released { Task { @MainActor in OperationGate.forceFinish() } } }
    }

    private(set) static var current: Token?
    private(set) static var isCancelled = false
    private static var escMonitor: Any?

    static weak var badgePresenter: BadgePresenting?

    /// Tries to take the lock. `nil` means busy — the caller must bail out.
    ///
    /// The badge is shown HERE, not in each service: otherwise six places would print six
    /// different wordings of the same refusal, and half would forget to show it at all.
    static func begin(_ kind: Kind) -> Token? {
        if let current {
            Log.warn(.app, "OperationGate: занято (\(current.kind.rawValue)), отклонено: \(kind.rawValue)")
            badgePresenter?.showBadge(BadgeText.alreadyBusy, kind: .warning)
            return nil
        }
        let token = Token(kind: kind)
        current = token
        isCancelled = false
        startEscMonitor()
        Log.info(.app, "OperationGate: начата операция «\(kind.rawValue)»")
        return token
    }

    /// Whether the user cancelled the current operation. Long steps (retry loops, network waits)
    /// must check this between steps — otherwise Esc "works" only after everything is done.
    static func cancelledNow() -> Bool { isCancelled }

    private static func finish(_ token: Token) {
        guard current === token else { return }   // someone else's token — the lock was already taken over
        Log.info(.app, "OperationGate: завершена операция «\(token.kind.rawValue)»\(isCancelled ? " (отменена)" : "")")
        current = nil
        stopEscMonitor()
    }

    /// Emergency release: the token was destroyed without being released. That alone signals
    /// a missing `defer`, so it is logged as an error rather than silently fixed.
    private static func forceFinish() {
        guard current != nil else { return }
        Log.error(.app, "OperationGate: токен уничтожен без release() — замок снят аварийно")
        current = nil
        stopEscMonitor()
    }

    // MARK: - Esc

    /// The monitor is GLOBAL and observe-only: Esc still reaches the app under the cursor.
    /// Swallowing it with a tap is not allowed — Esc closes other apps' modals and exits editor
    /// modes, and taking it away for the whole network request would break the user's work
    /// more than it helps ours.
    /// The local monitor covers the case when the frontmost app is US.
    ///
    /// By design `addGlobalMonitorForEvents` gets no events while our own window is active: the
    /// snippet palette deliberately takes focus, and Esc there never reached the lock. Two
    /// monitors cover both sides.
    private static var localEscMonitor: Any?

    private static func startEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }   // Esc
            MainActor.assumeIsolated { handleEsc() }
        }
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { handleEsc() }
            // Pass the event ON: Esc is never swallowed. Otherwise it would stop closing
            // sheets and popovers in our own window, and the app would break a standard key
            // for the sake of its own cancel.
            return event
        }
    }

    /// Esc handling. The priority order is set EXPLICITLY, not by the order observers happened
    /// to register: the key has four claimants (voice recording, palette, current operation,
    /// visible badge), and "whatever happens" means different behavior in situations that look
    /// the same.
    ///
    /// The lock is the second level: voice recording and the palette hold it themselves and set
    /// `onCancel`, so the token's handler is their branch. The badge is last: it closes on a
    /// timer and needs no separate interception.
    @MainActor
    private static func handleEsc() {
        guard let token = current, !isCancelled else { return }
        isCancelled = true
        Log.warn(.app, "OperationGate: Esc — операция «\(token.kind.rawValue)» отменяется")
        badgePresenter?.showBadge(BadgeText.cancelled, kind: .info)
        // Call the handler AFTER setting the flag: it may release the lock synchronously,
        // and whoever observes that must already see `isCancelled`.
        token.onCancel?()
    }

    private static func stopEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
        if let localEscMonitor { NSEvent.removeMonitor(localEscMonitor) }
        localEscMonitor = nil
    }
}
