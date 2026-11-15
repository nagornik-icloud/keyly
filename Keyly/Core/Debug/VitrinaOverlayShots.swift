#if DEBUG
import SwiftUI
import AppKit

/// Transparent snapshots of the floating overlays for the public showcase (site, README).
///
/// Run: `KEYLY_QA_SNAPSHOT=1 KEYLY_VITRINA=1 KEYLY_DEMO=1 KEYLY_QA_LANG=<ru|en> KEYLY_QA_OUT=<dir>`.
///
/// Why separate from `QACatalog`: catalog frames are rendered OPAQUE on the app background or on a
/// flat color — fine for judging contrast, wrong for a showcase, where the plate has to sit over a
/// picture backdrop without a seam. Here the plate is rendered with an alpha channel (its own
/// shadow included), and the backdrop is composited outside. The views are the product's own —
/// `VoiceRecordingView` (the batch mode the demo set selects) and `BadgeView` with the product's
/// text — and the strings follow `KEYLY_QA_LANG`.
@MainActor
enum VitrinaOverlayShots {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KEYLY_VITRINA"] == "1"
    }

    static func run() {
        // Without the demo set the cheatsheet reads the developer's real modules and apps —
        // a public showcase must never be shot from them.
        guard DemoContent.isActive else {
            FileHandle.standardError.write(Data("VITRINA: needs KEYLY_DEMO=1\n".utf8))
            return
        }
        let dir = QASnapshotExporter.outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // The wave draws the live input level. Without a level it is a row of flat dots — which
        // reads as "nothing is being heard". A real meter report gives the product's own wave.
        InputLevelMeter.shared.report(level: 0.12)
        let recording = VoiceOverlayState()

        let shots: [(String, AnyView)] = [
            ("vitrina-pill-recording",
             AnyView(VoiceRecordingView(elapsedProvider: { 7 }, onCancel: {}, state: recording))),
            ("vitrina-badge-fixing",
             AnyView(BadgeView(text: BadgeText.fixing, kind: .progress, snapshot: true))),
        ]
        // The cheatsheet as the phone close-up: rows come from the product's own builder over the
        // seeded demo stores, not from the catalog fixture (that one lists a real user's apps).
        // No shadow padding — on a phone every point of width costs text size.
        let cheatsheet = AnyView(CheatsheetView(rows: CheatsheetRows.build(), snapshot: true))
        for (id, view, pad) in shots.map({ ($0.0, $0.1, CGFloat(40)) })
            + [("vitrina-cheatsheet", cheatsheet, CGFloat(1))] {
            let content = view
                .fixedSize()
                // Room for the plate's own shadow, so it isn't clipped by the canvas edge.
                .padding(pad)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            renderer.isOpaque = false
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write("VITRINA: FAILED \(id)\n".data(using: .utf8)!)
                continue
            }
            let url = dir.appendingPathComponent("\(id).png")
            try? png.write(to: url)
            print("VITRINA: wrote \(url.lastPathComponent) (\(cg.width)×\(cg.height)px)")
        }
        NSApp.terminate(nil)
    }
}
#endif
