import SwiftUI
import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Declared first on purpose: stored properties initialize in order, so the settings
    /// migration finishes before any other property can read UserDefaults.
    private let legacySettingsMigrated: Void = {
        LegacyDomainMigrator.runIfNeeded()
        #if DEBUG
        MainActor.assumeIsolated { DemoContent.seedIfActive() }
        #endif
    }()
    var menuBarController: MenuBarController?
    var onboardingWindow: NSWindow?
    private let onboardingViewModel = OnboardingViewModel()
    private let voiceRecordingOverlayController = VoiceRecordingOverlayController()
    private let realtimeIndicatorController = RealtimeIndicatorController()
    private let voiceErrorToastController = VoiceErrorToastController()
    private let badgeController = BadgeController()
    private let storeFailureAlert = StoreFailureAlert()
    private var accessMonitorTimer: Timer?
    private var lastAccessTrusted: Bool = false
    private var hotKeysRunning: Bool = false
    /// Esc/⌘W monitor for the window without traffic-light buttons (see `installEscapeHatch`).
    private var escapeHatch: Any?
    private var closeRequestObserver: Any?

    private var showDockIcon: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.showDockIcon) as? Bool ?? true
    }
    
    private var showMenuBarIcon: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.showMenuBarIcon) as? Bool ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // QA dump: deterministically render every state into .qa-shots/ and exit.
        // Gives a full visual pass without a manual walkthrough. See scripts/qa-capture.sh.
        // Recording self-test: the voice core was rewritten on top of the engine, and there is
        // no other way to check it — screenshots show only the UI, and package tests don't touch audio.
        if RecordingSelfTest.runIfRequested() { return }
        if ProcessInfo.processInfo.environment["KEYLY_QA_SNAPSHOT"] == "1" {
            Task { @MainActor in QASnapshotExporter.run() }
            return
        }
        // Snapshot of the LIVE window via the window compositor. One screen per process — the
        // shell loops launches. Replaced the cacheDisplay exporter, which lost the vibrancy
        // sidebar and captured at a width below the window minimum.
        // Badge variants gallery: a visual choice is judged by eye, not by description.
        // Gallery of toasts and the recording pill.
        if ProcessInfo.processInfo.environment["KEYLY_SURFACE_VARIANTS"] == "1" {
            Task { @MainActor in
                let renderer = ImageRenderer(content: SurfaceVariantsSheet())
                renderer.scale = 2
                let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KEYLY_QA_OUT"] ?? ".qa-shots")
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    let url = out.appendingPathComponent("surface-variants.png")
                    try? png.write(to: url)
                    print("SURFACE VARIANTS: \(url.path)")
                }
                NSApp.terminate(nil)
            }
            return
        }

        // Toast variants gallery: a design choice is judged by eye, not by description.
        if ProcessInfo.processInfo.environment["KEYLY_TOAST_VARIANTS"] == "1" {
            Task { @MainActor in
                let renderer = ImageRenderer(content: ToastVariantsSheet())
                renderer.scale = 2
                let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KEYLY_QA_OUT"] ?? ".qa-shots")
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    let url = out.appendingPathComponent("toast-variants.png")
                    try? png.write(to: url)
                    print("TOAST VARIANTS: \(url.path)")
                }
                NSApp.terminate(nil)
            }
            return
        }

        if ProcessInfo.processInfo.environment["KEYLY_BADGE_VARIANTS"] == "1" {
            Task { @MainActor in
                let renderer = ImageRenderer(content: BadgeVariantsSheet())
                renderer.scale = 2
                let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KEYLY_QA_OUT"] ?? ".qa-shots")
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    let url = out.appendingPathComponent("badge-variants.png")
                    try? png.write(to: url)
                    print("BADGE VARIANTS: \(url.path)")
                }
                NSApp.terminate(nil)
            }
            return
        }
        // Mockups of the chosen concepts in REAL tokens — to see how they look live before
        // deciding. NOT wired into the product: only a preview window and a snapshot, app
        // navigation does not change.
        if let concept = ProcessInfo.processInfo.environment["KEYLY_CONCEPT"], !concept.isEmpty {
            Task { @MainActor in await ConceptShotter.run(concept) }
            return
        }
        if let shot = ProcessInfo.processInfo.environment["KEYLY_LIVESHOT"], !shot.isEmpty {
            Task { @MainActor in await LiveWindowCapture.run() }
            return
        }
        // Live probe of the dictation pill: drives the REAL overlay controller through the
        // "recording → processing" phases and asserts what a screenshot can't check at all — that
        // the window is on all Spaces, above full-screen apps, and survives a stop.
        if ProcessInfo.processInfo.environment["KEYLY_PILL_PROBE"] == "1" {
            Task { @MainActor in await VoicePillProbe.run() }
            return
        }
        // Safe redesign preview: a live interactive window WITHOUT event tap/hotkeys/menu bar/
        // permission prompts — doesn't interfere with a running Keyly or with the user's input.
        if ProcessInfo.processInfo.environment["KEYLY_PREVIEW"] == "1" {
            showPreviewWindow()
            return
        }
        #endif
        guard SingleInstanceGuard.claim() else {
            NSApp.terminate(nil)
            return
        }
        LaunchAtLoginSync.reconcile()
        storeFailureAlert.startObserving()
        VoiceRecorder.removeLeftoverRecordings()
        applyUIVisibility()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(uiVisibilityChanged),
                                               name: .uiVisibilityChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleOpenSnippetInEditor(_:)),
                                               name: .openSnippetInEditor,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleShowWizardAgain),
                                               name: .showWizardAgain,
                                               object: nil)

        lastAccessTrusted = AccessibilityPermission.ensurePermission(prompt: true)
        _ = MicrophonePermission.ensurePermission(prompt: true)
        // The third permission without which NOT A SINGLE key arrives: "Input Monitoring".
        // It is separate from Accessibility (`kTCCServiceListenEvent`) and used to be unchecked —
        // the app reported "all set" with two permissions out of three while hotkeys stayed
        // silent. Easily lost when the .app is replaced: the grant is tied to the signature.
        if !InputMonitoringPermission.isGranted {
            Log.warn(.app, "Мониторинг ввода не выдан — клавиши в event tap не придут")
            InputMonitoringPermission.request()
        }
        updateHotKeys(for: lastAccessTrusted)
        startAccessMonitor()
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["KEYLY_GALLERY"] == "1" {
            showGallery()
            return
        }
        switch env["KEYLY_SCREEN"] {
        case "settings": showOnboarding(openSettings: true); return
        case "voice":    showOnboarding(selectedModule: .voiceToText); return
        case "errorfix": showOnboarding(selectedModule: .errorFix); return
        case "layout":   showOnboarding(selectedModule: .layoutSwitch); return
        case "apps":     showOnboarding(selectedModule: .appLauncher); return
        default: break
        }
        #endif
        // First launch → wizard, afterwards always the main window. The flag is set by the
        // "Done" button, not by the fact of showing: closed halfway — the wizard comes back.
        // Starter examples are seeded BEFORE the window shows: otherwise the user sees an empty
        // list and concludes the app can't do anything.
        StarterContent.seedIfNeeded()

        if UserDefaults.standard.bool(forKey: SettingsKeys.wizardCompleted) {
            showOnboarding()
        } else {
            showWizard()
        }
    }

    #if DEBUG
    private var previewWindow: NSWindow?
    /// Interactive onboarding/settings window for visually previewing the redesign.
    /// No input interception and no system prompts — UI on real data only.
    private func showPreviewWindow() {
        let vm = OnboardingViewModel()
        let hosting = NSHostingController(rootView: OnboardingView(model: vm))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.title = "Keyly · Preview (редизайн)"
        window.setContentSize(CGSize(width: 1040, height: 720))
        window.center()
        previewWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private var galleryWindow: NSWindow?
    private func showGallery() {
        let hosting = NSHostingController(rootView: DesignGalleryView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Keyly · Gallery"
        window.setContentSize(CGSize(width: 720, height: 760))
        window.center()
        galleryWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        accessMonitorTimer?.invalidate()
        HotKeyManager.shared.stop()
        NotificationCenter.default.removeObserver(self)
    }

    /// Called on a Dock icon click AND when the already running app is launched again
    /// (Finder/Spotlight/Launchpad). This is the only guaranteed way to open the window
    /// when both icons (menu bar and Dock) are hidden — relaunching the app lands here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOnboarding()
        return true
    }

    @objc private func uiVisibilityChanged() {
        applyUIVisibility()
    }

    /// Dock icon visibility = activation policy: shown (regular) / hidden (accessory).
    /// Idempotent — doesn't touch it if already in the desired mode.
    private func applyActivationPolicy() {
        let desired: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
        }
    }

    private func applyUIVisibility() {
        applyActivationPolicy()

        if showMenuBarIcon {
            if menuBarController == nil {
                let controller = MenuBarController()
                controller.showOnboardingHandler = { [weak self] module, openSettings in
                    self?.showOnboarding(selectedModule: module, openSettings: openSettings)
                }
                menuBarController = controller
                // Pause survives a restart (people set it and walk away) — the icon must show it
                // immediately, not after the first hotkey press.
                controller.applyPauseState()
            }
        } else {
            menuBarController?.removeStatusItem()
            menuBarController = nil
        }

        VoiceToTextManager.shared.statusPresenter = menuBarController
        VoiceToTextManager.shared.statusAnimator = menuBarController
        VoiceToTextManager.shared.overlayPresenter = voiceRecordingOverlayController
        VoiceToTextManager.shared.realtimeIndicatorPresenter = realtimeIndicatorController
        VoiceToTextManager.shared.errorToastPresenter = voiceErrorToastController
        ErrorFixer.shared.statusAnimator = menuBarController
        ErrorFixer.shared.errorPresenter = voiceErrorToastController
        // The badge at the caret is the shared channel for short statuses of all text features.
        ErrorFixer.shared.badgePresenter = badgeController
        CustomModuleRunner.shared.badgePresenter = badgeController
        // Popup for the "Show" output: the same controller that shows voice toasts — a second
        // one would create two always-on-top windows with different geometry.
        CustomModuleRunner.shared.toastPresenter = voiceErrorToastController
        VoiceToTextManager.shared.badgePresenter = badgeController
        SnippetService.shared.badgePresenter = badgeController
        AppLauncherService.shared.badgePresenter = badgeController
        TextPolisher.errorToastPresenter = voiceErrorToastController
        // Start the network monitor at launch: an on-demand query answers no sooner than a few
        // hundred milliseconds, so the very first check would say "unknown".
        NetworkReachability.shared.start()
        // Load an already downloaded local model into memory at launch — silently, downloading NOTHING.
        // Readiness lived only in RAM and reset on every launch: the model was on disk, yet after
        // a restart the app treated it as missing and said so only AFTER the user had dictated
        // a long phrase.
        Task { await LocalTranscriber.shared.warmUpIfDownloaded() }
        TextSelector.badgePresenter = badgeController
        UndoActionService.shared.badgePresenter = badgeController
        // Polishing must explain refusals too: without this "Polish" silently returns the raw
        // text, and the toggle looks broken.
        TextPolisher.badgePresenter = badgeController
        // The operation gate itself shows "Already working…" and "Cancelled" — otherwise six
        // services would print six wordings of the same refusal.
        OperationGate.badgePresenter = badgeController
        CustomModuleRunner.shared.statusAnimator = menuBarController
        CustomModuleRunner.shared.errorPresenter = voiceErrorToastController
        // Clicking the error toast opens Settings (where the key/model are configured).
        voiceErrorToastController.onOpenSettings = { [weak self] in
            self?.showOnboarding(openSettings: true)
        }
    }

    // MARK: - Accessibility monitoring

    private func startAccessMonitor() {
        accessMonitorTimer?.invalidate()
        accessMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
            guard let self else { return }
            let trusted = AccessibilityPermission.isTrusted
            if trusted != lastAccessTrusted {
                lastAccessTrusted = trusted
                updateHotKeys(for: trusted)
            }
            // Tap health is checked ACTUALLY, not by the presence of the grant: the permission may
            // be granted while the tap failed to create or silently died.
            HotKeyManager.shared.pollTapHealth()
        })
        if let timer = accessMonitorTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateHotKeys(for trusted: Bool) {
        if trusted {
            if !hotKeysRunning {
                HotKeyManager.shared.start()
                ClickTracker.shared.start() // feeds the caret hit test in CaretProbe
                #if DEBUG
                CaretProbeDebug.installIfEnabled() // ⌃⌥⌘P: manual runtime check of CaretProbe (KEYLY_CARET_DEBUG=1)
                #endif
                hotKeysRunning = true
            }
        } else {
            if hotKeysRunning {
                HotKeyManager.shared.stop()
                ClickTracker.shared.stop()
                hotKeysRunning = false
            }
        }
    }


    /// The palette asks to open the window on snippets. The window may be closed — then it must
    /// be shown first, otherwise nobody hears the notification and the press goes nowhere.
    /// Showing the wizard again from settings. The main window is hidden: two windows on top
    /// of each other leave the user unsure where they are and what to close.
    @objc private func handleShowWizardAgain() {
        onboardingWindow?.orderOut(nil)
        showWizard()
    }

    @objc private func handleOpenSnippetInEditor(_ note: Notification) {
        showOnboarding()
        // Re-post AFTER showing: a freshly created window subscribes only now.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openSnippetInEditor, object: note.object)
        }
    }

    func showOnboarding(selectedModule: ModuleKind? = nil, openSettings: Bool = false) {
        onboardingViewModel.selectedModule = selectedModule
        onboardingViewModel.openSettings = openSettings

        let contentView = OnboardingView(
            model: onboardingViewModel,
            onClose: { [weak self] in self?.closeOnboarding() },
            onSizeChange: { [weak self] size in self?.resizeOnboarding(to: size) }
        )
        let isNewWindow = onboardingWindow == nil
        if let hosting = onboardingWindow?.contentViewController as? NSHostingController<OnboardingView> {
            hosting.rootView = contentView
            if let window = onboardingWindow {
                applyWindowChrome(window)
            }
        } else {
            let hosting = NSHostingController(rootView: contentView)
            let window = NSWindow(contentViewController: hosting)
            // FIXED-size window with no zoom button, by design.
            // `.closable` stays in the mask on purpose: the traffic-light buttons are hidden, but
            // without this flag ⌘W stops working — the window would become a trap.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.title = ""
            window.isReleasedWhenClosed = false
            window.minSize = Self.defaultWindowSize
            window.maxSize = Self.defaultWindowSize
            applyWindowChrome(window)
            onboardingWindow = window
        }

        if let window = onboardingWindow {
            // Set the size ONLY for a new window and only if the system hasn't restored a saved
            // frame. It used to be forced on every show — and a window the user had shrunk sprang
            // back each time: `setFrameAutosaveName` worked, but its result was overwritten at once
            // (the size must be remembered).
            if isNewWindow, !hasRestoredFrame(window) {
                resizeOnboarding(to: Self.defaultWindowSize)
            }
            if isNewWindow {
                window.center()
            }
            // Bring the restored frame into the VISIBLE area. A monitor was unplugged, the resolution
            // changed, the window stayed outside the desktop — and the app "doesn't open": it opened
            // where nobody can see it.
            bringIntoVisibleArea(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            // orderFrontRegardless raises the window even when the app is in .accessory mode
            // (Dock icon hidden) and cannot become active the normal way.
            window.orderFrontRegardless()
            // Activating the window may have "brought back" the Dock icon. Reassert the policy
            // deferred — after activation has finished.
            DispatchQueue.main.async { [weak self] in
                self?.applyActivationPolicy()
            }
        }
    }

    // MARK: - First-launch wizard

    private var wizardWindow: NSWindow?

    private func showWizard() {
        let hosting = NSHostingController(rootView: WizardView(onFinish: { [weak self] in
            UserDefaults.standard.set(true, forKey: SettingsKeys.wizardCompleted)
            self?.wizardWindow?.close()
            self?.wizardWindow = nil
            self?.showOnboarding()
        }))
        let window = NSWindow(contentViewController: hosting)
        // No .resizable: the steps are laid out for a fixed size, and stretching leaves dead
        // space around a short step.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // DISABLED: dragging list rows (snippets, launch targets) starts from the row background,
        // and window dragging hijacked the gesture — the whole window moved instead of the row.
        // The title bar is still there for moving the window, which is enough.
        window.isMovableByWindowBackground = false
        applyThemeBackground(window)
        window.setContentSize(CGSize(width: 620, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        wizardWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    /// Default window size. Width 1040: at 1080 the three-pane snippets screen used to need
    /// 1120 or the right pane collapsed; at 1120 the right part of the screen was empty.
    /// The three-pane screen still works — the list is narrowed to 260pt, the editor keeps
    /// the same width as before.
    /// Height 860, not 720: at 720 the "Voice" screen was cut mid-word at "Text processing".
    /// The product has no scroll bars by design and no continuation hint either — a clipped
    /// label reads as a broken screen. Enlarging the window removes and moves nothing, unlike
    /// squeezing sections. 860 fits a 13-inch MacBook (work area ~900pt).
    static let defaultWindowSize = CGSize(width: 1040, height: 860)

    /// Whether the system restored the saved window frame (`setFrameAutosaveName`).
    /// If so, the default size must not be forced — that is the "remembered" size.
    /// Brings the window back on screen if the saved frame ended up outside the visible area.
    ///
    /// Width is raised to the minimum: the saved frame could be narrower if the minimum grew
    /// between versions, and then the sidebar and content would overlap.
    /// Window size that ACTUALLY fits on this screen.
    ///
    /// The window became fixed and non-resizable, which exposed a trap: 860pt doesn't fit a
    /// 13-inch MacBook Air — 900 logical points minus the menu bar and Dock give ~805pt.
    /// `setFrame(_:display:)` is NOT limited by `minSize` (clamping happens only on
    /// interactive resize), so the window would silently shrink below its own minimum — with
    /// no way to enlarge it: no frame, no zoom.
    ///
    /// So we fix not a constant but what fits: 1040×860 on a large screen, screen-sized on a
    /// small one. Content inside scrolls, nothing is cut off.
    static func fittingWindowSize(on screen: NSScreen?) -> CGSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        guard visible != .zero else { return defaultWindowSize }
        let inset: CGFloat = 24
        return CGSize(width: min(defaultWindowSize.width, visible.width - inset),
                      height: min(defaultWindowSize.height, visible.height - inset))
    }

    private func bringIntoVisibleArea(_ window: NSWindow) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        guard visible != .zero else { return }

        // Re-fix the size for the CURRENT screen: the window may have been dragged to another monitor.
        let fitting = Self.fittingWindowSize(on: window.screen)
        window.minSize = fitting
        window.maxSize = fitting

        var frame = window.frame
        frame.size = fitting
        // Check INTERSECTION, not full containment: a window half past the edge is visible and
        // the user can move it themselves — no need to yank it.
        if !visible.intersects(frame) {
            frame.origin = CGPoint(x: visible.midX - frame.width / 2,
                                   y: visible.midY - frame.height / 2)
            Log.info(.app, "Окно было вне видимой области — возвращено на экран")
        }
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    private func hasRestoredFrame(_ window: NSWindow) -> Bool {
        UserDefaults.standard.string(forKey: "NSWindow Frame \(window.frameAutosaveName)") != nil
    }

    private func resizeOnboarding(to size: CGSize) {
        guard let window = onboardingWindow else { return }
        let clamped = CGSize(width: max(Self.defaultWindowSize.width, size.width),
                             height: max(Self.defaultWindowSize.height, size.height))
        window.setContentSize(clamped)
    }


    /// Window background = theme background. `titlebarAppearsTransparent` makes the title bar
    /// transparent, but the SYSTEM window background (#1b1b1b) stays under it — lighter than
    /// every product surface, so every screen had the lightest strip of the UI on top.
    private func applyThemeBackground(_ window: NSWindow) {
        window.backgroundColor = NSColor(srgbRed: 7/255, green: 7/255, blue: 7/255, alpha: 1)
    }

    /// Local Esc and ⌘W monitor that lives along with the settings window.
    ///
    /// The only guaranteed way to close a window without traffic-light buttons: it depends
    /// neither on the activation policy nor on whether SwiftUI drew the app menu.
    /// The close button in the window sends the same as Esc and ⌘W: one exit, three ways to reach it.
    private func observeCloseRequests() {
        guard closeRequestObserver == nil else { return }
        closeRequestObserver = NotificationCenter.default.addObserver(
            forName: .closeOnboardingWindow, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closeOnboarding() }
        }
    }

    private func installEscapeHatch(_ window: NSWindow) {
        guard escapeHatch == nil else { return }
        escapeHatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let window, window.isKeyWindow else { return event }
            let isEscape = event.keyCode == 53
            let isCommandW = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "w"
            guard isEscape || isCommandW else { return event }
            Log.info(.app, "Окно настроек закрыто с клавиатуры (\(isEscape ? "Esc" : "⌘W"))")
            self?.closeOnboarding()
            return nil
        }
    }

    private func applyWindowChrome(_ window: NSWindow) {
        applyThemeBackground(window)
        installEscapeHatch(window)
        observeCloseRequests()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // DISABLED: dragging list rows (snippets, launch targets) starts from the row background,
        // and window dragging hijacked the gesture — the whole window moved instead of the row.
        // The title bar is still there for moving the window, which is enough.
        window.isMovableByWindowBackground = false
        // NO traffic-light buttons, by design.
        //
        // The exit is provided EXPLICITLY (`installEscapeHatch`), not by hoping for AppKit: with
        // the Dock icon hidden the app lives in `.accessory`, where there is no app menu at all —
        // so ⌘W may not exist, and the window would have no way to close. An earlier version
        // promised three ways out (⌘W, Esc, icon click); in practice at most one worked.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
