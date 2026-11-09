import Cocoa
import SwiftUI

@MainActor
protocol MenuBarAnimating: AnyObject {
    func beginMenuAnimation()
    func endMenuAnimation()
}

class MenuBarController: NSObject, VoiceTimerPresenting, MenuBarAnimating {
    var showOnboardingHandler: ((ModuleKind?, Bool) -> Void)?

    private var statusItem: NSStatusItem?
    private let defaultImage: NSImage? = {
        let img = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "Magic")
        img?.isTemplate = true
        return img
    }()
    private lazy var spinner: NSProgressIndicator = {
        let p = NSProgressIndicator()
        p.style = .spinning
        p.controlSize = .small
        p.isIndeterminate = true
        p.isDisplayedWhenStopped = false
        return p
    }()

    /// Icon states. Each one must be reachable: a case with no way to enter it looks like a
    /// done feature while showing nothing.
    private enum MenuBarState { case normal, recording, animating, alarm, paused }
    private var currentState: MenuBarState = .normal

    /// Pause has its own icon. A pause visible only in the menu is useless: the user turns it on
    /// and forgets, then presses a hotkey and decides the product is broken.
    private let pausedImage: NSImage? = {
        let img = NSImage(systemSymbolName: "pause.circle",
                          accessibilityDescription: "menubar.paused.a11y".loc)
        img?.isTemplate = true
        return img
    }()

    /// Alarm icon: the event tap hasn't come up for longer than the threshold, and the product
    /// silently doesn't work. Without a visible sign the user thinks Keyly is broken and doesn't
    /// know what to fix — and the fix is granting the permission in System Settings.
    private let alarmImage: NSImage? = {
        let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                          accessibilityDescription: "menubar.dead.a11y".loc)
        img?.isTemplate = true
        return img
    }()

    override init() {
        super.init()

        installStatusItemIfNeeded()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(rebuildMenu),
                                               name: .customHotKeyChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(tapHealthChanged),
                                               name: .eventTapHealthChanged,
                                               object: nil)
        rebuildMenu()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DispatchQueue.main.async { [weak self] in
            self?.removeStatusItem()
        }
    }

    // MARK: - VoiceTimerPresenting

    func showVoiceTimer(_ text: String) {
        guard let button = statusItem?.button else { return }
        currentState = .recording
        let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
        mic?.isTemplate = true
        button.image = mic
        button.contentTintColor = .systemRed
        button.title = ""
        button.imagePosition = .imageOnly
    }

    func hideVoiceTimer() {
        guard currentState == .recording else { return }
        restoreNormalIcon()
    }

    func hideMenuBarIcon() {
        removeStatusItem()
    }

    func restoreMenuBarIcon() {
        installStatusItemIfNeeded()
    }

    // MARK: - MenuBarAnimating

    func beginMenuAnimation() {
        guard currentState == .normal, let button = statusItem?.button else { return }
        currentState = .animating
        // Fix the width, otherwise variableLength collapses to 0 without an image.
        statusItem?.length = 24
        button.image = nil
        button.title = ""
        if spinner.superview !== button {
            button.addSubview(spinner)
        }
        spinner.frame = NSRect(
            x: (button.bounds.width - 16) / 2,
            y: (button.bounds.height - 16) / 2,
            width: 16,
            height: 16
        )
        spinner.startAnimation(nil)
    }

    func endMenuAnimation() {
        guard currentState == .animating else { return }
        spinner.stopAnimation(nil)
        spinner.removeFromSuperview()
        statusItem?.length = NSStatusItem.variableLength
        restoreNormalIcon()
    }

    private func restoreNormalIcon() {
        guard let button = statusItem?.button else { return }
        currentState = .normal
        button.image = defaultImage
        // Reset the tint — a template image then adapts to the menu bar theme by itself.
        button.contentTintColor = nil
        button.title = ""
        button.imagePosition = .imageOnly
    }

    // MARK: - Menu

    /// Toggles pause from the menu.
    @objc private func togglePause() {
        AppPause.isPaused.toggle()
        Log.info(.app, "Пауза: \(AppPause.isPaused ? "включена" : "снята")")
        applyPauseState()
        rebuildMenu()
    }

    /// The icon must reflect the pause — otherwise it is visible only in the menu.
    func applyPauseState() {
        if AppPause.isPaused {
            currentState = .paused
            statusItem?.button?.image = pausedImage
            statusItem?.button?.toolTip = "menubar.paused.tooltip".loc
        } else if currentState == .paused {
            currentState = .normal
            statusItem?.button?.image = defaultImage
            statusItem?.button?.toolTip = nil
        }
    }

    @objc func rebuildMenu() {
        guard let statusItem = statusItem else { return }
        let menu = NSMenu()

        // The menu is MINIMAL — "Open Keyly" · "Settings…" · "Quit", no actions, everything via
        // hotkeys. Removed: instant actions of three modules, the apps submenu and on/off toggles —
        // all reachable via hotkeys and on screens, and in the menu they were duplicates.
        //
        // KEPT deliberately, because for them the menu is the ONLY way, and removing it would mean
        // dropping the feature rather than moving the entry point:
        //   · custom modules and snippets WITHOUT a hotkey — there is no other way to run them;
        //     they will leave the menu once the snippet palette and a mandatory module hotkey exist.
        let custom = CustomModuleStore.load().filter { $0.hotKey == nil }
        if !custom.isEmpty {
            menu.addItem(submenuItem("menu.customModules".loc, items: custom.map {
                menuLeaf($0.name.isEmpty ? "menu.untitled".loc : $0.name,
                         #selector(menuRunCustom(_:)), represented: $0)
            }))
        }
        let snippets = SnippetStore.load().filter { $0.isEnabled && $0.hotKey == nil && $0.triggers.isEmpty }
        if !snippets.isEmpty {
            menu.addItem(submenuItem("menu.snippets".loc, items: snippets.map {
                // displayTitle is the single fallback point "name, otherwise start of text".
                // The previous empty-string check lived here as its own copy and produced
                // "Untitled" where seeing the snippet text itself is more useful.
                menuLeaf($0.displayTitle.loc, #selector(menuInsertSnippet(_:)), represented: $0)
            }))
        }
        if !custom.isEmpty || !snippets.isEmpty { menu.addItem(.separator()) }

        // "Undo last action" was REMOVED from the menu. The item came and went depending on
        // whether there was anything to undo — the menu jumped around, while undo itself lives on
        // a hotkey (⌥⌘Z by default) and in the list of global shortcuts. The entry point wasn't
        // removed, only the flickering duplicate.

        menu.addItem(actionItem("menu.open".loc, #selector(showOnboarding)))
        // Pause is the only ACTION in the menu: everything else is reachable via hotkeys and on
        // screens. It genuinely needs the menu: when all hotkeys are off, there is no other way to
        // turn them back on.
        let pauseItem = actionItem(AppPause.isPaused ? "menu.resume".loc : "menu.pause".loc,
                                   #selector(togglePause))
        pauseItem.state = AppPause.isPaused ? .on : .off
        menu.addItem(pauseItem)
        menu.addItem(actionItem("menu.settings".loc, #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem("menu.quit".loc, #selector(quitApp), key: "q"))

        statusItem.menu = menu
    }

    private func actionItem(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        return it
    }

    private func menuLeaf(_ title: String, _ sel: Selector, represented: Any) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.representedObject = represented
        return it
    }

    private func submenuItem(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }


    // MARK: - Actions

    @objc private func showOnboarding() {
        showOnboardingHandler?(nil, false)
    }

    @objc private func openSettings() {
        if let handler = showOnboardingHandler {
            handler(nil, true)
        } else if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showOnboarding(openSettings: true)
        }
    }

    // MARK: - Instant menu actions (same path as the hotkey)



    @objc private func menuRunCustom(_ sender: NSMenuItem) {
        guard let module = sender.representedObject as? CustomAIModule else { return }
        HotKeyManager.shared.menuRunCustom(module)
    }

    @objc private func menuInsertSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        Task { @MainActor in SnippetService.shared.insert(snippet) }
    }

    /// Toggles a module's master switch — the same mechanism as the switch in the window (flag + re-registration).
    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let cur = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        UserDefaults.standard.set(!cur, forKey: key)
        NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Status item lifecycle

    func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = defaultImage
            button.imagePosition = .imageOnly
        }
        statusItem = item
        rebuildMenu()
    }

    /// Tap health changed. The alarm overrides the idle state but does NOT override recording and
    /// processing: if the user is dictating right now, swapping the icon for a triangle would
    /// remove the only sign that recording is in progress.
    @MainActor
    @objc private func tapHealthChanged() {
        let unhealthy = HotKeyManager.shared.tapIsUnhealthy
        switch (unhealthy, currentState) {
        case (true, .normal):
            currentState = .alarm
            statusItem?.button?.image = alarmImage
            statusItem?.button?.toolTip = "menubar.dead.tooltip".loc
        case (false, .alarm):
            currentState = .normal
            statusItem?.button?.image = defaultImage
            statusItem?.button?.toolTip = nil
        default:
            break   // recording or processing in progress — leave the icon alone
        }
    }

    @MainActor
    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

}
