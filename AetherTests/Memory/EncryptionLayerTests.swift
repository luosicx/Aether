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

    /// 默认状态：init 自动调用 enable 加载/生成密钥，isEnabled 应为 true（P1-10）
    /// 注：setUp 中已 clearKey，新实例 init 时 Keychain 无密钥，会自动生成新密钥
    func testDefaultEnabledAfterInit() {
        let newLayer = EncryptionLayer()
        XCTAssertTrue(newLayer.isEnabled, "EncryptionLayer 默认应启用（init 自动 enable）")
        newLayer.clearKey()  // 清理新实例生成的密钥，避免污染其他测试
    }

    /// clearKey 后应处于禁用状态（保留以验证 clearKey 语义）
    func testStateAfterClearKey() {
        XCTAssertFalse(layer.isEnabled, "clearKey 后应禁用")
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

    // MARK: - 解码失败场景

    /// decryptToString 在解密成功但明文非合法 UTF-8 时应抛出 decryptionFailed。
    /// 构造合法加密的非 UTF-8 字节序列（Data([0xFF, 0xFE])），加密后调用 decryptToString。
    func testDecryptToStringInvalidUTF8Throws() throws {
        layer.enable()
        // 0xFF, 0xFE 不是合法 UTF-8 字节序列
        let nonUTF8Bytes = Data([0xFF, 0xFE])
        let encrypted = try layer.encrypt(nonUTF8Bytes)

        XCTAssertThrowsError(try layer.decryptToString(encrypted), "非 UTF-8 明文应抛出 decryptionFailed") { error in
            guard case EncryptionError.decryptionFailed = error else {
                return XCTFail("应抛出 decryptionFailed，实际：\(error)")
            }
        }
    }

    // MARK: - Keychain 损坏数据场景

    /// Keychain 中存在非密钥字节数据时，loadKeyFromKeychain 仍返回 SymmetricKey（CryptoKit 不校验大小）。
    /// 验证 enable() 加载已存在的（损坏）数据作为密钥，不生成新密钥覆盖。
    /// 注：CryptoKit 的 SymmetricKey(data:) 接受任意非空数据，不在初始化时校验密钥长度，
    /// 因此 loadKeyFromKeychain 不会因数据"非密钥"而返回 nil —— 实现层未做密钥长度校验。
    func testLoadKeyFromKeychainWithCorruptData() throws {
        // 写入非密钥字节数据（3 字节，非合法 AES-256 密钥长度 32 字节）
        let corruptData = Data([0x00, 0x01, 0x02])
        try KeychainManager.shared.save(key: EncryptionLayer.keychainAccount, value: corruptData)

        // 创建新 EncryptionLayer（setUp 已注入 InMemoryKeychainBackend）
        let newLayer = EncryptionLayer()

        // enable() 应加载已存在的（损坏）密钥，而非生成新密钥
        let result = newLayer.enable()
        XCTAssertTrue(result, "enable 应返回 true（SymmetricKey 接受任意非空数据）")
        XCTAssertTrue(newLayer.isEnabled, "isEnabled 应为 true")

        // Keychain 中应仍为原始损坏数据（未生成新密钥覆盖）
        let storedData = KeychainManager.shared.readData(key: EncryptionLayer.keychainAccount)
        XCTAssertEqual(storedData, corruptData, "应保留原始损坏数据，未生成新密钥")

        // 清理
        newLayer.clearKey()
    }
}
