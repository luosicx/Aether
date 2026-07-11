import XCTest
@testable import Aether

/// KeychainManager 单元测试：使用真实 Keychain，setUp/tearDown 清理测试 key
/// 源码确认：service = "com.aether.apikey"，account = "apikey"
final class KeychainManagerTests: XCTestCase {
    private let manager = KeychainManager.shared

    override func setUp() {
        super.setUp()
        // 注入内存 Keychain 后端，避免依赖真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        // 清理可能残留的测试 key（deepseek + qwen + onDevice）
        manager.deleteAPIKey(for: .deepseek)
        manager.deleteAPIKey(for: .qwen)
        manager.deleteAPIKey(for: .onDevice)
    }

    override func tearDown() {
        manager.deleteAPIKey(for: .deepseek)
        manager.deleteAPIKey(for: .qwen)
        manager.deleteAPIKey(for: .onDevice)
        KeychainManager.shared.backend = SystemKeychainBackend()
        super.tearDown()
    }

    /// save 后 get 应返回相同字符串
    func testSaveAndGetRoundTrip() throws {
        try manager.saveAPIKey("test-key-123")
        XCTAssertEqual(manager.getAPIKey(), "test-key-123", "保存后应能读回相同 API Key")
    }

    /// 重复 save（内部先 Delete 再 Add）不应抛错
    func testSaveTwiceDoesNotError() throws {
        try manager.saveAPIKey("first-key")
        try manager.saveAPIKey("second-key")
        XCTAssertEqual(manager.getAPIKey(), "second-key", "重复 save 后应保留最后一次的值")
    }

    /// delete 不存在的 key 也应是幂等的（不抛错、不崩溃）
    func testDeleteIsIdempotent() {
        // setUp 已 delete 一次；此处对不存在的 key 再 delete 两次
        manager.deleteAPIKey()
        manager.deleteAPIKey()
        XCTAssertNil(manager.getAPIKey(), "删除后应返回 nil")
    }

    /// get 从未保存的 key 返回 nil
    func testGetNonExistentKeyReturnsNil() {
        // setUp 已清理，确保无残留
        XCTAssertNil(manager.getAPIKey(), "未保存的 key 应返回 nil")
    }

    // MARK: - key 更新

    /// 同一 provider 多次 save 应更新为最新值（key 更新）
    func testUpdateKeyForSameProvider() throws {
        try manager.saveAPIKey("v1")
        XCTAssertEqual(manager.getAPIKey(), "v1", "首次保存后应为 v1")

        try manager.saveAPIKey("v2")
        XCTAssertEqual(manager.getAPIKey(), "v2", "更新后应为 v2")

        try manager.saveAPIKey("v3-final")
        XCTAssertEqual(manager.getAPIKey(), "v3-final", "再次更新后应为 v3-final")
    }

    /// 多 provider 各自更新 key 应互不影响
    func testUpdateKeyPerProviderIndependently() throws {
        try manager.saveAPIKey("ds-v1", for: .deepseek)
        try manager.saveAPIKey("qwen-v1", for: .qwen)

        // 更新 deepseek
        try manager.saveAPIKey("ds-v2", for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "ds-v2", "deepseek 更新后应为 ds-v2")
        XCTAssertEqual(manager.getAPIKey(for: .qwen), "qwen-v1", "qwen 不应受 deepseek 更新影响")

        // 更新 qwen
        try manager.saveAPIKey("qwen-v2", for: .qwen)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "ds-v2", "deepseek 不应受 qwen 更新影响")
        XCTAssertEqual(manager.getAPIKey(for: .qwen), "qwen-v2", "qwen 更新后应为 qwen-v2")
    }

    // MARK: - 重复 key 处理

    /// 重复保存相同 key 值应幂等（不报错，值保持一致）
    func testSaveSameKeyMultipleTimesIdempotent() throws {
        try manager.saveAPIKey("same-key", for: .deepseek)
        try manager.saveAPIKey("same-key", for: .deepseek)
        try manager.saveAPIKey("same-key", for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "same-key",
                       "重复保存相同值应幂等，最终值一致")
    }

    /// 保存后删除再保存应正常工作
    func testSaveDeleteSaveCycle() throws {
        try manager.saveAPIKey("first", for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "first")

        manager.deleteAPIKey(for: .deepseek)
        XCTAssertNil(manager.getAPIKey(for: .deepseek))

        try manager.saveAPIKey("second", for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "second",
                       "删除后重新保存应正常工作")
    }

    // MARK: - 多 provider key 并发读写

    /// 并发写入不同 provider 的 key 后应能各自正确读取
    func testConcurrentWriteMultipleProviders() async throws {
        // 使用 async let 并发写入三个 provider
        async let save1: Void = Task.detached(priority: .userInitiated) {
            try? KeychainManager.shared.saveAPIKey("ds-concurrent", for: .deepseek)
        }.value
        async let save2: Void = Task.detached(priority: .userInitiated) {
            try? KeychainManager.shared.saveAPIKey("qwen-concurrent", for: .qwen)
        }.value
        async let save3: Void = Task.detached(priority: .userInitiated) {
            try? KeychainManager.shared.saveAPIKey("ondevice-concurrent", for: .onDevice)
        }.value
        _ = await (save1, save2, save3)

        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "ds-concurrent",
                       "并发写入后 deepseek key 应正确读取")
        XCTAssertEqual(manager.getAPIKey(for: .qwen), "qwen-concurrent",
                       "并发写入后 qwen key 应正确读取")
        XCTAssertEqual(manager.getAPIKey(for: .onDevice), "ondevice-concurrent",
                       "并发写入后 onDevice key 应正确读取")
    }

    /// 并发读取多 provider key 应返回正确值
    func testConcurrentReadMultipleProviders() async throws {
        try manager.saveAPIKey("ds-read", for: .deepseek)
        try manager.saveAPIKey("qwen-read", for: .qwen)

        async let dsResult = Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey(for: .deepseek)
        }.value
        async let qwenResult = Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey(for: .qwen)
        }.value

        let (ds, qwen) = await (dsResult, qwenResult)

        XCTAssertEqual(ds, "ds-read", "并发读取 deepseek key 应返回正确值")
        XCTAssertEqual(qwen, "qwen-read", "并发读取 qwen key 应返回正确值")
    }

    /// 并发写入同一 provider 应最终保留其中一个值（不崩溃，最终状态确定）
    func testConcurrentWriteSameProvider() async throws {
        let keys = ["key-a", "key-b", "key-c", "key-d"]
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    try? KeychainManager.shared.saveAPIKey(key, for: .deepseek)
                }
            }
        }

        let finalValue = manager.getAPIKey(for: .deepseek)
        XCTAssertTrue(keys.contains(finalValue ?? ""),
                       "并发写入同一 provider 后最终值应为其中之一，实际：\(finalValue ?? "nil")")
    }

    // MARK: - 边界值

    /// 保存空字符串应能正常工作
    func testSaveEmptyString() throws {
        try manager.saveAPIKey("", for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), "", "空字符串应能被保存和读取")
    }

    /// 保存含 Unicode 字符的 key 应能正常工作
    func testSaveUnicodeKey() throws {
        let unicodeKey = "密钥-🔑-test-中文"
        try manager.saveAPIKey(unicodeKey, for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), unicodeKey,
                       "Unicode 字符的 key 应能被正确保存和读取")
    }

    /// 保存长字符串应能正常工作
    func testSaveLongKey() throws {
        let longKey = String(repeating: "a", count: 1000)
        try manager.saveAPIKey(longKey, for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), longKey,
                       "长字符串 key 应能被正确保存和读取")
    }

    /// 保存含特殊字符的 key 应能正常工作
    func testSaveKeyWithSpecialCharacters() throws {
        let specialKey = "key-with-spaces and\ttabs\nnewlines\"quotes\""
        try manager.saveAPIKey(specialKey, for: .deepseek)
        XCTAssertEqual(manager.getAPIKey(for: .deepseek), specialKey,
                       "含特殊字符的 key 应能被正确保存和读取")
    }

    // MARK: - onDevice provider

    /// onDevice provider 也应支持 save/get/delete（虽无实际 API Key）
    func testOnDeviceProviderSaveGetDelete() throws {
        try manager.saveAPIKey("ondevice-test", for: .onDevice)
        XCTAssertEqual(manager.getAPIKey(for: .onDevice), "ondevice-test",
                       "onDevice provider 应支持 save/get")

        manager.deleteAPIKey(for: .onDevice)
        XCTAssertNil(manager.getAPIKey(for: .onDevice),
                     "onDevice provider 删除后应返回 nil")
    }

    // MARK: - AppError

    /// AppError.apiKeyMissing 应提供非空描述
    func testAppErrorApiKeyMissingDescription() {
        let error = AppError.apiKeyMissing
        XCTAssertNotNil(error.errorDescription, "apiKeyMissing 的 errorDescription 不应为 nil")
        XCTAssertTrue(error.errorDescription?.contains("API Key") == true,
                      "apiKeyMissing 描述应含「API Key」")
    }

    /// AppError.keychainError 应携带底层消息
    func testAppErrorKeychainErrorDescription() {
        let error = AppError.keychainError("底层错误详情")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("底层错误详情") == true,
                      "keychainError 描述应含底层消息")
    }

    /// AppError.networkError 应携带底层消息
    func testAppErrorNetworkErrorDescription() {
        let error = AppError.networkError("网络中断")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("网络中断") == true,
                      "networkError 描述应含底层消息")
    }

    // MARK: - Keychain 迁移逻辑测试

    /// 辅助：用 InMemoryKeychainBackend 预填充旧 service 数据
    private func prefillLegacyData(backend: InMemoryKeychainBackend, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aibuilder.apikey",
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        _ = backend.secItemAdd(query as CFDictionary)
    }

    /// migrateLegacyKeychainIfNeeded：旧 service 有数据时迁移到新 service
    func testMigrateLegacyKeychainWithData() {
        let backend = InMemoryKeychainBackend()
        let legacyData = "old-api-key-123".data(using: .utf8)!
        prefillLegacyData(backend: backend, account: ModelProvider.deepseek.keychainAccount, data: legacyData)

        KeychainManager.shared.backend = backend
        // 确保新 service 无旧数据
        KeychainManager.shared.deleteAPIKey(for: .deepseek)

        // 手动触发迁移
        KeychainManager.shared.migrateLegacyKeychainIfNeeded()

        // 验证迁移后新 service 有数据
        let migrated = KeychainManager.shared.getAPIKey(for: .deepseek)
        XCTAssertEqual(migrated, "old-api-key-123", "迁移后应能从新 service 读取旧数据")
    }

    /// migrateLegacyKeychainIfNeeded：旧 service 无数据时正常跳过
    func testMigrateLegacyNoDataSkipsGracefully() {
        let backend = InMemoryKeychainBackend()
        KeychainManager.shared.backend = backend
        KeychainManager.shared.deleteAPIKey(for: .deepseek)

        KeychainManager.shared.migrateLegacyKeychainIfNeeded()

        XCTAssertNil(KeychainManager.shared.getAPIKey(for: .deepseek), "无迁移数据时新 service 应为空")
        XCTAssertNil(KeychainManager.shared.getAPIKey(for: .qwen), "qwen 也应为空")
    }

    // MARK: - InMemoryKeychainBackend 边界测试

    /// InMemoryKeychainBackend 的 secItemCopyMatching 对不存在的 key 返回 errSecItemNotFound
    func testInMemoryBackendReturnsNotFoundForMissingKey() {
        let backend = InMemoryKeychainBackend()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test-service",
            kSecAttrAccount as String: "test-account",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = backend.secItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecItemNotFound, "不存在的 key 应返回 errSecItemNotFound")
    }

    /// InMemoryKeychainBackend 的 secItemDelete 对不存在的 key 也返回 success
    func testInMemoryBackendDeleteIsIdempotent() {
        let backend = InMemoryKeychainBackend()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test-service",
            kSecAttrAccount as String: "test-account"
        ]
        // 删除不存在的 key
        let status = backend.secItemDelete(query as CFDictionary)
        XCTAssertEqual(status, errSecSuccess, "删除不存在的 key 应返回 success")
    }

    /// InMemoryKeychainBackend 的 secItemAdd 正确写入并返回 success
    func testInMemoryBackendAddSucceeds() {
        let backend = InMemoryKeychainBackend()
        let data = "test-value".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test-service",
            kSecAttrAccount as String: "test-account",
            kSecValueData as String: data
        ]
        let status = backend.secItemAdd(query as CFDictionary)
        XCTAssertEqual(status, errSecSuccess, "写入应返回 success")

        // 验证可读取
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test-service",
            kSecAttrAccount as String: "test-account",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let readStatus = backend.secItemCopyMatching(readQuery as CFDictionary, &result)
        XCTAssertEqual(readStatus, errSecSuccess, "读取应返回 success")
        XCTAssertEqual(result as? Data, data, "读取的数据应与写入一致")
    }

    /// InMemoryKeychainBackend 先删后加（幂等保存）
    func testInMemoryBackendDeleteThenAddIsIdempotent() {
        let backend = InMemoryKeychainBackend()
        let data1 = "value1".data(using: .utf8)!
        let data2 = "value2".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test-service",
            kSecAttrAccount as String: "test-account",
            kSecValueData as String: data1
        ]

        // 第一次写入
        _ = backend.secItemAdd(query as CFDictionary)

        // 修改 data 后先删后加
        var deleteQuery = query
        deleteQuery.removeValue(forKey: kSecValueData as String)
        _ = backend.secItemDelete(deleteQuery as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data2
        _ = backend.secItemAdd(addQuery as CFDictionary)

        // 验证最终值为 data2
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test-service",
            kSecAttrAccount as String: "test-account",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        _ = backend.secItemCopyMatching(readQuery as CFDictionary, &result)
        XCTAssertEqual(result as? Data, data2, "先删后加后应为 data2")
    }
}
