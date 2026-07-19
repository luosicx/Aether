import Foundation
import CryptoKit
import Security

/// Task 19 阶段 4: 端到端加密层。
///
/// 使用 CryptoKit `AES.GCM` 算法对向量与元数据加密：
/// - 主密钥（256-bit SymmetricKey）由 Keychain 派生（首次启用时生成并保存到 Keychain）。
/// - 启用后所有写入 VectorStore 与 SwiftData 的内容均经加密。
/// - 关闭后新写入数据明文存储，已加密数据可通过 `decrypt` 解密。
///
/// 安全性：
/// - Keychain 标记 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，仅本机解锁后可用。
/// - nonce 由 CryptoKit 自动生成并附在 sealed box 中。
/// - 默认关闭，用户主动在设置页启用。
final class EncryptionLayer {
    /// Keychain 中保存主密钥的 account key
    static let keychainAccount = "aether.memory.encryption.key"

    /// 单例（App 全局唯一）
    static let shared = EncryptionLayer()

    /// Keychain 管理器（生产用 KeychainManager.shared，测试可注入）
    private let keychain: KeychainManager

    /// 是否已启用加密（默认关闭）
    private(set) var isEnabled: Bool = false

    /// 当前主密钥（启用后加载）
    private var key: SymmetricKey?

    /// 创建 EncryptionLayer 实例
    /// - Parameter keychain: Keychain 管理器，nil 时使用单例
    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    // MARK: - 启用 / 禁用

    /// 启用加密：从 Keychain 加载或生成新主密钥。
    /// - Returns: 是否成功启用（生成或加载密钥成功）
    @discardableResult
    func enable() -> Bool {
        // 1. 尝试加载已存在的密钥
        if let existingKey = loadKeyFromKeychain() {
            self.key = existingKey
            self.isEnabled = true
            return true
        }
        // 2. 生成新密钥（256-bit）
        let newKey = SymmetricKey(size: .bits256)
        // 3. 保存到 Keychain
        do {
            try saveKeyToKeychain(newKey)
            self.key = newKey
            self.isEnabled = true
            return true
        } catch {
            return false
        }
    }

    /// 禁用加密（不清除已加密数据，密钥仍保留在 Keychain）
    func disable() {
        isEnabled = false
        key = nil
    }

    // MARK: - 加密 / 解密

    /// 加密 Data。
    /// - Parameter data: 明文数据
    /// - Returns: 加密后的 sealed box 序列化数据
    /// - Throws: 加密未启用或加密失败
    func encrypt(_ data: Data) throws -> Data {
        guard isEnabled, let key = key else {
            throw EncryptionError.encryptionNotEnabled
        }
        let sealedBox = try AES.GCM.seal(data, using: key)
        // combined() 返回 nonce + ciphertext + tag 的组合
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed("无法生成 combined 数据")
        }
        return combined
    }

    /// 解密 Data。
    /// - Parameter data: 加密数据（combined 格式）
    /// - Returns: 明文数据
    /// - Throws: 解密失败或密钥不可用
    func decrypt(_ data: Data) throws -> Data {
        // 解密允许在禁用状态下进行（用于读取历史加密数据）
        guard let key = key ?? loadKeyFromKeychain() else {
            throw EncryptionError.keyNotAvailable
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// 加密字符串（便捷方法）。
    func encryptString(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed("UTF-8 编码失败")
        }
        return try encrypt(data)
    }

    /// 解密为字符串（便捷方法）。
    func decryptToString(_ data: Data) throws -> String {
        let plaintext = try decrypt(data)
        guard let string = String(data: plaintext, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed("UTF-8 解码失败")
        }
        return string
    }

    /// 加密向量数组（Double 序列化为 JSON 后加密）。
    func encryptEmbedding(_ embedding: [Double]) throws -> Data {
        let data = try JSONEncoder().encode(embedding)
        return try encrypt(data)
    }

    /// 解密向量数组。
    func decryptEmbedding(_ data: Data) throws -> [Double] {
        let plaintext = try decrypt(data)
        return try JSONDecoder().decode([Double].self, from: plaintext)
    }

    // MARK: - Keychain 操作

    /// 从 Keychain 加载主密钥
    private func loadKeyFromKeychain() -> SymmetricKey? {
        guard let data = keychain.readData(key: Self.keychainAccount) else { return nil }
        return SymmetricKey(data: data)
    }

    /// 保存主密钥到 Keychain
    private func saveKeyToKeychain(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        try keychain.save(key: Self.keychainAccount, value: data)
    }

    /// 清除主密钥（用于测试或用户重置）
    func clearKey() {
        keychain.delete(key: Self.keychainAccount)
        key = nil
        isEnabled = false
    }
}

/// Task 19 阶段 4: 加密错误类型。
enum EncryptionError: LocalizedError {
    case encryptionNotEnabled
    case keyNotAvailable
    case encryptionFailed(String)
    case decryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .encryptionNotEnabled:
            return NSLocalizedString("加密未启用", comment: "")
        case .keyNotAvailable:
            return NSLocalizedString("加密密钥不可用", comment: "")
        case .encryptionFailed(let msg):
            return String(format: NSLocalizedString("加密失败: %@", comment: ""), msg)
        case .decryptionFailed(let msg):
            return String(format: NSLocalizedString("解密失败: %@", comment: ""), msg)
        }
    }
}
