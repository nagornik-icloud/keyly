import Foundation

/// Copies the user's settings from the pre-rename domain (`personal.punto-switcher`) once.
/// Runs before anything reads UserDefaults or seeds starter content: the legacy values
/// replace whatever the new domain holds, which at that point is nothing or only seed data.
enum LegacyDomainMigrator {
    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !AppRunMode.isToolRun else { return }
        let flag = LegacyDomainMigration.doneFlagKey
        guard LegacyDomainMigration.shouldRun(currentBundleID: Bundle.main.bundleIdentifier,
                                              alreadyDone: defaults.bool(forKey: flag)) else { return }
        // An old copy still running could save settings on quit after we copied them.
        SingleInstanceGuard.quitLegacyCopies()
        guard let legacy = defaults.persistentDomain(forName: AppIdentity.legacyBundleID), !legacy.isEmpty else {
            defaults.set(true, forKey: flag)
            return
        }
        let entries = LegacyDomainMigration.entriesToCopy(from: legacy)
        for (key, value) in entries { defaults.set(value, forKey: key) }

        // The flag is set only after every value reads back equal; otherwise retry next launch.
        let mismatched = entries.filter { key, value in
            (defaults.object(forKey: key) as? NSObject)?.isEqual(value) != true
        }.keys
        guard mismatched.isEmpty else {
            Log.error(.app, "Legacy settings migration: \(mismatched.count) values did not verify, will retry")
            return
        }
        defaults.set(true, forKey: flag)
        Log.info(.app, "Legacy settings migration: copied \(entries.count) values")
    }
}
