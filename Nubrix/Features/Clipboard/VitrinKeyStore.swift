import CryptoKit
import Foundation
import Security

enum VitrinKeyLoad {
    case ready(SymmetricKey)
    case missing
    case invalid
    case locked(OSStatus)
}

protocol VitrinKeyProviding: Sendable {
    var label: String { get }
    func load() -> VitrinKeyLoad
    func create(_ key: SymmetricKey) -> OSStatus
    func delete() -> OSStatus
}

struct KeychainVitrinKeyStore: VitrinKeyProviding {
    static let service = "dev.nubrix.vitrin"
    static let account = "history-key.v1"
    static let itemLabel = "Nubrix Vitrin history key"

    let label = "login keychain"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    func load() -> VitrinKeyLoad {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess else { return .locked(status) }
        guard let data = result as? Data, data.count == 32 else { return .invalid }
        return .ready(SymmetricKey(data: data))
    }

    func create(_ key: SymmetricKey) -> OSStatus {
        var item = query
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrLabel as String] = Self.itemLabel
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        return SecItemAdd(item as CFDictionary, nil)
    }

    func delete() -> OSStatus {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}

#if DEBUG
struct FileVitrinKeyStore: VitrinKeyProviding {
    let url: URL
    let label = "Debug key file"

    init(url: URL) {
        self.url = url
    }

    func load() -> VitrinKeyLoad {
        do {
            let data = try Data(contentsOf: url)
            guard data.count == 32 else { return .invalid }
            return .ready(SymmetricKey(data: data))
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return .missing }
            return .locked(errSecIO)
        }
    }

    func create(_ key: SymmetricKey) -> OSStatus {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return errSecDuplicateItem }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try key.withUnsafeBytes { Data($0) }.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return errSecSuccess
        } catch {
            return errSecIO
        }
    }

    func delete() -> OSStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return errSecSuccess }
        do {
            try fm.removeItem(at: url)
            return errSecSuccess
        } catch {
            return fm.fileExists(atPath: url.path) ? errSecIO : errSecSuccess
        }
    }
}
#endif

enum VitrinKeyStores {
    static func makeDefault(directory: URL) -> VitrinKeyProviding {
        #if DEBUG
        FileVitrinKeyStore(url: directory.appendingPathComponent("key"))
        #else
        KeychainVitrinKeyStore()
        #endif
    }
}
