import AppKit
import SwiftUI

/// Cheatsheet floating above all windows.
///
/// A non-activating floating window, not a regular one: it must not take focus from what the user
/// is working in — they open it to RECALL a shortcut and press it right away.
@MainActor
final class CheatsheetController {
    static let shared = CheatsheetController()

    private var panel: NSPanel?

    func toggle() {
        if panel != nil {
            close()
        } else {
            show()
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func show() {
        let view = CheatsheetView(rows: CheatsheetRows.build())
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 480)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // Show on the screen that currently has focus: on a second monitor a window that opened
        // on the main one is useless — the user simply won't see it.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - 210, y: frame.midY - 240))
        }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
