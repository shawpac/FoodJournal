import Foundation
import Security

enum KeychainStore {
    private static let service = "com.foodjournal.app"

    /// Identifies which key to read/write. Different `account` values keep multiple keys cleanly separated in Keychain.
    enum Key: String {
        case anthropic = "anthropic_api_key"
        case usda = "usda_api_key"
    }

    @discardableResult
    static func save(_ value: String, for key: Key) -> OSStatus {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        print("KeychainStore.save (\(key.rawValue)) status:", status, "value length:", value.count)
        return status
    }

    static func load(_ key: Key) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        print("KeychainStore.load (\(key.rawValue)) status:", status)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    // MARK: - Backward-compatible shims
    // These let existing call sites keep working unchanged. Prefer `save(_:for:)` and `load(_:)` for new code.

    @discardableResult
    static func saveAPIKey(_ key: String) -> OSStatus {
        save(key, for: .anthropic)
    }

    static func loadAPIKey() -> String {
        load(.anthropic)
    }
}
