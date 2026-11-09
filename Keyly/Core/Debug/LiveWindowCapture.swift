#if DEBUG
import SwiftUI
import AppKit

/// Snapshot of the app's LIVE window via the window compositor.
///
/// Replaces `ScreenSnapshotExporter`, which captured via `cacheDisplay(in:to:)` and therefore
/// **lied**: `NavigationSplitView` draws the sidebar with a vibrancy material that lives not in
/// the view's layer but in the compositor — the frame showed a ~300pt white rectangle instead
/// of the sidebar. Earlier visual verdicts were made on an artifact missing a quarter of the UI;
/// that is exactly why this exists.
///
/// Why no "Screen Recording" grant is needed: TCC restricts capturing windows of OTHER
/// processes. Here the process captures ITS OWN window by its `windowNumber` — allowed without
/// a permission prompt, so the harness works in CI and after every rebuild, without depending
/// on a grant that an ad-hoc-signed binary would lose on every build.
///
/// Run: env `KEYLY_LIVESHOT=<screen id>` → `.qa-shots/screen-*.png`. One screen per process.
@MainActor
enum LiveWindowCapture {

    /// EXACTLY the product's default window size. A frame narrower than the minimum proves
    /// nothing: three-pane screens don't fit, and the previous harness captured at 1000pt — a
    /// size the user never has. While frames were captured larger (1120×760), they showed a screen
    /// the user doesn't see: content was cut off earlier for the user than in the frame, and
    /// acceptance judged a longer screen.
    private static let size = AppDelegate.defaultWindowSize

    /// Strong reference to the snapshot controller (see `makeWindow`).
    private static var retainedHosting: NSViewController?

    static func run() async {
        let dir = QASnapshotExporter.outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = ProcessInfo.processInfo.environment["KEYLY_LIVESHOT"] ?? "overview"

        // Permission gate BEFORE capture. `OnboardingView` puts a full-screen "grant access" overlay
        // over the sidebar and detail when Accessibility/microphone aren't granted — and then all
        // eight screens would capture THE SAME placeholder frame. The sidebar validator doesn't catch
        // it: the overlay is drawn on top, the strip stops being uniform, the frame looks "honest".
        // Exactly the silent failure that must not happen, so the refusal here is loud.
        guard AccessibilityPermission.isTrusted, MicrophonePermission.isAuthorized else {
            fail("""
                 права не выданы (Accessibility: \(AccessibilityPermission.isTrusted), \
                 микрофон: \(MicrophonePermission.isAuthorized)).
                 Приложение показало бы оверлей «дайте доступ» вместо запрошенного экрана,
                 и все восемь кадров оказались бы одной и той же заглушкой. Выдай права
                 этому бинарю и повтори — снимать нечестный кадр нельзя.
                 """)
        }

        switch QAScreens.resolve(key) {
        case .unknownKey:
            fail("неизвестный экран '\(key)' — допустимые: \(QAScreens.keys.joined(separator: ", "))")
        case .noData(let why):
            fail("экран '\(key)' снять нечем: \(why). Это НЕ опечатка в ключе — нет данных.")
        case .ok(let id, let nav):
            await capture(id: id, nav: nav, into: dir)
        }
    }

    private static func capture(id: String, nav: NavItem, into dir: URL) async {
        let window = makeWindow(nav: nav)
        // SwiftUI must run onAppear (loading snippets/modules, setting selection) and settle the
        // layout; the compositor must draw the window on screen.
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // Restore the requested window size AFTER SwiftUI has laid out: while waiting it inflates
        // the view to the ideal content size (snippets screen — 1040pt in a 760pt window). The user
        // sees a 760pt window, so the frame must be that too.
        window.setFrame(window.frameRect(forContentRect: CGRect(origin: window.frame.origin,
                                                                size: size)),
                        display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 400_000_000)

        guard let shot = capture(window) else {
            fail("не удалось получить изображение окна '\(id)'")
        }
        // A rejected frame can be saved for analysis: "the strip is uniform" doesn't say WHAT
        // came out — an empty window, half a window, or another screen.
        if ProcessInfo.processInfo.environment["KEYLY_LIVESHOT_KEEP_REJECTED"] == "1" {
            write(shot.image, id: id + ".rejected", into: dir)
        }
        validate(shot, id: id)
        write(shot.image, id: id, into: dir)
        NSApp.terminate(nil)
    }

    // MARK: - Window

    private static func makeWindow(nav: NavItem) -> NSWindow {
        let vm = OnboardingViewModel()
        vm.initialSelection = nav
        // The size is set on the SwiftUI root ITSELF, not on the window. The window adapts to the
        // ideal content size, and stopping it from outside didn't work: neither
        // `sizingOptions = []`, nor `minSize`/`maxSize`, nor `setFrame` — SwiftUI resizes
        // programmatically, and window constraints don't bind programmatic changes.
        // The snippets screen came out 1040pt (what `TextEditor` asks for all possible text) in a
        // 760pt product window, and the frame showed a UI the user doesn't see. A pinned root
        // solves it at the source.
        let hosting = NSHostingController(
            rootView: OnboardingView(model: vm)
                .frame(width: size.width, height: size.height)
        )
        // The snapshot window keeps EXACTLY the given size. By default `NSHostingController`
        // propagates SwiftUI's ideal size to the window, and the screen with a text editor
        // stretched the window to 2946pt: the frame was four screens tall, and the sidebar gate hit
        // a uniform strip below it and rejected the capture — with a perfectly fine UI.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        // WITHOUT `.fullSizeContentView`, unlike the product window — deliberately: with it the
        // contentView grows to 892pt (860 of the product + the title bar strip), and the harness's
        // own gate rejects such a frame, because a layout can't be judged on a canvas taller than
        // the window.
        //
        // THE COST OF THIS CHOICE, worth knowing: the frame does NOT reproduce the top safe-area
        // inset. An element pinned to the top via `topTrailing` sits at its 12pt in the frame, but
        // ~28pt lower in the live window, under the title bar. That is exactly how a close button
        // not sitting in the corner went unnoticed: the frame was honest about size and silent
        // about chrome. Anything attached to the TOP of the window is checked on a real launch.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = ""
        window.isReleasedWhenClosed = false
        // Chrome like the real window (see applyWindowChrome in AppDelegate): without it the
        // system background #1b1b1b shows through the title bar strip, lighter than every product
        // surface, and the frame shows a strip the product doesn't have.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(srgbRed: 7/255, green: 7/255, blue: 7/255, alpha: 1)
        window.setContentSize(size)
        window.center()
        // The window must be on screen and drawn: the compositor captures what is actually
        // composited, not what exists in memory.
        window.orderFrontRegardless()
        // Pin the size AFTER showing and lock min/max. `sizingOptions = []` stops SwiftUI from
        // SETTING the size, but doesn't stop AppKit from fitting the window to content on first
        // show: the snippets screen came out 1040pt instead of 760pt. A frame of a window the user
        // will never see can't be judged — so the restriction is hard, not a "wish".
        let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        window.minSize = frame.size
        window.maxSize = frame.size
        window.setContentSize(size)
        window.contentView?.frame = CGRect(origin: .zero, size: size)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    // MARK: - Capture

    /// A frame together with the view's LOGICAL size. The size comes from `bounds`, not derived
    /// by dividing pixels by the expected width: such a derivation fools itself — a 1000pt@2x
    /// frame (exactly what the old harness captured) gives 2000/1120 = 1 and "passes" as 2000pt.
    private struct Shot {
        let image: CGImage
        let logicalWidth: CGFloat
        var scale: Int { max(1, image.width / Int(logicalWidth)) }
    }

    private static func capture(_ window: NSWindow) -> Shot? {
        guard let view = window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        let rect = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect),
              let cg = { view.cacheDisplay(in: rect, to: rep); return rep.cgImage }() else {
            return nil
        }
        return Shot(image: cg, logicalWidth: rect.width)
    }

    // MARK: - Frame honesty check

    /// A harness that silently returns a placeholder instead of an element that didn't fit is
    /// not allowed. So the frame is checked BEFORE writing, and on failure no PNG is written
    /// at all — otherwise "no frame" and "the frame lies" look the same downstream.
    private static func validate(_ shot: Shot, id: String) {
        // Height must match the requested one. If it drifted, the window adapted to content, and
        // the frame shows NOT the window the user sees.
        let expectedHeight = Int(size.height) * shot.scale
        if abs(shot.image.height - expectedHeight) > shot.scale {
            fail("""
                 кадр '\(id)': высота \(shot.image.height / shot.scale)pt вместо \(Int(size.height))pt — \
                 окно подстроилось под контент, а не под размер продукта.
                 """)
        }
        // Width is compared with the ACTUAL product window size, not a number in the gate code:
        // 1120 was left over from the old window, and after narrowing to 1040 the gate rejected all
        // honest frames at once. A constant duplicating a product value drifts from it on the first edit.
        guard shot.logicalWidth >= AppDelegate.defaultWindowSize.width else {
            fail("""
                 кадр '\(id)' шириной \(Int(shot.logicalWidth))pt — уже окна продукта \
                 \(Int(AppDelegate.defaultWindowSize.width))pt
                 """)
        }
        // Sidebar on the left — exactly what the old harness dropped.
        // A uniform strip = the sidebar wasn't captured; a verdict on such a frame is worthless.
        if uniformColumn(shot.image, fromPt: 8, toPt: 200, scale: shot.scale) {
            fail("""
                 кадр '\(id)': полоса сайдбара (8–200pt) ОДНОТОННА — сайдбар не попал в кадр.
                 Это тот самый дефект, из-за которого прошлый заход судил четверть интерфейса
                 вслепую. PNG не записан намеренно.
                 """)
        }
    }

    private static func uniformColumn(_ image: CGImage, fromPt: Int, toPt: Int, scale: Int) -> Bool {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var seen = Set<UInt32>()
        var y = image.height / 4
        while y < image.height * 3 / 4 {
            var x = fromPt * scale
            while x < min(toPt * scale, image.width) {
                let o = y * bpr + x * bpp
                let px = UInt32(ptr[o]) << 16 | UInt32(ptr[o + 1]) << 8 | UInt32(ptr[o + 2])
                seen.insert(px)
                if seen.count > 12 { return false } // enough distinct colors — the sidebar is there
                x += 4 * scale
            }
            y += 8
        }
        return true
    }

    // MARK: - Write and fail

    private static func write(_ image: CGImage, id: String, into dir: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("не удалось закодировать PNG для '\(id)'")
        }
        do {
            try png.write(to: dir.appendingPathComponent("\(id).png"))
            FileHandle.standardOutput.write("LIVESHOT: wrote \(id).png (\(image.width)×\(image.height)px)\n".data(using: .utf8)!)
        } catch {
            fail("не удалось записать '\(id)': \(error.localizedDescription)")
        }
    }

    /// Failure is ALWAYS loud with a non-zero exit code: a silent capture failure is
    /// indistinguishable from a successful run, and acceptance is built on the frames.
    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write("LIVESHOT: НЕ СМОГ СНЯТЬ — \(message)\n".data(using: .utf8)!)
        exit(2)
    }
}
#endif
