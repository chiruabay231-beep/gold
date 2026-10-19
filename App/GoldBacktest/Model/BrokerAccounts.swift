import Foundation
import Security

/// An MT5 account the user logs in to on the VPS, kept in a list on this
/// iPhone for quick switching. The password, when saved, is in the Keychain.
struct SavedBrokerAccount: Codable, Hashable, Identifiable {
    var broker: String
    var login: String
    var server: String

    var id: String { "\(login)@\(server)" }

    private static let listKey = "broker.accounts"
    private static let service = "GoldBacktest.mt5"

    static var all: [SavedBrokerAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: listKey),
                  let list = try? JSONDecoder().decode([SavedBrokerAccount].self, from: data) else { return [] }
            return list
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: listKey) }
    }

    static func remember(_ account: SavedBrokerAccount, password: String?) {
        var list = all.filter { $0.id != account.id }
        list.insert(account, at: 0)
        all = list
        if let password { Keychain.save(password, service: service, account: account.id) }
    }

    static func forget(_ account: SavedBrokerAccount) {
        all = all.filter { $0.id != account.id }
        Keychain.delete(service: service, account: account.id)
    }

    var savedPassword: String? { Keychain.read(service: Self.service, account: id) }
}

/// Generic password items, this device only.
enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func save(_ value: String, service: String, account: String) {
        delete(service: service, account: account)
        guard !value.isEmpty else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
