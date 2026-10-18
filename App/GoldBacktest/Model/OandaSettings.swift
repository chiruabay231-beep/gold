import Foundation
import Security
import BacktestKit

/// OANDA environment (UserDefaults) and access token (Keychain, this device only).
enum OandaSettings {
    private static let environmentKey = "oanda.environment"
    private static let service = "GoldBacktest.oanda"
    private static let account = "token"

    static var environment: OandaClient.Environment {
        get { UserDefaults.standard.string(forKey: environmentKey).flatMap(OandaClient.Environment.init) ?? .practice }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: environmentKey) }
    }

    static var hasToken: Bool { token != nil }

    static var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    static func saveToken(_ token: String) {
        deleteToken()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// A client with the saved settings, or nil when no token is saved.
    static func client() -> OandaClient? {
        token.map { OandaClient(environment: environment, token: $0) }
    }
}
