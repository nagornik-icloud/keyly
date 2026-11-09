import AppKit

/// Two copies of Keyly would both grab the same global hotkeys and fight over the clipboard.
enum SingleInstanceGuard {
    /// Quits a still-running pre-rename copy and waits for it to exit, so that settings it
    /// saves on quit are on disk before they are migrated. Force-quits after `timeout`.
    static func quitLegacyCopies(timeout: TimeInterval = 3) {
        guard !AppRunMode.isToolRun else { return }
        let legacy = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.legacyBundleID)
        guard !legacy.isEmpty else { return }
        Log.warn(.app, "Pre-rename copy is running (\(legacy.count)) — asking it to quit")
        legacy.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while legacy.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        for app in legacy where !app.isTerminated {
            Log.error(.app, "Pre-rename copy did not quit in \(Int(timeout)) s — force quitting")
            app.forceTerminate()
        }
    }

    /// Returns false when another copy of this build should keep running: it is brought to
    /// the front and this launch should quit. When two copies start at once, the one with
    /// the lower pid stays, so exactly one survives.
    static func claim() -> Bool {
        guard !AppRunMode.isToolRun else { return true }
        quitLegacyCopies()
        let me = NSRunningApplication.current
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != me && !$0.isTerminated }
        guard let keeper = others.min(by: { $0.processIdentifier < $1.processIdentifier }),
              keeper.processIdentifier < me.processIdentifier else { return true }
        Log.warn(.app, "Another Keyly is running (pid \(keeper.processIdentifier)) — handing over and quitting")
        keeper.activate()
        return false
    }
}
