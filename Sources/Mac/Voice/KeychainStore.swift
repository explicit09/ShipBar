import Foundation
import Security

enum KeychainStore {
    // Store only the OpenAI API key here. Realtime sessions use this directly
    // from the macOS app, so avoid logging or reflecting the value anywhere.
    private static let service = "com.tadies.ShipBar"
    private static let openAIKeyAccount = "openai-api-key"

    static func openAIKey() -> String? {
        Self.read(account: Self.openAIKeyAccount)
    }

    static func setOpenAIKey(_ key: String?) {
        Self.write(key, account: Self.openAIKeyAccount)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func write(_ value: String?, account: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = value.data(using: .utf8) else { return }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
