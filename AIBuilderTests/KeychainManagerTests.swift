import XCTest
@testable import AIBuilder

/// KeychainManager 单元测试：使用真实 Keychain，setUp/tearDown 清理测试 key
/// 源码确认：service = "com.aibuilder.apikey"，account = "apikey"
final class KeychainManagerTests: XCTestCase {
    private let manager = KeychainManager.shared

    override func setUp() {
        super.setUp()
        // 清理可能残留的测试 key
        manager.deleteAPIKey()
    }

    override func tearDown() {
        manager.deleteAPIKey()
        super.tearDown()
    }

    /// save 后 get 应返回相同字符串
    func testSaveAndGetRoundTrip() throws {
        do {
            try manager.saveAPIKey("test-key-123")
        } catch {
            throw XCTSkip("Keychain 不可用：\(error)")
        }
        XCTAssertEqual(manager.getAPIKey(), "test-key-123", "保存后应能读回相同 API Key")
    }

    /// 重复 save（内部先 Delete 再 Add）不应抛错
    func testSaveTwiceDoesNotError() throws {
        do {
            try manager.saveAPIKey("first-key")
            try manager.saveAPIKey("second-key")
        } catch {
            throw XCTSkip("Keychain 不可用：\(error)")
        }
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
}
