#if DEBUG
import SwiftUI
import AppKit

/// Deterministic visual dump for visual checks.
///
/// With env `KEYLY_QA_SNAPSHOT=1` (hook in `AppDelegate`) renders EVERY `QACatalog` entry via
/// `ImageRenderer` into a separate PNG (`<id>.png`) in `.qa-shots/` and quits the app.
/// This is the "full visual" for the team — no flaky screenshots and no manual walk through
/// screens. The `MANIFEST.txt` next to them is for matching against `docs/qa/visual-inventory.md`.
@MainActor
enum QASnapshotExporter {

    static func run() {
        let outDir = outputDirectory()
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            err("не удалось создать \(outDir.path): \(error.localizedDescription)")
            NSApp.terminate(nil)
            return
        }

        let entries = QACatalog.entries
        var written: [String] = []
        for entry in entries {
            if let url = render(entry, into: outDir) {
                written.append(entry.id)
                log("wrote \(url.lastPathComponent)")
            } else {
                err("FAILED \(entry.id)")
            }
        }

        let manifest = written.joined(separator: "\n") + "\n"
        try? manifest.write(to: outDir.appendingPathComponent("MANIFEST.txt"),
                            atomically: true, encoding: .utf8)
        log("done: \(written.count)/\(entries.count) → \(outDir.path)")
        NSApp.terminate(nil)
    }

    /// Where to write: `KEYLY_QA_OUT` (set by `scripts/qa-capture.sh`), otherwise `.qa-shots`
    /// in the current working directory.
    static func outputDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["KEYLY_QA_OUT"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".qa-shots", isDirectory: true)
    }

    private static func render(_ entry: QACatalogEntry, into dir: URL) -> URL? {
        let content = entry.content
            .frame(width: entry.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(entry.padding)
            .frame(width: entry.width + entry.padding * 2, alignment: .topLeading)
            .background(Theme.Colors.bg)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        renderer.isOpaque = true

        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let url = dir.appendingPathComponent("\(entry.id).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func log(_ s: String) {
        FileHandle.standardOutput.write("QA-SNAPSHOT: \(s)\n".data(using: .utf8)!)
    }
    private static func err(_ s: String) {
        FileHandle.standardError.write("QA-SNAPSHOT: \(s)\n".data(using: .utf8)!)
    }
}
#endif
