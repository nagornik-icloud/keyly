import AppKit
import SwiftUI

@MainActor
protocol RealtimeIndicatorPresenting: AnyObject {
    func showRealtimeIndicator(session: RealtimeVoiceSession,
                               elapsedProvider: @escaping () -> Int)
    /// Dictation ended, processing is running. The indicator STAYS and changes its look.
    func markRealtimeIndicatorProcessing()
    func hideRealtimeIndicator()
}

/// Indicator of an active realtime recording: a capsule at top center of the screen,
/// slightly below the menu bar. The window spans the full width of the visible area; the
/// capsule itself is centered by SwiftUI, so it stays exactly centered
/// at any width (timer, status change and wave change the width on the fly).
/// Transparent to the mouse (`ignoresMouseEvents`); stopping is hotkey-only.
@MainActor
final class RealtimeIndicatorController: RealtimeIndicatorPresenting {
    private var window: NSWindow?
    /// The indicator phase lives SEPARATELY from the session: "processing" continues after the
    /// session is closed and released. The indicator used to be hidden exactly at that moment, leaving
    /// the user with no sign of work for the whole post-processing time.
    private let state = VoiceOverlayState()
    private var spaceObserver: NSObjectProtocol?
    private let showDuration: TimeInterval = 0.28
    private let hideDuration: TimeInterval = 0.22
    /// Capsule offset from the top edge of the visible area (below the menu bar).
    private let topInset: CGFloat = 8

    func showRealtimeIndicator(session: RealtimeVoiceSession,
                               elapsedProvider: @escaping () -> Int) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let showTimer = UserDefaults.standard.object(forKey: SettingsKeys.voiceIndicatorShowTimer) as? Bool ?? true

        state.phase = .recording
        let content = RealtimeIndicatorRootView(
            session: session,
            elapsedProvider: elapsedProvider,
            showTimer: showTimer,
            topInset: topInset,
            state: state
        )
        let hosting = NSHostingView(rootView: content)

        // visibleFrame excludes the menu bar at the top and the Dock: the window sits right under the menu bar
        // at full screen width; the capsule inside is centered by SwiftUI.
        let frame = screen.visibleFrame

        // NSPanel + .nonactivatingPanel: needed to appear over fullscreen apps.
        let panel = IndicatorWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = showDuration
            panel.animator().alphaValue = 1
        }

        window?.close()
        window = panel
        // The capsule sits at the top center of this full-width window: the top is taken, and a toast
        // must go below it, not underneath it (see TopCenterOverlaySlot).
        TopCenterOverlaySlot.occupy(height: RealtimeIndicatorView.capsuleHeight + topInset)
        watchSpaceChange()

        Log.info(.ui, "VoiceIndicator: show top-center timer=\(showTimer) screen=\(NSStringFromRect(screen.frame))")
    }

    func markRealtimeIndicatorProcessing() {
        guard window != nil else { return }
        state.phase = .processing
        Log.info(.ui, "VoiceIndicator: фаза «обработка»")
    }

    /// The user switched to another Space. The window already shows on all Spaces, but its geometry
    /// was computed from the screen active at start: on another screen (different size,
    /// different notch) the capsule would drift off center. Recompute from the active screen.
    private func watchSpaceChange() {
        guard spaceObserver == nil else { return }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let window = self.window,
                      let screen = NSScreen.main ?? NSScreen.screens.first else { return }
                window.setFrame(screen.visibleFrame, display: true)
                window.orderFrontRegardless()
                Log.info(.ui, "VoiceIndicator: сменился рабочий стол — переставили окно")
            }
        }
    }

    func hideRealtimeIndicator() {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        TopCenterOverlaySlot.release()
        guard let window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = hideDuration
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.close()
        })
        Log.info(.ui, "VoiceIndicator: hide")
    }
}

/// Full-width container: the capsule is pinned to the top and centered
/// horizontally. `alignment: .top` on a ZStack = top + horizontal center.
private struct RealtimeIndicatorRootView: View {
    @ObservedObject var session: RealtimeVoiceSession
    let elapsedProvider: () -> Int
    let showTimer: Bool
    let topInset: CGFloat
    @ObservedObject var state: VoiceOverlayState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            RealtimeIndicatorView(
                session: session,
                elapsedProvider: elapsedProvider,
                showTimer: showTimer,
                state: state
            )
            .padding(.top, topInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private final class IndicatorWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
