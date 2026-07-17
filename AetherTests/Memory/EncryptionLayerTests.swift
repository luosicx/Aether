import XCTest
@testable import Aether

/// Task 19 阶段 4: EncryptionLayer 单元测试。
///
/// 覆盖：启用/禁用、加密/解密 Data、加密/解密字符串、加密/解密向量数组、
/// 密钥持久化（Keychain）、错误场景。
final class EncryptionLayerTests: XCTestCase {
    private var layer: EncryptionLayer!

    override func setUpWithError() throws {
        // 隔离 Keychain：使用内存后端
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        layer = EncryptionLayer()
        layer.clearKey()
    }

    override func tearDownWithError() throws {
        layer?.disable()
        layer?.clearKey()
        layer = nil
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    // MARK: - 启用 / 禁用

    /// 默认状态应为禁用
    func testDefaultDisabled() {
        XCTAssertFalse(layer.isEnabled, "EncryptionLayer 默认应禁用")
    }

    /// enable() 应成功并设置 isEnabled=true
    func testEnableSucceeds() {
        let result = layer.enable()
        XCTAssertTrue(result, "enable 应返回 true")
        XCTAssertTrue(layer.isEnabled, "isEnabled 应为 true")
    }

    /// disable() 应设置 isEnabled=false（但不清除密钥）
    func testDisableKeepsKey() {
        layer.enable()
        layer.disable()
        XCTAssertFalse(layer.isEnabled)
        // 再次 enable 应仍能成功（密钥保留在 Keychain）
        let result = layer.enable()
        XCTAssertTrue(result, "再次 enable 应成功（密钥保留）")
    }

    /// 重复 enable() 应幂等
    func testEnableIdempotent() {
        XCTAssertTrue(layer.enable())
        XCTAssertTrue(layer.enable(), "重复 enable 应幂等成功")
    }

    /// clearKey() 应清除密钥并禁用
    func testClearKey() {
        layer.enable()
        layer.clearKey()
        XCTAssertFalse(layer.isEnabled, "clearKey 后应禁用")
    }

    // MARK: - Data 加密 / 解密

    /// 加密后的数据应不同于明文
    func testEncryptProducesDifferentData() throws {
        layer.enable()
        let plaintext = "Hello, Aether!".data(using: .utf8)!
        let encrypted = try layer.encrypt(plaintext)
        XCTAssertNotEqual(encrypted, plaintext, "加密数据应不同于明文")
    }

    /// 解密应还原原始数据
    func testDecryptRestoresOriginalData() throws {
        layer.enable()
        let plaintext = "记忆内容测试".data(using: .utf8)!
        let encrypted = try layer.encrypt(plaintext)
        let decrypted = try layer.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext, "解密应还原原始数据")
    }

    /// 禁用状态下 encrypt 应抛出 encryptionNotEnabled
    func testEncryptFailsWhenDisabled() {
        XCTAssertThrowsError(try layer.encrypt(Data())) { error in
            guard case EncryptionError.encryptionNotEnabled = error else {
                return XCTFail("应抛出 encryptionNotEnabled，实际：\(error)")
            }
        }
    }

    /// 禁用状态下 decrypt 应仍可解密（用于读取历史加密数据）
    func testDecryptWorksWhenDisabledButKeyAvailable() throws {
        layer.enable()
        let plaintext = "测试".data(using: .utf8)!
        let encrypted = try layer.encrypt(plaintext)
        layer.disable()
        // 禁用后仍能解密（key 仍保留在 Keychain）
        let decrypted = try layer.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext, "禁用后应仍能解密历史数据")
    }

    /// 无密钥时 decrypt 应抛出 keyNotAvailable
    func testDecryptFailsWithoutKey() {
        // clearKey 后无密钥
        layer.clearKey()
        XCTAssertThrowsError(try layer.decrypt(Data())) { error in
            guard case EncryptionError.keyNotAvailable = error else {
                return XCTFail("应抛出 keyNotAvailable，实际：\(error)")
            }
        }
    }

    // MARK: - 字符串加密

    /// 加密/解密字符串应还原原始内容
    func testEncryptDecryptString() throws {
        layer.enable()
        let original = "用户偏好：喜欢简洁回答"
        let encrypted = try layer.encryptString(original)
        let decrypted = try layer.decryptToString(encrypted)
        XCTAssertEqual(decrypted, original, "字符串加密/解密应还原")
    }

    // MARK: - 向量加密

    /// 加密/解密向量数组应还原原始向量
    func testEncryptDecryptEmbedding() throws {
        layer.enable()
        let original: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let encrypted = try layer.encryptEmbedding(original)
        let decrypted = try layer.decryptEmbedding(encrypted)
        XCTAssertEqual(decrypted.count, original.count, "向量维度应一致")
        for (i, value) in original.enumerated() {
            XCTAssertEqual(decrypted[i], value, accuracy: 0.0001, "向量第 \(i) 维应一致")
        }
    }

    /// 空向量加密应正常工作
    func testEncryptEmptyEmbedding() throws {
        layer.enable()
        let original: [Double] = []
        let encrypted = try layer.encryptEmbedding(original)
        let decrypted = try layer.decryptEmbedding(encrypted)
        XCTAssertTrue(decrypted.isEmpty, "空向量解密应仍为空")
    }

    // MARK: - 密钥持久化

    /// 新实例应能加载已存在的密钥
    func testKeyPersistsAcrossInstances() throws {
        layer.enable()
        let original = "持久化测试"
        let encrypted = try layer.encryptString(original)

        // 创建新实例，应能加载同一密钥
        let newLayer = EncryptionLayer()
        XCTAssertTrue(newLayer.enable(), "新实例 enable 应成功（加载已存密钥）")
        let decrypted = try newLayer.decryptToString(encrypted)
        XCTAssertEqual(decrypted, original, "新实例应能解密旧实例加密的数据")
    }

    // MARK: - 错误场景

    /// 损坏的密文应抛出错误
    func testCorruptedCiphertextFails() throws {
        layer.enable()
        let plaintext = "测试".data(using: .utf8)!
        var encrypted = try layer.encrypt(plaintext)
        // 篡改数据
        encrypted[0] ^= 0xFF
        XCTAssertThrowsError(try layer.decrypt(encrypted), "损坏的密文应抛出错误")
    }

    /// 长度不足的密文应抛出错误
    func testTooShortCiphertextFails() {
        layer.enable()
        let tooShort = Data([0x01, 0x02])
        XCTAssertThrowsError(try layer.decrypt(tooShort), "过短的密文应抛出错误")
    }
}
