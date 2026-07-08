import XCTest
@testable import AIBuilder

/// Day 13: KeychainManager 多 provider API Key 隔离测试
final class KeychainManagerMultiProviderTests: XCTestCase {

    override func tearDown() {
        // 清理两个 provider 的 key，避免污染其他测试
        KeychainManager.shared.deleteAPIKey(for: .deepseek)
        KeychainManager.shared.deleteAPIKey(for: .qwen)
        super.tearDown()
    }

    func testSaveAndGetPerProvider() throws {
        // save 不同 key 给两个 provider，分别 get 验证隔离
        do {
            try KeychainManager.shared.saveAPIKey("ds-key", for: .deepseek)
            try KeychainManager.shared.saveAPIKey("qwen-key", for: .qwen)
        } catch {
            throw XCTSkip("Keychain 不可用：\(error)")
        }

        XCTAssertEqual(KeychainManager.shared.getAPIKey(for: .deepseek), "ds-key", "deepseek key 应隔离读取")
        XCTAssertEqual(KeychainManager.shared.getAPIKey(for: .qwen), "qwen-key", "qwen key 应隔离读取")
    }

    func testDeleteOnlyAffectsOneProvider() throws {
        do {
            try KeychainManager.shared.saveAPIKey("ds-key", for: .deepseek)
            try KeychainManager.shared.saveAPIKey("qwen-key", for: .qwen)
        } catch {
            throw XCTSkip("Keychain 不可用：\(error)")
        }

        // 删 deepseek 不应影响 qwen
        KeychainManager.shared.deleteAPIKey(for: .deepseek)
        XCTAssertNil(KeychainManager.shared.getAPIKey(for: .deepseek), "deepseek 应被删除")
        XCTAssertEqual(KeychainManager.shared.getAPIKey(for: .qwen), "qwen-key", "qwen 不应受影响")
    }

    func testLegacyAPIKeyMethodsUseDeepseek() throws {
        // 旧 getAPIKey/saveAPIKey/deleteAPIKey 等价于 provider: .deepseek
        do {
            try KeychainManager.shared.saveAPIKey("legacy-key")
        } catch {
            throw XCTSkip("Keychain 不可用：\(error)")
        }

        XCTAssertEqual(KeychainManager.shared.getAPIKey(), "legacy-key", "旧 getAPIKey 应返回 legacy-key")
        XCTAssertEqual(KeychainManager.shared.getAPIKey(for: .deepseek), "legacy-key", "旧 saveAPIKey 应写入 deepseek account")

        KeychainManager.shared.deleteAPIKey()
        XCTAssertNil(KeychainManager.shared.getAPIKey(for: .deepseek), "旧 deleteAPIKey 应删除 deepseek account")
    }
}
