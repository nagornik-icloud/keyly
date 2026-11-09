import Foundation
import Security

/// One generic-password item in the user's login keychain.
final class KeychainBlobStore: SecretBlobStore {
    struct KeychainError: Error { let status: OSStatus }

    private let service: String
    private let account: String

    nonisolated init(service: String = AppIdentity.keychainService, account: String) {
        self.service = service
        self.account = account
    }

    private var itemQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() throws -> Data? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func write(_ data: Data) throws {
        let updated = SecItemUpdate(itemQuery as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }
        var item = itemQuery
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Keyly API keys"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }
}
