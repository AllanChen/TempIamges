import Foundation
import Security

guard let key = ProcessInfo.processInfo.environment["FREEIMAGEKEY"]?
    .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
    fputs("FREEIMAGEKEY is not set.\n", stderr)
    exit(1)
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.glance.app.freeimage",
    kSecAttrAccount as String: "api-key"
]
let value = Data(key.utf8)
let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
if status == errSecItemNotFound {
    var item = query
    item[kSecValueData as String] = value
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(item as CFDictionary, nil)
    guard added == errSecSuccess else {
        fputs("Could not save Freeimage key to Keychain (\(added)).\n", stderr)
        exit(1)
    }
} else if status != errSecSuccess {
    fputs("Could not update Freeimage key in Keychain (\(status)).\n", stderr)
    exit(1)
}

print("Freeimage key saved to the macOS Keychain.")
