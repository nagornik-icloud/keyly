import Foundation

/// A place that keeps one opaque secret blob (Keychain in the app, memory in tests).
protocol SecretBlobStore: AnyObject {
    /// nil = nothing stored yet. Throws when the store exists but cannot be read
    /// (access denied, keychain locked) — that is not the same as "empty".
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// Moves secrets out of plain-text UserDefaults into a `SecretBlobStore`.
enum SecretMigration {
    enum Outcome: Equatable {
        /// Vault readable and empty, no plain copy either.
        case nothingToMove
        /// Vault already held data (returned, so callers never need a second read).
        case alreadyInVault(Data)
        /// Plain copy written to the vault and read back identical.
        case moved(Data)
        /// Vault unreadable or write failed: the vault must not be written over.
        case failed

        /// The plain-text copy may be deleted only when the vault provably holds the keys.
        var plaintextMayBeErased: Bool {
            switch self {
            case .moved, .alreadyInVault: return true
            case .nothingToMove, .failed: return false
            }
        }
    }

    static func moveIfNeeded(vault: SecretBlobStore, plaintext: Data?) -> Outcome {
        let existing: Data?
        do { existing = try vault.read() } catch { return .failed }
        if let existing, !existing.isEmpty { return .alreadyInVault(existing) }
        guard let plaintext, !plaintext.isEmpty else { return .nothingToMove }
        do {
            try vault.write(plaintext)
            return (try vault.read()) == plaintext ? .moved(plaintext) : .failed
        } catch {
            return .failed
        }
    }
}
