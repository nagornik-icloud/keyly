import Foundation

/// Persists API keys in Keychain (never in UserDefaults) and moves old plain-text copies
/// there once. Same envelope format and the same "never overwrite unreadable data" rule
/// as `VersionedStore`: keys are issued by the provider and cannot be recovered.
@MainActor
final class APIKeyVault {
    /// Where keys lived as plain text before; still read once for migration.
    static let plaintextKey = "apiKeys.storage"

    private let vault: SecretBlobStore
    private let defaults: UserDefaults
    private var writeBlocked = false

    /// The keys could not be read (Keychain denied, unreadable data, tool run). The list
    /// returned by load() is then "unknown", not "none" — nothing may be reset because of it.
    var keysUnknown: Bool { writeBlocked }

    init(vault: SecretBlobStore = KeychainBlobStore(account: "apiKeys"), defaults: UserDefaults = .standard) {
        self.vault = vault
        self.defaults = defaults
    }

    func load() -> [APIKeyEntry] {
        // Screenshot/probe runs must not move or erase the user's real keys.
        guard !AppRunMode.isToolRun else {
            writeBlocked = true
            #if DEBUG
            // Demo keys live only in memory: writes stay blocked, nothing reaches Keychain.
            if DemoContent.isActive { return DemoContent.apiKeys }
            #endif
            return []
        }
        let plaintext = defaults.data(forKey: Self.plaintextKey) ?? legacyPlaintext()
        let outcome = SecretMigration.moveIfNeeded(vault: vault, plaintext: plaintext)
        if outcome.plaintextMayBeErased {
            erasePlaintext()
        }
        switch outcome {
        case .moved(let data):
            Log.info(.app, "API keys moved from settings to Keychain")
            return decode(data)
        case .alreadyInVault(let data):
            return decode(data)
        case .nothingToMove:
            return []
        case .failed:
            // Keychain denied or broken. Keys may exist there, so writing now could replace
            // them: block writes for this launch and work from the plain copy, if any.
            writeBlocked = true
            Log.error(.app, "API keys: Keychain unavailable, writes blocked until restart")
            return decode(plaintext)
        }
    }

    @discardableResult
    func save(_ keys: [APIKeyEntry]) -> Bool {
        guard !writeBlocked else {
            Log.error(.app, "API keys: write refused — stored keys could not be read at launch")
            return false
        }
        do {
            try vault.write(try StoreEnvelope.encode(keys))
            return true
        } catch {
            Log.error(.app, "API keys: Keychain write failed")
            return false
        }
    }

    private func decode(_ data: Data?) -> [APIKeyEntry] {
        switch StoreEnvelope.decode(data, as: APIKeyEntry.self) {
        case .empty:
            return []
        case .ok(let items, _):
            return items
        case .corrupted(_, let reason):
            writeBlocked = true
            Log.error(.app, "API keys: stored data unreadable (\(LogSanitizer.sanitize(reason))), writes blocked")
            return []
        }
    }

    /// Before the rename keys lived in the old app's domain; the settings migration skips
    /// them on purpose, so they are read straight from there.
    private func legacyPlaintext() -> Data? {
        guard AppIdentity.isReleaseIdentity else { return nil }
        return defaults.persistentDomain(forName: AppIdentity.legacyBundleID)?[Self.plaintextKey] as? Data
    }

    private func erasePlaintext() {
        defaults.removeObject(forKey: Self.plaintextKey)
        guard AppIdentity.isReleaseIdentity,
              var legacy = defaults.persistentDomain(forName: AppIdentity.legacyBundleID),
              legacy[Self.plaintextKey] != nil else { return }
        legacy.removeValue(forKey: Self.plaintextKey)
        defaults.setPersistentDomain(legacy, forName: AppIdentity.legacyBundleID)
    }
}
