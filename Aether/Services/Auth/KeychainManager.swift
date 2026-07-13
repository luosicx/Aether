import Foundation
import Security

/// 应用错误类型，LocalizedError 协议提供用户友好描述
enum AppError: LocalizedError {
    /// Keychain 操作失败
    case keychainError(String)
    /// API Key 未设置
    case apiKeyMissing
    /// 网络错误
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .keychainError(let msg): return String(format: NSLocalizedString("钥匙串错误: %@", comment: ""), msg)
        case .apiKeyMissing: return NSLocalizedString("API Key 未设置", comment: "")
        case .networkError(let msg): return String(format: NSLocalizedString("网络错误: %@", comment: ""), msg)
        }
    }
}

/// Keychain 底层存储后端协议（便于测试注入）
protocol KeychainBackend {
    func secItemAdd(_ query: CFDictionary) -> OSStatus
    func secItemDelete(_ query: CFDictionary) -> OSStatus
    func secItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
}

/// 真实系统 Keychain 后端
struct SystemKeychainBackend: KeychainBackend {
    func secItemAdd(_ query: CFDictionary) -> OSStatus { SecItemAdd(query, nil) }
    func secItemDelete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
    func secItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus {
        SecItemCopyMatching(query, result)
    }
}

/// 内存 Keychain 后端（测试用，不依赖真实 Keychain）
final class InMemoryKeychainBackend: KeychainBackend {
    private var storage: [String: Data] = [:]

    private func key(for query: CFDictionary) -> String? {
        // 从 query dict 提取 service + account 作为存储 key
        guard let dict = query as? [String: Any] else { return nil }
        let service = dict[kSecAttrService as String] as? String ?? ""
        let account = dict[kSecAttrAccount as String] as? String ?? ""
        return "\(service):\(account)"
    }

    func secItemAdd(_ query: CFDictionary) -> OSStatus {
        guard let key = key(for: query) else { return errSecParam }
        guard let dict = query as? [String: Any] else { return errSecParam }
        storage[key] = dict[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func secItemDelete(_ query: CFDictionary) -> OSStatus {
        guard let key = key(for: query) else { return errSecParam }
        storage.removeValue(forKey: key)
        return errSecSuccess
    }

    func secItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus {
        guard let key = key(for: query) else { return errSecParam }
        if let data = storage[key] {
            result.pointee = data as CFTypeRef
            return errSecSuccess
        }
        return errSecItemNotFound
    }
}

/// Keychain 单例管理 API Key 的增删改查
final class KeychainManager {
    /// 单例
    static let shared = KeychainManager()
    /// Keychain service 标识 "com.aether.apikey"
    private let service = "com.aether.apikey"
    /// 旧版 Keychain service（用于迁移）
    private let legacyService = "com.aibuilder.apikey"
    /// 底层存储后端（生产用 SystemKeychainBackend，测试可注入 InMemoryKeychainBackend）
    internal var backend: KeychainBackend = SystemKeychainBackend()
    /// 通用敏感数据 Keychain service
    private let secretsService = "com.aether.secrets"

    /// 私有初始化，外部只能用 shared
    private init() {
        migrateLegacyKeychainIfNeeded()
    }

    // MARK: - 通用字符串/数据存取

    /// 通用：将字符串保存到 Keychain（account = key，service = secretsService）。
    /// 先删后加保证幂等，失败抛出 keychainError。
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        try save(key: key, value: data)
    }

    /// 通用：将 Data 保存到 Keychain（account = key，service = secretsService）。
    /// 先删后加保证幂等，失败抛出 keychainError。
    func save(key: String, value: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = backend.secItemDelete(query as CFDictionary)
        let status = backend.secItemAdd(query as CFDictionary)
        guard status == errSecSuccess else {
            throw AppError.keychainError(String(format: NSLocalizedString("保存失败: %@", comment: ""), String(status)))
        }
    }

    /// 通用：从 Keychain 读取字符串。无记录返回 nil。
    func read(key: String) -> String? {
        guard let data = readData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 通用：从 Keychain 读取原始 Data。无记录返回 nil。
    func readData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = backend.secItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// 通用：从 Keychain 删除指定 key。幂等，无记录不报错。
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: key
        ]
        _ = backend.secItemDelete(query as CFDictionary)
    }

    /// 迁移旧 Keychain service 到新 service（com.aibuilder.apikey → com.aether.apikey）。
    /// 遍历所有 provider account，若旧 service 下存在数据则迁移到新 service 并删除旧条目。
    internal func migrateLegacyKeychainIfNeeded() {
        for provider in ModelProvider.allCases {
            let account = provider.keychainAccount
            // 查询旧 service 下的数据
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: CFTypeRef?
            let status = backend.secItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { continue }
            // 保存到新 service（先删后加，幂等）
            let saveQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
            _ = backend.secItemDelete(saveQuery as CFDictionary)
            let saveStatus = backend.secItemAdd(saveQuery as CFDictionary)
            guard saveStatus == errSecSuccess else { continue }
            // 删除旧条目
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: account
            ]
            _ = backend.secItemDelete(deleteQuery as CFDictionary)
        }
    }

    // MARK: - 旧 API（向后兼容）：等价于 provider: .deepseek

    /// 保存 API Key（旧 API，等价于 provider: .deepseek）。
    func saveAPIKey(_ key: String) throws {
        try saveAPIKey(key, for: .deepseek)
    }

    /// 读取 API Key（旧 API，等价于 provider: .deepseek）。无记录返回 nil。
    func getAPIKey() -> String? {
        getAPIKey(for: .deepseek)
    }

    /// 删除 API Key（旧 API，等价于 provider: .deepseek）。幂等，无记录不报错。
    func deleteAPIKey() {
        deleteAPIKey(for: .deepseek)
    }

    // MARK: - Day 13: 多 provider 命名空间 API

    /// Day 13: 按 provider 命名空间保存 API Key（account = provider.keychainAccount）。
    /// 为何先 SecItemDelete 再 SecItemAdd：幂等保存，避免重复 key 报 errSecDuplicateItem。失败抛 keychainError。
    func saveAPIKey(_ key: String, for provider: ModelProvider) throws {
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecValueData as String: data
        ]
        // 先删后加：幂等保存，避免重复 key 报 errSecDuplicateItem
        _ = backend.secItemDelete(query as CFDictionary)
        let status = backend.secItemAdd(query as CFDictionary)
        guard status == errSecSuccess else {
            throw AppError.keychainError(String(format: NSLocalizedString("保存失败: %@", comment: ""), String(status)))
        }
    }

    /// Day 13: 按 provider 命名空间读取 API Key。无记录返回 nil。
    func getAPIKey(for provider: ModelProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = backend.secItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Day 13: 按 provider 命名空间删除 API Key。幂等，无记录不报错。
    func deleteAPIKey(for provider: ModelProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount
        ]
        _ = backend.secItemDelete(query as CFDictionary)
    }
}
