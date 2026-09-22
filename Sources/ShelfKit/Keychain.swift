import Foundation
import Security
import os

/// A generic-password Keychain store, for NAS logins.
///
/// Each app passes its own `service` ("com.vanities.mango.nas", "com.vanities.earmark.nas")
/// rather than it being derived here: a different service can't see the passwords already
/// saved under the old one, so it is the app's to pin and never to change.
public struct Keychain: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else {
                Logger.keychain.error("[keychain] add failed for \(key, privacy: .public): \(added)")
                throw KeychainError.status(added)
            }
        } else if status != errSecSuccess {
            Logger.keychain.error("[keychain] update failed for \(key, privacy: .public): \(status)")
            throw KeychainError.status(status)
        }
        Logger.keychain.info("[keychain] stored credential for \(key, privacy: .public)")
    }

    public func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                Logger.keychain.error("[keychain] read failed for \(key, privacy: .public): \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        Logger.keychain.info("[keychain] deleted credential for \(key, privacy: .public) status=\(status)")
    }

    public enum KeychainError: LocalizedError {
        case status(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .status(let code): "Keychain error \(code)."
            }
        }
    }
}
