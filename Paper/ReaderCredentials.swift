import Foundation
import Security

struct ReaderCredentials {
    var service: String = "com.aayush.paper.reader"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "reader-api-token"]
    }
    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else { throw CredentialError.invalidToken }
        return token
    }
    func save(_ token: String) throws {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CredentialError.invalidToken }
        let values: [String: Any] = [
            kSecValueData as String: Data(cleaned.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // Update in place so a failed replacement cannot remove a working credential.
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
    @discardableResult func consumeProvisionedToken(at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let token = try String(contentsOf: url, encoding: .utf8)
        try save(token)
        try FileManager.default.removeItem(at: url)
        return true
    }
}

private enum CredentialError: LocalizedError {
    case invalidToken
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidToken: return "Enter a valid Reader access token."
        case .keychain: return "Your Reader token could not be accessed securely. Please try again."
        }
    }
}
