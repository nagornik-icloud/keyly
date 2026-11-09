import Foundation

/// Decides what moves from the pre-rename UserDefaults domain to the current one.
/// Pure logic; the side-effecting runner lives in `LegacyDomainMigrator`.
enum LegacyDomainMigration {
    static let doneFlagKey = "migration.legacyDomain.v1"

    /// API keys move to Keychain separately and must never be copied as plain text.
    static let secretKeys: Set<String> = ["apiKeys.storage"]

    /// Window frames, open panels, language overrides — owned by AppKit, not by the user.
    static let systemPrefixes = ["NS", "Apple"]

    static func shouldRun(currentBundleID: String?, alreadyDone: Bool) -> Bool {
        currentBundleID != AppIdentity.legacyBundleID && !alreadyDone
    }

    static func entriesToCopy(from legacy: [String: Any]) -> [String: Any] {
        legacy.filter { key, _ in
            !secretKeys.contains(key) && !systemPrefixes.contains { key.hasPrefix($0) }
        }
    }
}
