import AppKit
import SwiftUI

/// Narrow "show an error toast" protocol for modules that only need errors
/// (text features: error fix, custom modules), without info toasts
/// and the sound details of the voice path.
@MainActor
protocol ErrorToastPresenting: AnyObject {
    func showErrorToast(message: String)
}

@MainActor
final class VoiceErrorToastController: VoiceErrorToastPresenting, ErrorToastPresenting {

    /// Click on an error toast. Set by AppDelegate: opens Settings (where key/model live).
    var onOpenSettings: (() -> Void)?

    func showErrorToast(message: String) {
        showVoiceErrorToast(message: message)
    }
    private var window: NSWindow?
    private var hideTask: DispatchWorkItem?

    #if DEBUG
    /// Toast window for the live probe (`VoicePillProbe`): its position is checked by machine.
    var debugWindow: NSWindow? { window }
    #endif

    func showVoiceInfoToast(message: String) {
        showToast(content: AnyView(VoiceInfoToastView(message: message)), interactive: false)
    }

    func showVoiceErrorToast(message: String) {
        let view = VoiceErrorToastView(message: message) { [weak self] in
            self?.dismiss()
            self?.onOpenSettings?()
        }
        showToast(content: AnyView(view), interactive: true)
    }

    func showVoiceErrorToast(message: String, actionTitle: String, action: @escaping () -> Void) {
        let view = VoiceErrorToastView(message: message, actionTitle: actionTitle) { [weak self] in
            self?.dismiss()
            action()
        }
        showToast(content: AnyView(view), interactive: true)
    }

    /// Remove the toast immediately (on click) without waiting for the auto timer.
    private func dismiss() {
        hideTask?.cancel()
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { window.orderOut(nil) })
    }

    private func showToast(content: AnyView, interactive: Bool) {
        hideTask?.cancel()

        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        // The window is sized TO CONTENT, not a fixed 420pt.
        //
        // A fixed width was the cause of "toast left of center": the capsule inside the window
        // hugs the text, but the window stayed 420pt, so the window was centered, not what
        // the user sees. Plus the shadow margin, same as the dictation pill: without it
        // the blur gets clipped by the window edge at a right angle.
        let margin = Theme.Elevation.pillShadowMargin
        let hosting = NSHostingView(rootView: content.padding(margin))
        // The hosting layer is opaque by default: a dark rectangular backing with sharp corners
        // showed through under the rounded pill.
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fitted)

        let toastWindow: NSWindow
        if let existing = window {
            toastWindow = existing
            toastWindow.contentView = hosting
            toastWindow.setContentSize(fitted)
        } else {
            let created = NSWindow(
                contentRect: NSRect(origin: .zero, size: fitted),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.level = .statusBar
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            created.contentView = hosting
            created.alphaValue = 0
            toastWindow = created
            window = created
        }

        // Interactive (error): catches the click and opens Settings. An info toast does not.
        toastWindow.ignoresMouseEvents = !interactive

        // Top center, the same place as the recording pill and the badge. The toast used to
        // slide under the menu bar icon: three surfaces of one
        // product appeared in three different places on screen.
        //
        // If the top is taken by the dictation pill, go BELOW it. The pill lives at a higher level
        // (`.screenSaver`), and a toast placed in the same spot would stick out from under it at the edges:
        // it is wider than the pill. A recognition error arrives exactly when
        // the pill is still on screen, so this is the typical case, not a rare one.
        // Edge offsets are measured from the VISIBLE capsule, so the shadow margin, which is part of
        // the window size, is subtracted; otherwise the pill would sit lower than intended
        // by exactly the invisible margin (same math as for the dictation pill).
        let size = toastWindow.frame.size
        let x = targetScreen.visibleFrame.midX - size.width / 2
        let y = targetScreen.visibleFrame.maxY - size.height - Theme.Space.xl + margin
            - TopCenterOverlaySlot.dropDown
        toastWindow.setFrameOrigin(NSPoint(x: max(targetScreen.visibleFrame.minX + 12, x), y: y))
        toastWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            toastWindow.animator().alphaValue = 1
        }

        let hide = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
        hideTask = hide
        // Eight seconds: the toast carries the failure reason and, for errors, an action;
        // in three seconds people could not finish reading it, let alone click.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: hide)
    }
}

private struct VoiceInfoToastView: View {
    let message: String
    var body: some View {
        ToastShell(tint: Theme.Colors.accent, message: message)
    }
}

private struct VoiceErrorToastView: View {
    let message: String
    /// Action caption, now for VoiceOver only: it is not shown on screen
    /// (the whole toast is clickable instead).
    var actionTitle: String?
    var onTap: () -> Void

    var body: some View {
        // The WHOLE toast is clickable, and it is a real button, not `.onTapGesture`: a gesture is not
        // exposed to Accessibility as an action (the same bug class fixed on the
        // sidebar row). There is NO separate "Open Settings" chip on the pill: the design is
        // a clean capsule; the VoiceOver hint says where the click leads.
        Button(action: onTap) {
            ToastShell(tint: Theme.Colors.danger, message: message)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message)
        .accessibilityHint(actionTitle ?? "toast.openSettings".loc)
    }
}

/// The toast is a CAPSULE in the dictation pill's visual language.
///
/// The previous look had an icon in a colored tile, an all-caps "FAILED" title, text and an action
/// caption: four levels of styling for one phrase, and the phrase itself ended up
/// as the quietest element. Here the text is the only content, a colored dot carries the state,
/// and the action is not shown at all: the whole pill is clickable.
///
/// Shape, fill and shadow come from the same tokens as the dictation capsule, so the two
/// surfaces that appear in the same spot read as one family.
struct ToastShell: View {
    let tint: Color
    let message: String

    /// Width cap: a long reason wraps to a second line instead of stretching
    /// the capsule across the whole screen.
    static let maxTextWidth: CGFloat = 380

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Self.maxTextWidth, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(
            Capsule()
                .fill(Theme.Elevation.fill)
                .shadow(color: .black.opacity(Theme.Elevation.pillShadowOpacity),
                        radius: Theme.Elevation.pillShadowRadius,
                        y: Theme.Elevation.pillShadowY)
                .shadow(color: .black.opacity(Theme.Elevation.pillContactOpacity),
                        radius: Theme.Elevation.pillContactRadius,
                        y: Theme.Elevation.pillContactY)
        )
        .fixedSize()
    }
}
