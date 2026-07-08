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
        case .keychainError(let msg): return "钥匙串错误: \(msg)"
        case .apiKeyMissing: return "API Key 未设置"
        case .networkError(let msg): return "网络错误: \(msg)"
        }
    }
}

/// Keychain 单例管理 API Key 的增删改查
final class KeychainManager {
    /// 单例
    static let shared = KeychainManager()
    /// Keychain service 标识 "com.aibuilder.apikey"
    private let service = "com.aibuilder.apikey"

    /// 私有初始化，外部只能用 shared
    private init() {}

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
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.keychainError("保存失败: \(status)")
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
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
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
        SecItemDelete(query as CFDictionary)
    }
}
