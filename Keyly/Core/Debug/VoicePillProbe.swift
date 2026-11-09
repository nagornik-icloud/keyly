#if DEBUG
import AppKit
import SwiftUI

/// LIVE probe of the dictation pill.
///
/// Why separate from `QACatalog`: that one renders the VIEW via `ImageRenderer` and therefore
/// proves exactly one thing — how a phase looks. The requirement ("the pill is always on
/// screen whatever Space I switch to; after stopping it must change") is about the WINDOW and
/// the TRANSITION, not the picture: `collectionBehavior`, window level, surviving a Space
/// change, and the phase change itself. A static render checks none of that.
///
/// The probe drives the REAL `VoiceRecordingOverlayController` — the same class the product
/// runs — and asserts postconditions. Any failed assertion fails the run with a non-zero
/// code: a silently "green" probe is worse than none.
///
/// Run: `KEYLY_PILL_PROBE=1` → prints a report and writes `pill-live-*.png` frames.
@MainActor
enum VoicePillProbe {

    private static var failures: [String] = []

    static func run() async {
        let controller = VoiceRecordingOverlayController()
        let out = QASnapshotExporter.outputDirectory()
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // --- Phase 1: recording ---------------------------------------------------
        controller.showVoiceRecordingOverlay(elapsedProvider: { 7 },
                                             onCancel: {},
                                             placement: .topCenter)
        try? await Task.sleep(nanoseconds: 900_000_000)

        guard let window = controller.debugWindow else {
            report("окно плашки не создано вовсе")
            finish()
        }
        check(window.isVisible, "плашка на экране во время записи")

        // The shadow must not hit the window edge. That's exactly what happened when the shadow
        // radius went from 16 to 24 while the window margin stayed 22: the blur was clipped by the
        // edge and drew a SHARP RECTANGLE around the capsule. The numbers lived in different files,
        // unconnected — now the margin is derived from the shadow, and the probe guards it.
        let reach = Theme.Elevation.pillShadowRadius + abs(Theme.Elevation.pillShadowY)
        check(VoiceRecordingOverlayController.shadowMargin >= reach,
              "запас окна под тень (\(Int(VoiceRecordingOverlayController.shadowMargin))pt) "
              + "перекрывает её размах (\(Int(reach))pt) — тень не обрежется прямоугольником")

        // Main requirement: visible on EVERY Space and above full-screen windows.
        let behavior = window.collectionBehavior
        check(behavior.contains(.canJoinAllSpaces),
              "плашка живёт на всех рабочих столах (canJoinAllSpaces)")
        check(behavior.contains(.fullScreenAuxiliary),
              "плашка пробивается поверх полноэкранных приложений (fullScreenAuxiliary)")
        check(behavior.contains(.stationary),
              "плашка не уезжает вместе с анимацией смены стола (stationary)")
        check(window.level.rawValue >= NSWindow.Level.statusBar.rawValue,
              "плашка выше строки меню — её не накрывают чужие окна")

        // The shadow must FADE OUT before the window edge. Checked by pixels, not by formula: the
        // formula already lied once — it used `radius + |offsetY| + 4`, while the Gaussian tail
        // reaches about three times the nominal radius, leaving alpha 21/255 at the very edge. The
        // user sees it as a sharp rectangle border around the capsule.
        checkShadowFade(window)

        let recordingFrame = window.frame
        // Offset from the top screen edge. Checked AFTER the phase change: the pill must stay put
        // vertically. An earlier version computed the top with three different formulas (initial,
        // "pin to top", "processing"), and two of them forgot the shadow margin included in the
        // window size — the pill jumped down ~30pt exactly when the user was looking at it.
        // A single-phase frame can't catch this.
        let topGap = { (screen: NSScreen) in screen.visibleFrame.maxY - window.frame.maxY }
        let recordingTopGap = (window.screen ?? NSScreen.main).map(topGap)
        capture(window, as: "pill-live-1-recording", into: out)

        // --- Space change ---------------------------------------------------------
        // A real swipe between Spaces isn't available to the process, but the handler hangs on
        // exactly this notification — fire it and check the postcondition: the window stayed and
        // moved to the top center of the active screen.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        try? await Task.sleep(nanoseconds: 600_000_000)
        check(window.isVisible, "после смены рабочего стола плашка НЕ пропала")
        if let screen = window.screen ?? NSScreen.main {
            let expectedX = screen.visibleFrame.midX - window.frame.width / 2
            check(abs(window.frame.origin.x - expectedX) < 2,
                  "после смены стола плашка встала по центру активного экрана")
        }

        // --- Phase 2: processing --------------------------------------------------
        controller.markVoiceOverlayProcessing()
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        check(window.isVisible,
              "плашка ОСТАЛАСЬ на экране, пока идёт распознавание (главный дефект прошлой версии)")
        // The look must DIFFER, not just "change the label": the "Processing…" label is wider than
        // the timer, so a width difference is machine proof that the phase was really applied to
        // the live view, not just to the model field.
        check(abs(window.frame.width - recordingFrame.width) > 8,
              "плашка ВИЗУАЛЬНО изменилась при переходе запись → обработка "
              + "(ширина \(Int(recordingFrame.width)) → \(Int(window.frame.width)))")
        if let before = recordingTopGap, let after = (window.screen ?? NSScreen.main).map(topGap) {
            check(abs(after - before) < 2,
                  "при смене фазы плашка НЕ прыгнула по вертикали "
                  + "(отступ сверху \(Int(before))pt → \(Int(after))pt)")
        }
        capture(window, as: "pill-live-2-processing", into: out)

        // --- End ------------------------------------------------------------------
        controller.hideVoiceRecordingOverlay()
        try? await Task.sleep(nanoseconds: 700_000_000)
        check(controller.debugWindow == nil, "по завершении диктовки плашка снята")

        await checkToast(out: out)
        finish()
    }

    /// Toast: CENTER and shadow margin.
    ///
    /// Checked by machine because the eye already missed it: the window was a fixed 420pt while
    /// the capsule inside hugs the text — the WINDOW was centered, not what the user sees, and
    /// the toast sat left of center.
    private static func checkToast(out: URL) async {
        let toasts = VoiceErrorToastController()
        toasts.showVoiceErrorToast(message: "Не слышно речи — говорите громче")
        try? await Task.sleep(nanoseconds: 900_000_000)

        guard let window = toasts.debugWindow,
              let screen = window.screen ?? NSScreen.main else {
            report("окно тоста не создано")
            return
        }
        let visible = screen.visibleFrame
        let delta = abs(window.frame.midX - visible.midX)
        check(delta < 2,
              "тост стоит РОВНО по центру экрана (расхождение \(Int(delta))pt)")
        check(window.frame.width < visible.width * 0.6,
              "ширина тоста идёт по содержимому, а не растянута на пол-экрана "
              + "(\(Int(window.frame.width))pt)")
        let reach = Theme.Elevation.pillShadowRadius + abs(Theme.Elevation.pillShadowY)
        check(Theme.Elevation.pillShadowMargin >= reach,
              "запас окна тоста под тень перекрывает её размах — не обрежется прямоугольником")
        capture(window, as: "toast-live-centered", into: out)
    }

    // MARK: - Assertions and report

    private static func check(_ condition: Bool, _ what: String) {
        if condition {
            print("  ✓ \(what)")
        } else {
            print("  ✗ \(what)")
            failures.append(what)
        }
    }

    private static func report(_ message: String) {
        print("  ✗ \(message)")
        failures.append(message)
    }

    private static func finish() -> Never {
        if failures.isEmpty {
            print("PILL PROBE: всё сошлось")
            exit(0)
        }
        FileHandle.standardError.write(
            "PILL PROBE: НЕ СОШЛОСЬ (\(failures.count)):\n\(failures.map { "  — " + $0 }.joined(separator: "\n"))\n"
                .data(using: .utf8)!)
        exit(3)
    }

    /// The shadow fades out BEFORE the window edge — otherwise a right angle shows in its place.
    ///
    /// Take the maximum alpha over the four outermost pixel rows. Non-zero alpha at the edge is
    /// the cutoff: nothing can be drawn beyond the window, and the gradient is chopped by a
    /// straight line.
    private static func checkShadowFade(_ window: NSWindow) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 2, h > 2 else { return }

        func alpha(_ x: Int, _ y: Int) -> Int {
            Int((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255)
        }
        var peak = 0
        for x in stride(from: 0, to: w, by: 2) {
            peak = max(peak, alpha(x, 0), alpha(x, h - 1))
        }
        for y in stride(from: 0, to: h, by: 2) {
            peak = max(peak, alpha(0, y), alpha(w - 1, y))
        }
        check(peak <= 2,
              "тень затухает ДО кромки окна (максимум альфы на краю \(peak)/255) — "
              + "прямоугольной границы вокруг капсулы не видно")
    }

    /// Snapshot of OUR OWN window. The frame lets the phase be looked at by eye too: a width
    /// assertion says "changed", not "changed correctly".
    private static func capture(_ window: NSWindow, as id: String, into dir: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(id).png"))
        print("  · кадр \(id).png")
    }
}
#endif
