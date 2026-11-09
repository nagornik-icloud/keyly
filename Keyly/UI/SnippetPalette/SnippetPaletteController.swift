import AppKit
import SwiftUI

/// Global snippet insertion palette: hotkey → search window → Enter inserts.
/// Without it the feature does not scale beyond a dozen snippets — they can't be found in the menu bar.
///
/// The main difficulty: the palette needs KEYBOARD input, so the window must become key, and
/// the target app loses focus. Therefore focus is captured BEFORE showing and restored before
/// inserting — the same technique as voice uses (`restoreFocusIfPossible`).
@MainActor
final class SnippetPaletteController {

    static let shared = SnippetPaletteController()

    private var panel: NSPanel?
    private var focusSnapshot: FocusSnapshot?

    private struct FocusSnapshot {
        let app: NSRunningApplication?
        let element: AXUIElement
    }

    private init() {}

    // MARK: - Showing

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        // Capture focus BEFORE showing: as soon as the palette becomes key, the "current focus" is ours.
        focusSnapshot = captureFocusSnapshot()

        let snippets = SnippetStore.load()
        var view = SnippetPaletteView(
            snippets: snippets,
            onPick: { [weak self] snippet in self?.insert(snippet) },
            onCancel: { [weak self] in self?.close() }
        )
        // Both exits lead to the WINDOW: the palette closes, the window opens on snippets.
        // Otherwise someone who pressed ⌘↩ or "Create" stays in the palette and can't tell
        // whether it worked.
        view.onEdit = { [weak self] snippet in
            self?.close()
            NotificationCenter.default.post(name: .openSnippetInEditor, object: snippet.id)
        }
        view.onCreateSnippet = { [weak self] in
            self?.close()
            NotificationCenter.default.post(name: .openSnippetInEditor, object: nil)
        }

        let hosting = NSHostingView(rootView: view)
        // 760pt, not 560: with the preview pane to the right of the list, the old width
        // cut the text down to two or three words per line — a preview in such a column
        // answers "this one or the next?" no better than no preview at all.
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: Self.height(for: snippets.count))

        let panel = existingPanel()
        panel.contentView = hosting
        panel.setContentSize(hosting.frame.size)
        centerNearTop(panel)
        // makeKey is required — without it you can't type in the search field.
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.info(.snippets, "Палитра открыта, сниппетов: \(snippets.count)")
    }

    /// Palette height follows the LIBRARY SIZE, not a fixed value.
    ///
    /// It used to be a hard 400pt regardless of content. With four snippets ~200pt sat empty
    /// under the list, and in the "nothing found" and "no snippets yet" states the palette
    /// popped over the work as a 760×400 black slab for a single phrase — people read that as
    /// "frozen", not as an answer.
    ///
    /// Computed ONCE on opening and not changed while typing: a window twitching on every
    /// character is worse than empty space — the target slides from under the cursor and the
    /// list below jumps. Spotlight and Raycast behave exactly this way.
    ///
    /// 48 — search field, 44 — row height (`KeylyRow.height`), 34 — footer with hints.
    /// The 400 ceiling stays as before, the 220 floor keeps the preview from collapsing into a slit.
    static func height(for snippetCount: Int) -> CGFloat {
        let rows = min(max(snippetCount, 1), 8)
        let ideal = 48 + CGFloat(rows) * 44 + 34
        return min(max(ideal, 220), 400)
    }

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: - Insertion

    private func insert(_ snippet: Snippet) {
        close()
        Task { @MainActor in
            // Restore focus BEFORE inserting: the palette took it, and without restoring it Cmd+V goes
            // nowhere (or into the Keyly app itself).
            await restoreFocus()
            SnippetService.shared.insert(snippet)
            focusSnapshot = nil
        }
    }

    private func restoreFocus() async {
        guard let snapshot = focusSnapshot else { return }
        snapshot.app?.activate()
        // App activation is asynchronous: without a pause the AX focus is set on a window that is
        // not active yet, and the insertion misses.
        try? await Task.sleep(nanoseconds: 140_000_000)
        AXUIElementSetAttributeValue(snapshot.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func captureFocusSnapshot() -> FocusSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let app = NSWorkspace.shared.frontmostApplication
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return FocusSnapshot(app: app, element: unsafeBitCast(focused, to: AXUIElement.self))
    }

    // MARK: - Window

    private func existingPanel() -> NSPanel {
        if let panel { return panel }
        let created = KeyablePanel(contentRect: .zero,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        created.isFloatingPanel = true
        created.level = .floating
        created.backgroundColor = .clear
        created.isOpaque = false
        created.hasShadow = true
        created.appearance = NSAppearance(named: .darkAqua)
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Close when the user moves to another window: a forgotten palette floating above
        // everything is the most annoying kind of overlay.
        created.hidesOnDeactivate = true
        panel = created
        return created
    }

    /// Top center, like system search: that is where eyes look for it, not the screen center,
    /// where the palette would cover what the user is about to paste into.
    private func centerNearTop(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.maxY - size.height - visible.height * 0.18))
    }
}

/// A `borderless` window cannot become key by default, and typing in the search would be impossible.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
