#if DEBUG
import AppKit
import SwiftUI

/// Snapshot of a concept mockup via the LIVE window compositor — the same way as the product
/// screens (`LiveWindowCapture`), and at the same 1040×860 size.
///
/// Why not `ImageRenderer`: it doesn't capture materials and live controls, and a design can't
/// be judged from a frame missing a quarter of the UI — this already cost the project a round.
/// The compositor returns exactly what the user will see.
///
/// Run: `KEYLY_CONCEPT=<key>` → `.qa-shots/concept-<key>.png`. Keys are added for a specific
/// design choice and removed along with it once the choice is made.
@MainActor
enum ConceptShotter {

    static func run(_ key: String) async {
        let size = AppDelegate.defaultWindowSize
        let root: AnyView
        switch key.lowercased() {
        // How to fill the hotkey bar: the issue is known, the fix is a visual choice judged by eye.
        case "fill-1": root = AnyView(HotkeyBarFill(page: 1))
        case "fill-2": root = AnyView(HotkeyBarFill(page: 2))
        // There used to be branches for concept mockups (k6/k8, voice-k8) and hotkey row variants
        // (keyrow/bg/fork). All of them are DONE: the concepts were rejected, and the hotkey row was
        // settled and is already in the product (`KeylyHotKeyField.lyingRow`).
        // A mockup that outlived its decision is not an archive but a second source of truth: it
        // shows a layout the product doesn't have and misleads anyone who looks at it.
        default:
            FileHandle.standardError.write("CONCEPT: ключ '\(key)' неизвестен — действующих макетов сейчас нет, все отыграли свои развилки\n".data(using: .utf8)!)
            exit(2)
        }

        let hosting = NSHostingController(rootView: root.frame(width: size.width, height: size.height))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        // WITHOUT `.fullSizeContentView`: with it the contentView stretches over the title bar strip,
        // and `bounds` returned 892pt for an 860pt product window. Same styleMask as the product
        // harness (`LiveWindowCapture`) — two capturers of the same product must not disagree on canvas.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: 7/255, green: 7/255, blue: 7/255, alpha: 1)
        // No traffic-light buttons — same as in the product itself.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(size)
        window.center()
        window.orderFrontRegardless()
        // Pin the size AFTER showing — as LiveWindowCapture has long done.
        //
        // Without this `.fullSizeContentView` gave a 892pt-tall contentView for an 860pt product
        // window: the style would be judged on a canvas 32pt taller than the real window, and the
        // last layout row would sit exactly in that extra strip. One harness had already been fixed
        // for this ("frames are captured at product size"), the other was left behind.
        let locked = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        window.minSize = locked.size
        window.maxSize = locked.size
        window.setContentSize(size)
        window.contentView?.frame = CGRect(origin: .zero, size: size)
        window.contentView?.layoutSubtreeIfNeeded()

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 400_000_000)

        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write("CONCEPT: не удалось снять окно\n".data(using: .utf8)!)
            exit(2)
        }
        // CANVAS GATE: the frame must be the size of the product window.
        //
        // A mismatch here is not "image inaccuracy" but a substitution of what is being decided on:
        // the layout is judged on a canvas that doesn't exist, hiding that the bottom row is past
        // the edge. This must not go unnoticed — fail loudly.
        let expected = AppDelegate.defaultWindowSize
        if abs(view.bounds.width - expected.width) > 0.5 || abs(view.bounds.height - expected.height) > 0.5 {
            FileHandle.standardError.write("""
            CONCEPT: холст \(Int(view.bounds.width))×\(Int(view.bounds.height))pt             вместо \(Int(expected.width))×\(Int(expected.height)) — кадр показал бы не то окно
            
            """.data(using: .utf8)!)
            exit(3)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("CONCEPT: не удалось закодировать PNG\n".data(using: .utf8)!)
            exit(2)
        }
        let dir = QASnapshotExporter.outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("concept-\(key.lowercased()).png")
        try? png.write(to: url)
        print("CONCEPT: wrote \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh)px)")
        NSApp.terminate(nil)
    }
}
#endif
