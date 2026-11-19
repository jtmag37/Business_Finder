import Foundation
import Security

/// Minimal Keychain wrapper for small sensitive values (e.g. the cached
/// purchase entitlement). Items are device-only and available after first
/// unlock so the game can read them offline in the background.
struct KeychainStore {
    let service: String

    init(service: String = AppConfig.bundleID + ".secure") {
        self.service = service
    }

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            attributes.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func bool(for account: String) -> Bool {
        (try? data(for: account)).flatMap { $0 }.map { $0 == Data([1]) } ?? false
    }

    func setBool(_ value: Bool, for account: String) {
        try? set(Data([value ? 1 : 0]), for: account)
    }
}
