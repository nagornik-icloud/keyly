import AppKit
import SwiftUI

/// Show a short message at the caret. A narrow protocol — features don't need to know about windows.
@MainActor
protocol BadgePresenting: AnyObject {
    /// `caretRect` is the caret rectangle already known to the caller (AX coordinates). Passing
    /// it is mandatory if the feature has just run `CaretProbe.resolve`: otherwise the controller
    /// repeats the whole tree walk (up to ~0.28 s on the main actor) for the same position.
    func showBadge(_ text: String, kind: BadgeView.Kind, caretRect: CGRect?)
    func hideBadge()
    /// Hide the badge ONLY if this exact kind is currently shown.
    ///
    /// Needed for removing progress in `defer`: the "Fixing… → No errors found" path is synchronous,
    /// and an unconditional `hideBadge()` from defer hid the message shown one line above in the
    /// same frame — the user saw a flash instead of an answer.
    func hideBadge(onlyIf kind: BadgeView.Kind)
}

extension BadgePresenting {
    func showBadge(_ text: String, kind: BadgeView.Kind) {
        showBadge(text, kind: kind, caretRect: nil)
    }
}

/// The badge window.
///
/// Three decisions, each learned the hard way:
/// - **Anchored to the caret**, falling back to the menu bar icon. The old "next to the mouse cursor"
///   was dropped: when working from the keyboard the mouse is nowhere near where the user is looking.
/// - **The window ignores the mouse** (`ignoresMouseEvents`): a clickable badge eats the user's next
///   click. It closes on a timer and on Esc, not on click.
/// - **Doesn't activate the app** (`.nonactivatingPanel`, no `makeKey`): otherwise the badge steals
///   focus from the field we were just working in — and the very next feature won't find the caret.
@MainActor
final class BadgeController: BadgePresenting {

    private var panel: NSPanel?
    private var hosting: NSHostingView<BadgeView>?
    private var hideTask: DispatchWorkItem?
    private var escMonitor: Any?
    private var currentKind: BadgeView.Kind?
    /// Bottom-left corner of the PLATE from the previous show. Reused when the content changes on a
    /// visible window: between "Fixing…" and the result there is Cmd+A and a network request, AX
    /// returns a different caret rectangle — and an "in-place change" would turn into the plate
    /// moving right where the user is looking.
    private var lastPlateOrigin: NSPoint?
    /// Show counter. Deferred tasks (auto-hide, fade-out completion) check it and do NOTHING if the
    /// badge was shown again in the meantime: otherwise the previous fade-out completion calls
    /// `orderOut` on the new badge and hides it.
    private var generation = 0

    /// A regular message stays 2–3 s, an error longer (~5 s).
    private static let infoDuration: TimeInterval = 2.5
    private static let warningDuration: TimeInterval = 5.0
    /// Progress stays until explicitly removed — but not forever: if the feature crashed and forgot
    /// to hide the badge, it must not stay on screen until restart.
    private static let progressDuration: TimeInterval = 30.0

    // The ceiling was raised along with the font size: at 14pt the old 320 would cut lines
    // that fit at 12pt.
    private static let maxWidth: CGFloat = 380

    func showBadge(_ text: String, kind: BadgeView.Kind, caretRect: CGRect? = nil) {
        hideTask?.cancel()
        generation += 1
        let token = generation
        let wasVisible = panel?.isVisible == true && currentKind != nil
        currentKind = kind

        if text.count > BadgeView.maxCharacters {
            // Contract: "badge = one short line" (see the BadgeView docs). We don't truncate silently:
            // a copy edit or localization (RU→DE adds 20–30 %) would otherwise eat the tail, and the
            // status would turn into nonsense mid-word.
            Log.warn(.ui, "Бейдж: строка \(text.count) симв. > \(BadgeView.maxCharacters) — будет обрезана, нужен тост")
        }

        let view = BadgeView(text: text, kind: kind)
        let panel = existingPanel()
        let host: NSHostingView<BadgeView>
        if let existing = hosting {
            host = existing
            host.rootView = view
        } else {
            host = NSHostingView(rootView: view)
            panel.contentView = host
            hosting = host
        }
        let size = fittingSize(of: host)
        // Re-anchor only when showing from the hidden state or when a rect was passed explicitly.
        let reuseAnchor = wasVisible && caretRect == nil
        let plateOrigin = (reuseAnchor ? lastPlateOrigin : nil) ?? plateOrigin(for: size, caretRect: caretRect)
        lastPlateOrigin = plateOrigin
        let margin = Theme.Elevation.pillShadowMargin
        let frame = NSRect(origin: NSPoint(x: plateOrigin.x - margin, y: plateOrigin.y - margin), size: size)

        if wasVisible {
            // In-place content change: don't reset alpha and don't jump the frame. Otherwise, right
            // where the user is looking, the plate fades to zero, changes width and shifts
            // horizontally — the "Fixing… → result" transition reads as a glitch.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }

        installEscMonitor()
        let duration: TimeInterval
        switch kind {
        case .info:     duration = Self.infoDuration
        case .warning:  duration = Self.warningDuration
        case .progress: duration = Self.progressDuration
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.hideBadge()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
        Log.info(.ui, "Бейдж: \(kind) на \(Int(duration))с")
    }

    func hideBadge() {
        hideTask?.cancel()
        hideTask = nil
        currentKind = nil
        lastPlateOrigin = nil
        removeEscMonitor()
        guard let panel else { return }
        generation += 1
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            // Leaving is faster than appearing — so the disappearance doesn't feel like a delay.
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A new badge may have arrived within 0.12 s — then the window must not be hidden.
            guard let self, self.generation == token else { return }
            panel.orderOut(nil)
        })
    }

    func hideBadge(onlyIf kind: BadgeView.Kind) {
        guard currentKind == kind else { return }
        hideBadge()
    }

    // MARK: - Window

    private func existingPanel() -> NSPanel {
        if let panel { return panel }
        let created = NSPanel(contentRect: .zero,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        // The plate is always dark, so the content is judged in the dark scheme too: the system
        // ProgressView in system Light draws with a light palette and disappears on the plate —
        // in exactly the state the icons were introduced to make distinguishable.
        created.appearance = NSAppearance(named: .darkAqua)
        created.isFloatingPanel = true
        created.level = .statusBar
        created.backgroundColor = .clear
        created.isOpaque = false
        created.hasShadow = false          // the view draws the shadow itself, otherwise it would be doubled
        created.ignoresMouseEvents = true  // see the class docs
        created.hidesOnDeactivate = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel = created
        return created
    }

    /// Window size = plate + room for the shadow on all sides. There is NO minimum width: on a short
    /// line ("Done") it produced dead space on the right.
    private func fittingSize(of hosting: NSHostingView<BadgeView>) -> CGSize {
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        return CGSize(width: min(ceil(fitted.width), Self.maxWidth + 2 * Theme.Elevation.pillShadowMargin),
                      height: ceil(fitted.height))
    }

    /// Position: under the caret, otherwise under the menu bar icon, otherwise top center of the screen.
    /// Always clamped to the visible area — otherwise a plate near a caret at the bottom of the screen slides off.
    ///
    /// Coordinates are computed for the PLATE, and the window is larger by `shadowMargin` on all
    /// sides — so the window origin is offset by that margin.
    private func plateOrigin(for size: CGSize, caretRect: CGRect?) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = Theme.Elevation.pillShadowMargin
        let plate = CGSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        let gap = Theme.Space.s

        // ALWAYS top center, like the recording badge, by design. At the caret the message covered
        // the very line the user is looking at, and it showed up in different places on screen —
        // a predictable spot is read faster than a nearby one.
        var plateOrigin = NSPoint(x: visible.midX - plate.width / 2,
                                  y: visible.maxY - plate.height - Theme.Space.xl)

        plateOrigin.x = min(max(plateOrigin.x, visible.minX + gap), visible.maxX - plate.width - gap)
        plateOrigin.y = min(max(plateOrigin.y, visible.minY + gap), visible.maxY - plate.height - gap)
        return plateOrigin
    }

    private func menuBarIconFrame() -> NSRect? {
        // The icon is owned by MenuBarController; its window is a reliable way to get the position.
        NSApp.windows.first { $0.className.contains("NSStatusBarWindow") }?.frame
    }

    // MARK: - Esc

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }   // Esc
            Task { @MainActor in self?.hideBadge() }
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }
}
