#if canImport(Security)
import Foundation
import Security

/// Stores the token pair in the Keychain, readable only while the device is
/// unlocked and never synced or migrated to another device.
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account = "tokens"

    public init(service: String = "app.lifeos.ios.tokens") {
        self.service = service
    }

    public func load() -> TokenPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }

    public func save(_ tokens: TokenPair?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
