import Testing
import Foundation
@testable import KeylyLogic

/// API keys move from plain-text UserDefaults into Keychain. The plain copy may be erased
/// only after the vault provably holds the same bytes; any failure keeps it, so the user
/// never loses keys that the provider will not show again.
@Suite("Secret migration to Keychain")
struct SecretMigrationTests {

    final class MemoryVault: SecretBlobStore {
        var blob: Data?
        var failWrite = false
        var failRead = false
        var corruptOnWrite = false
        func read() throws -> Data? {
            if failRead { throw VaultError() }
            return blob
        }
        func write(_ data: Data) throws {
            if failWrite { throw VaultError() }
            blob = corruptOnWrite ? Data("x".utf8) : data
        }
        struct VaultError: Error {}
    }

    let plain = Data(#"{"schemaVersion":1,"items":[]}"#.utf8)

    @Test("Plain keys move into an empty vault")
    func moves() {
        let vault = MemoryVault()
        #expect(SecretMigration.moveIfNeeded(vault: vault, plaintext: plain) == .moved(plain))
        #expect(vault.blob == plain)
    }

    @Test("Nothing in plain text → nothing to move")
    func nothing() {
        #expect(SecretMigration.moveIfNeeded(vault: MemoryVault(), plaintext: nil) == .nothingToMove)
        #expect(SecretMigration.moveIfNeeded(vault: MemoryVault(), plaintext: Data()) == .nothingToMove)
    }

    @Test("Vault already has keys → it wins, plain copy is stale")
    func alreadyInVault() {
        let vault = MemoryVault()
        vault.blob = Data("vault".utf8)
        #expect(SecretMigration.moveIfNeeded(vault: vault, plaintext: plain) == .alreadyInVault(Data("vault".utf8)))
        #expect(vault.blob == Data("vault".utf8))
    }

    @Test("Write fails → failed, plain copy must be kept")
    func writeFails() {
        let vault = MemoryVault()
        vault.failWrite = true
        #expect(SecretMigration.moveIfNeeded(vault: vault, plaintext: plain) == .failed)
    }

    @Test("Read-back differs → failed")
    func readBackDiffers() {
        let vault = MemoryVault()
        vault.corruptOnWrite = true
        #expect(SecretMigration.moveIfNeeded(vault: vault, plaintext: plain) == .failed)
    }

    @Test("Vault unreadable (denied/locked) → failed, never overwritten")
    func unreadable() {
        let vault = MemoryVault()
        vault.failRead = true
        vault.blob = Data("vault".utf8)
        #expect(SecretMigration.moveIfNeeded(vault: vault, plaintext: plain) == .failed)
        #expect(vault.blob == Data("vault".utf8))
    }

    @Test("Plain copy may be erased only after moved or alreadyInVault")
    func erasePolicy() {
        #expect(SecretMigration.Outcome.moved(plain).plaintextMayBeErased)
        #expect(SecretMigration.Outcome.alreadyInVault(plain).plaintextMayBeErased)
        #expect(!SecretMigration.Outcome.failed.plaintextMayBeErased)
        #expect(!SecretMigration.Outcome.nothingToMove.plaintextMayBeErased)
    }
}
