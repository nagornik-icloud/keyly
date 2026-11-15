#if DEBUG
import SwiftUI
import AppKit

/// Showcase frames of the product AT WORK: a real AppKit text field before and after.
///
/// Run: `KEYLY_QA_SNAPSHOT=1 KEYLY_VITRINA_FIELD=1 KEYLY_DEMO=1 KEYLY_QA_LANG=<ru|en> KEYLY_QA_OUT=<dir>`.
///
/// Why this exists: the site's header showed the settings screen — a list of toggles — and a
/// visitor could not see what the program DOES. What it does is turn "Ghbdtn" into "Привет" in a
/// text field. A drawn picture of that would be a mockup; here the field is a real `NSTextView`
/// in a real window, and the "after" text is NOT typed by hand: it is produced by the product's
/// own conversion path — `LayoutMapper.detectLayout` + `LayoutMapper.convert(_:from:)`, exactly
/// what `TextSelector` does with a selection on ⌥⌘L.
///
/// The overlays (the "Fixing…" badge, the recording pill) are the product's own views rendered
/// with alpha, so the composer can put them where the product puts them (top center of the
/// screen) over a backdrop without a seam.
///
/// Window chrome: the window's theme frame (title bar with the traffic lights) is captured
/// together with the content via `cacheDisplay` — the process draws ITS OWN window, so no
/// Screen Recording grant is involved and nothing of the user's screen can get into the frame.
@MainActor
enum VitrinaFieldShots {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KEYLY_VITRINA_FIELD"] == "1"
    }

    /// Pixel density of every frame. 3, not the screen's 2: the site shows scenes 820 css px wide,
    /// and a 2× capture of a readable region would come out narrower than 2× the display width.
    private static let scale: CGFloat = 3

    private static var ru: Bool { DemoContent.isRussian }

    /// What a Russian speaker types with the English layout still on. Letters, digits, space
    /// and "!" only: their keys are the same in the Mac "Russian" layout the converter maps and
    /// in "Russian – PC", so the frame does not depend on which of the two a visitor uses.
    static let layoutSample = "Ghbdtn! Pfdnhf d 10 ghbtle"

    private static var typoSample: String {
        ru ? "Скину отчет завтра утром, посмотри пожалуйсто и напеши что думаеш. Если будут вапросы — звони, я весь день на связе."
           : "Ill send the report tomorow morning, pleese take a look and tell me what you thinck. If you have any questons, call me — Im around all day."
    }

    private static var voiceSample: String {
        ru ? "Встречу переносим на четверг, в три часа. Захвати, пожалуйста, договор и счёт за октябрь — обсудим сроки"
           : "Let's move the meeting to Thursday at three. Please bring the contract and the October invoice, and we'll go over the dates"
    }

    private static var windowTitle: String { ru ? "Черновик" : "Draft" }

    /// Retained so the windows stay alive until captured.
    private static var windows: [NSWindow] = []

    static func run() async {
        guard DemoContent.isActive else {
            FileHandle.standardError.write(Data("VITRINA-FIELD: needs KEYLY_DEMO=1\n".utf8))
            NSApp.terminate(nil)
            return
        }
        let dir = QASnapshotExporter.outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if ProcessInfo.processInfo.environment["KEYLY_VITRINA_CUSTOM"] == "1" {
            await runCustomModule(into: dir)
            return
        }

        // The product's own conversion path for a selection (see TextSelector.handleExistingSelection).
        let detected = LayoutMapper.detectLayout(of: layoutSample)
        let converted = detected.map { LayoutMapper.convert(layoutSample, from: $0) }
            ?? LayoutMapper.convert(layoutSample)

        var texts: [String: String] = [
            "layout_before": layoutSample,
            "layout_after": converted,
            "layout_detected": detected == .en ? "en" : (detected == .ru ? "ru" : "nil"),
            "typo_before": typoSample,
            "voice_text": voiceSample,
        ]

        // Typo "after": the product's REAL answer, not text typed here. Only with a real key handed
        // in explicitly (`KEYLY_VITRINA_GEMINI_KEY`), through the product's own path — the same
        // `ErrorFixer.previewFix` the module's try-out field uses (prompt, fences, guard). One
        // network call per run; without the key the pair frame is simply not made.
        var typoAfter: String?
        if DemoContent.hasVitrinaGeminiKey {
            APIKeyStore.shared.select(context: .errorFix, selection: DemoContent.geminiErrorFixSelection)
            guard let answer = await ErrorFixer.shared.previewFix(typoSample) else {
                fail("модель не вернула исправленный текст (подробности в логе)")
            }
            typoAfter = answer
            texts["typo_after"] = answer
            texts["typo_model"] = APIKeyStore.shared.model(for: .errorFix)
            texts["typo_level"] = ErrorFixLevel.current.rawValue
            print("VITRINA-FIELD: typo «\(typoSample)» → «\(answer)» (\(texts["typo_model"] ?? "?"), 1 call)")
        }

        // Sizes in points; frames are captured at `scale`. The header pair is larger (24 pt) because
        // the site shows it narrower than the scenes and the phone close-up is cut from the same pixels.
        var jobs: [(id: String, text: String, width: CGFloat, font: CGFloat, select: Bool)] = [
            // The phrase is SELECTED: without a selection ⌥⌘L converts only the last word
            // (TextSelector.handleLastWordRewrite), and the frame would promise more than one press does.
            ("field-layout-before", layoutSample, 390, 24, true),
            ("field-layout-after", converted, 390, 24, false),
            ("field-typo-before", typoSample, 440, 20, true),
            ("field-voice", voiceSample, 440, 20, false),
        ]
        if let typoAfter {
            // The before/after pair for typos: same width and font, so the two windows line up.
            jobs.append(("field-typo-pair-before", typoSample, 440, 20, true))
            jobs.append(("field-typo-pair-after", typoAfter, 440, 20, false))
        }
        for job in jobs {
            let window = makeEditor(text: job.text, width: job.width, font: job.font, selectAll: job.select)
            windows.append(window)
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let cg = captureWithChrome(window) else {
                fail("не удалось снять окно \(job.id)")
            }
            write(cg, id: job.id, into: dir)
            texts[job.id + ".size_pt"] = "\(Int(window.frame.width))x\(Int(window.frame.height))"
            window.orderOut(nil)
        }

        // Overlays: the product's views, alpha kept for the composer.
        // Margin = the product's own shadow margin: a fixed 40 pt cut the pill's shadow tail (radius 24 reaches ~2.5×).
        InputLevelMeter.shared.report(level: 0.12)
        let recording = VoiceOverlayState()
        let overlays: [(String, AnyView)] = [
            ("overlay-pill-recording",
             AnyView(VoiceRecordingView(elapsedProvider: { 7 }, onCancel: {}, compact: true, state: recording))),
            ("overlay-badge-fixing",
             AnyView(BadgeView(text: BadgeText.fixing, kind: .progress, snapshot: true))),
        ]
        for (id, view) in overlays {
            let renderer = ImageRenderer(content: view.fixedSize().padding(Theme.Elevation.pillShadowMargin).environment(\.colorScheme, .dark))
            renderer.scale = scale
            renderer.isOpaque = false
            guard let cg = renderer.cgImage else { fail("не удалось отрисовать \(id)") }
            write(cg, id: id, into: dir)
        }
        texts["badge_text"] = BadgeText.fixing

        if let json = try? JSONSerialization.data(withJSONObject: texts, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: dir.appendingPathComponent("vitrina-field-texts.json"))
        }
        print("VITRINA-FIELD: layout «\(layoutSample)» → «\(converted)» (detected \(texts["layout_detected"] ?? "?"))")
        NSApp.terminate(nil)
    }

    // MARK: - Custom module

    /// What a visitor would select before pressing the module's hotkey. Russian in both page
    /// languages: the demo module is "Translate to English", so the input is the other language.
    static let customSample = "Созвон переносим на пятницу, в 11. Договор пришлю вечером."

    /// "Own command" scene: the module's RESULT, not its settings form. Only this pair is made
    /// (`KEYLY_VITRINA_CUSTOM=1`), so a run costs exactly one model call: the product's own
    /// `CustomModuleRunner.preview` (the try-out path — module prompt, system prompt, client) on the
    /// first demo module, through the demo "Work" (Gemini) entry with the key handed in explicitly.
    private static func runCustomModule(into dir: URL) async {
        guard DemoContent.hasVitrinaGeminiKey else { fail("нужен KEYLY_VITRINA_GEMINI_KEY") }
        guard let module = CustomModuleStore.load().first else { fail("нет демо-модуля") }
        APIKeyStore.shared.select(context: .customModule(module.id),
                                  selection: DemoContent.geminiErrorFixSelection)
        guard let answer = await CustomModuleRunner.shared.preview(module: module, sample: customSample) else {
            fail("модель не вернула результат модуля (подробности в логе)")
        }
        var texts: [String: String] = [
            "custom_module": module.name,
            "custom_prompt": module.prompt,
            "custom_model": APIKeyStore.shared.model(for: .customModule(module.id)),
            "custom_before": customSample,
            "custom_after": answer,
        ]
        print("VITRINA-FIELD: custom «\(module.name)» «\(customSample)» → «\(answer)» (\(texts["custom_model"] ?? "?"), 1 call)")
        // 28 pt: the scene is shown 346 css px wide on a phone, and the pair has to stay readable there.
        for job in [("field-custom-before", customSample, true), ("field-custom-after", answer, false)] {
            let window = makeEditor(text: job.1, width: 560, font: 28, selectAll: job.2)
            windows.append(window)
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let cg = captureWithChrome(window) else { fail("не удалось снять окно \(job.0)") }
            write(cg, id: job.0, into: dir)
            texts[job.0 + ".size_pt"] = "\(Int(window.frame.width))x\(Int(window.frame.height))"
            window.orderOut(nil)
        }
        if let json = try? JSONSerialization.data(withJSONObject: texts, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: dir.appendingPathComponent("vitrina-custom-texts.json"))
        }
        NSApp.terminate(nil)
    }

    // MARK: - Editor window

    private static func makeEditor(text: String, width: CGFloat, font: CGFloat, selectAll: Bool) -> NSWindow {
        let inset = NSSize(width: 16, height: 14)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.font = .systemFont(ofSize: font)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        textView.drawsBackground = true
        textView.textContainerInset = inset
        textView.isRichText = false
        // Selection and caret in macOS's DEFAULT blue, not the accent of the machine the frames
        // are shot on: a visitor with default settings sees blue.
        textView.selectedTextAttributes = [.backgroundColor: NSColor.systemBlue.withAlphaComponent(0.5),
                                           .foregroundColor: NSColor.white]
        textView.insertionPointColor = .systemBlue
        textView.string = text
        textView.textContainer?.widthTracksTextView = true
        // The container is the view width MINUS the insets: measured at the full width, the text
        // wrapped into fewer lines than it does on screen, and the window clipped the last line.
        textView.textContainer?.containerSize = NSSize(width: width - inset.width * 2,
                                                       height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        // Height of the laid-out text: the window hugs it, no empty editor below the line.
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? font * 1.3
        let height = ceil(used + inset.height * 2)

        let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = windowTitle
        window.isReleasedWhenClosed = false
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = textView
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        if selectAll {
            textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        } else {
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        return window
    }

    /// The whole window including its title bar: the theme frame is the content view's superview.
    private static func captureWithChrome(_ window: NSWindow) -> CGImage? {
        guard let frameView = window.contentView?.superview else { return nil }
        frameView.layoutSubtreeIfNeeded()
        let rect = frameView.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(rect.width * scale),
                                         pixelsHigh: Int(rect.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = rect.size
        frameView.cacheDisplay(in: rect, to: rep)
        return rep.cgImage
    }

    // MARK: - Write and fail

    private static func write(_ image: CGImage, id: String, into dir: URL) {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fail("не удалось закодировать \(id)")
        }
        do {
            try png.write(to: dir.appendingPathComponent("\(id).png"))
            print("VITRINA-FIELD: wrote \(id).png (\(image.width)×\(image.height)px)")
        } catch {
            fail("не удалось записать \(id): \(error.localizedDescription)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("VITRINA-FIELD: НЕ СМОГ — \(message)\n".utf8))
        exit(2)
    }
}
#endif
