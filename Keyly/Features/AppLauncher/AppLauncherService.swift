import AppKit

/// Launches app-launcher targets.
///
/// Separate from `HotKeyManager`: that one knows WHAT was pressed, not how to open a folder or
/// hide the active app. Launching used to live inside the hotkey manager and handled only one
/// case out of four.
@MainActor
final class AppLauncherService {
    static let shared = AppLauncherService()

    weak var badgePresenter: BadgePresenting?

    private init() {}

    func launch(_ shortcut: AppLaunchShortcut) {
        // Take the path FROM THE BOOKMARK: the app may have been moved or renamed, and the
        // saved string would point nowhere.
        let path = shortcut.bookmark == nil ? shortcut.appPath : shortcut.resolvedURL.path
        guard let target = LaunchTarget.resolve(path, bundleIdentifier: Self.bundleId(at:)) else {
            report(failure: shortcut)
            return
        }

        switch target {
        case .application(let bundleId, let url):
            // Pressing again while the app is ALREADY active hides it: the hotkey becomes a
            // toggle, one key goes there and back. Without this the second press does
            // nothing — and looks like a hotkey that didn't fire.
            if let bundleId, let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleId).first,
               running.isActive {
                running.hide()
                Log.info(.hotKey, "AppLauncher: \(shortcut.displayName) уже активен — спрятали")
                return
            }
            open(url: url, shortcut: shortcut)

        case .file(let url), .link(let url):
            open(url: url, shortcut: shortcut)
        }
    }

    private func open(url: URL, shortcut: AppLaunchShortcut) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if url.isFileURL, url.pathExtension.lowercased() == "app" {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in self?.finish(error: error, shortcut: shortcut) }
            }
        } else {
            NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in self?.finish(error: error, shortcut: shortcut) }
            }
        }
    }

    /// SUCCESS is not reported: the app opened, that's visible. Failure is reported, otherwise
    /// it is indistinguishable from "the hotkey didn't fire".
    private func finish(error: Error?, shortcut: AppLaunchShortcut) {
        guard let error else {
            Log.info(.hotKey, "AppLauncher: открыто \(shortcut.displayName)")
            return
        }
        Log.error(.hotKey, "AppLauncher: не удалось открыть \(shortcut.displayName) — \(error.localizedDescription)")
        report(failure: shortcut)
    }

    private func report(failure shortcut: AppLaunchShortcut) {
        badgePresenter?.showBadge(BadgeText.launchFailed, kind: .warning)
    }

    private static func bundleId(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}
