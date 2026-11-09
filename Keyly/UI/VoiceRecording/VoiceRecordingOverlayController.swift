import AppKit
import SwiftUI

@MainActor
final class VoiceRecordingOverlayController: VoiceRecordingOverlayPresenting {
    private var window: NSWindow?
    /// Pill phase, kept here so the look changes WITHOUT recreating the window: recreating
    /// would blink exactly when the user is waiting to learn whether they were heard.
    private let state = VoiceOverlayState()
    /// Observer of frontmost app changes.
    private var focusObserver: NSObjectProtocol?
    /// Observer of Space changes: the pill must be visible on EVERY Space (see below).
    private var spaceObserver: NSObjectProtocol?
    /// The pill has already moved to its place: do not move it again and do not move it back.
    private var isPinnedToTop = false

    /// Where the user chose to show the pill. Remembered for the session.
    ///
    /// All three "moves" (focus leaving, Space change and the switch to processing)
    /// used to be hardwired to `.topCenter`. So the "show at bottom center" setting worked
    /// only until the first of these events, and the processing phase ALWAYS IGNORED it: the user
    /// put the pill at the bottom, and recognition still popped up at the top.
    private var placement: VoiceIndicatorPlacement = .default
    private let showDuration: TimeInterval = 0.4
    private let hideDuration: TimeInterval = 0.4

    func showVoiceRecordingOverlay(
        elapsedProvider: @escaping () -> Int,
        onCancel: @escaping () -> Void,
        placement: VoiceIndicatorPlacement
    ) {
        guard let targetScreen = NSScreen.main ?? NSScreen.screens.first else { return }

        copiedHideWork?.cancel()
        copiedHideWork = nil
        state.phase = .recording
        isPinnedToTop = false
        self.placement = placement

        // A COMPACT pill at top center ("Top center" mode), NOT a full-screen
        // window with dimming. The previous version covered the whole screen, dimmed everything below
        // it by 42% and intercepted clicks: dictation is a background action, yet it looked like
        // a modal dialog demanding attention. Such a mode was never intended.
        // Near the caret the pill is COMPACT: a full-size one would cover the line
        // the user is dictating into, i.e. hide exactly what it is shown for.
        let content = VoiceRecordingView(elapsedProvider: elapsedProvider,
                                         onCancel: onCancel,
                                         compact: true,
                                         state: state)
        // Margin around the capsule for the shadow: a window exactly the capsule's size clips the blur,
        // and a straight edge shows where it is clipped: dark corners with sharp
        // 90-degree angles.
        let hosting = NSHostingView(rootView: content.padding(Self.shadowMargin))
        // NSHostingView paints its layer opaque by default; that is what produced
        // the dark backing under the rounded capsule. The window is transparent, but the view inside is not.
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let overlayWindow = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayWindow.contentView = hosting
        overlayWindow.isReleasedWhenClosed = false
        // Same level as the streaming indicator: one product surface cannot
        // live at two different heights depending on the recognition mode. Above the status bar,
        // so nothing covers the pill while recording is running.
        overlayWindow.level = .screenSaver
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        // The capsule draws its OWN shadow; the window provides none. With a system shadow around
        // the rounded capsule, the rectangular dark outline of the backing showed through
        // as a sharp corner edge.
        overlayWindow.hasShadow = false
        // On ALL Spaces and over fullscreen apps: the pill must always stay on screen,
        // whichever Space the user switches to. It used to be on one Space only, and a user who moved to a neighboring
        // Space or into a fullscreen app
        // lost the only sign that recording was running.
        //
        // The earlier objection ("on another Space the pill sits at the caret's coordinates and
        // points nowhere") is resolved not by giving up all Spaces but by moving: a Space change, like
        // an app change, pins the pill to top center, where it claims nothing
        // and reads on any Space.
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                            .fullScreenAuxiliary, .ignoresCycle]
        // Mouse events pass THROUGH: no interactive elements are left on the pill (the
        // Cancel button was replaced by Esc), and around the capsule there is now a wide transparent shadow margin;
        // if it caught events, it would eat clicks on another window in a spot that looks empty.
        overlayWindow.ignoresMouseEvents = true

        overlayWindow.setFrameOrigin(Self.plateOrigin(placement: placement,
                                                      size: size,
                                                      screen: targetScreen))
        overlayWindow.alphaValue = 0
        overlayWindow.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = showDuration
            overlayWindow.animator().alphaValue = 1
        }

        window?.close()
        window = overlayWindow
        occupySlotIfOnTop(height: size.height)
        watchFocusChange()
    }

    /// Recording ended, recognition is running. The pill is NOT removed, it changes its look.
    /// Shows "Done · copied to clipboard" for a moment, then hides the plate by itself.
    /// A new recording started meanwhile cancels the pending hide.
    @discardableResult
    func markVoiceOverlayCopied() -> Bool {
        guard window != nil else { return false }
        state.phase = .copied
        refitToPlace()
        let work = DispatchWorkItem { [weak self] in self?.hideVoiceRecordingOverlay() }
        copiedHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + copiedDuration, execute: work)
        return true
    }

    private var copiedHideWork: DispatchWorkItem?
    private let copiedDuration: TimeInterval = 1.2

    func markVoiceOverlayProcessing() {
        guard window != nil else { return }
        state.phase = .processing
        Log.info(.voice, "Плашка записи: перешла в фазу «обработка»")
        refitToPlace()
    }

    /// Re-measures the plate after a phase change and moves it to its own place.
    private func refitToPlace() {
        guard let window else { return }
        // The "Processing…" caption is wider than the timer, so the window must be re-measured. Do it
        // on the NEXT tick: SwiftUI does not apply the `phase` change inside this call, and
        // `fittingSize` taken right here would return the previous phase's size.
        DispatchQueue.main.async { [weak self] in
            // Check window IDENTITY, not just that the controller is alive. `window` is captured
            // strongly and outlives the pill's removal: `hideVoiceRecordingOverlay` nils
            // `self.window` immediately but closes the window itself only at the end of the animation (0.4s).
            // Without this check, a block queued before removal ran after
            // it and RE-OCCUPIED `TopCenterOverlaySlot` with the dead pill's height;
            // nobody was left to release it, and every toast until the next dictation
            // sat with a phantom offset under a nonexistent pill.
            // Real path: `stopAndTranscribe` calls this method SYNCHRONOUSLY and may then
            // exit via the "no audio file" `guard`, so the race is reachable without a single await.
            guard let self, self.window === window, let hosting = window.contentView else { return }
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            guard let screen = window.screen ?? NSScreen.main else { return }
            // Processing now happens outside the field where we started; the caret pill has nothing
            // more to show there. Move TO ITS OWN PLACE, as when focus leaves, and take the new size
            // in the same motion: two separate steps would jerk.
            let origin = Self.plateOrigin(placement: self.placement, size: size, screen: screen)
            let target = NSRect(origin: origin, size: size)
            self.isPinnedToTop = true
            self.occupySlotIfOnTop(height: size.height)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(target, display: true)
            }
        }
    }

    /// Focus left the field where recording started -> the pill moves to top center and
    /// stays there until recording ends. The same happens on a Space change.
    ///
    /// We do not move it back to the caret: a pill jumping after focus distracts more than
    /// a still one, and recording is still running, and the user must see that it is.
    private func watchFocusChange() {
        if focusObserver == nil {
            focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.pinToConfiguredPlace() }
            }
        }
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.followActiveSpace() }
            }
        }
    }

    /// The user switched to another Space. The pill follows: it already shows on
    /// all Spaces (`canJoinAllSpaces`), but caret coordinates on another Space are meaningless,
    /// so pin it to top center of the screen that became active.
    @MainActor
    private func followActiveSpace() {
        guard let window, window.isVisible else { return }
        isPinnedToTop = false            // allow moving again: the screen may have changed
        pinToConfiguredPlace()
        window.orderFrontRegardless()    // new Space: raise above other windows again
        Log.info(.voice, "Плашка записи: сменился рабочий стол — переехали на своё место (\(placement.rawValue))")
    }

    /// Reserve the toast offset ONLY when the pill is actually at the top.
    ///
    /// `TopCenterOverlaySlot` shifts the toast DOWN so it does not overlap the pill. With the pill
    /// at the bottom there is nothing to shift from: the toast would move away from empty space and
    /// could still overlap the pill at the bottom.
    private func occupySlotIfOnTop(height: CGFloat) {
        switch placement {
        case .topCenter, .topTrailing: TopCenterOverlaySlot.occupy(height: height)
        case .bottomCenter:            TopCenterOverlaySlot.release()
        }
    }

    @MainActor
    private func pinToConfiguredPlace() {
        guard let window, window.isVisible, !isPinnedToTop else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        isPinnedToTop = true
        // THE SAME math as the initial position. There used to be a separate calculation here with
        // a `Space.xl` offset and NO correction for the shadow margin that is part of the window
        // size: a pill moved to the top ended up ~30pt lower than one
        // placed there directly, i.e. it jumped down for no reason.
        let target = Self.plateOrigin(placement: placement,
                                      size: window.frame.size,
                                      screen: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().setFrameOrigin(target)
        }
    }

    private func stopWatchingFocus() {
        if let focusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(focusObserver)
        }
        focusObserver = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        isPinnedToTop = false
    }

    /// Where the pill sits.
    ///
    /// ABOVE the caret: the line the user is dictating into is the only spot on screen
    /// that must not be covered; that is where they are looking. A previous version put the pill
    /// "below the caret", but the caret height is small, and the pill landed right on the line.
    ///
    /// Static and pure so the rule is testable: the window position on screen
    /// can only be checked by eye at runtime, the coordinate conversion math by a test.
    /// Three positions to choose from.
    ///
    /// `size` already includes the shadow margin (`shadowMargin`), so we inset from the screen
    /// edges by the same margin; otherwise the visible capsule would end up farther from the edge
    /// than intended by exactly the invisible margin.
    static func plateOrigin(placement: VoiceIndicatorPlacement,
                            size: NSSize,
                            screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let inset = Theme.Space.l - shadowMargin
        switch placement {
        case .topCenter:
            return NSPoint(x: visible.midX - size.width / 2,
                           y: visible.maxY - size.height - inset)
        case .bottomCenter:
            return NSPoint(x: visible.midX - size.width / 2,
                           y: visible.minY + inset)
        case .topTrailing:
            return NSPoint(x: visible.maxX - size.width - inset,
                           y: visible.maxY - size.height - inset)
        }
    }

    /// Margin around the capsule for shadow blur, DERIVED from the shadow's own parameters
    /// (`Theme.Elevation.pillShadowMargin`), not set here as a number. A local number here
    /// was the cause of the clipping: the shadow went up to radius 24, the margin stayed 22, and the blur
    /// hit the window edge as a sharp rectangle.
    static var shadowMargin: CGFloat { Theme.Elevation.pillShadowMargin }

    func hideVoiceRecordingOverlay() {
        copiedHideWork?.cancel()
        copiedHideWork = nil
        stopWatchingFocus()
        // Release the slot ONLY if we actually held it. An unconditional release with
        // `window == nil` would take the top of the screen away from ANOTHER controller (the batch and
        // streaming indicators share one slot), and the toast would go under a pill that
        // is actually showing.
        guard let window else { return }
        TopCenterOverlaySlot.release()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = hideDuration
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.close()
        })
        self.window = nil
    }
}

#if DEBUG
extension VoiceRecordingOverlayController {
    /// Pill window for the LIVE probe (`VoicePillProbe`). The probe must assert about
    /// the real window (level, `collectionBehavior`, surviving a Space change)
    /// and not about a freshly drawn view: exactly these properties decide the requirement
    /// "the pill is always on screen".
    var debugWindow: NSWindow? { window }
}
#endif

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
