import XCTest
@testable import Aether

/// Day 13: ModelProvider 枚举单元测试
final class ModelProviderTests: XCTestCase {

    func testDeepseekBaseURL() {
        XCTAssertEqual(ModelProvider.deepseek.baseURL, "https://api.deepseek.com")
    }

    func testQwenBaseURL() {
        XCTAssertEqual(ModelProvider.qwen.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    func testKeychainAccountUnique() {
        let dsAccount = ModelProvider.deepseek.keychainAccount
        let qwenAccount = ModelProvider.qwen.keychainAccount
        XCTAssertNotEqual(dsAccount, qwenAccount, "两个 provider 的 keychainAccount 必须不同")
        XCTAssertEqual(dsAccount, "apikey-deepseek")
        XCTAssertEqual(qwenAccount, "apikey-qwen")
    }

    func testDefaultModelsNonEmpty() {
        for provider in ModelProvider.allCases {
            XCTAssertFalse(provider.defaultChatModel.isEmpty, "\(provider.displayName) defaultChatModel 不应为空")
            XCTAssertFalse(provider.defaultReasonerModel.isEmpty, "\(provider.displayName) defaultReasonerModel 不应为空")
            XCTAssertFalse(provider.defaultEmbeddingModel.isEmpty, "\(provider.displayName) defaultEmbeddingModel 不应为空")
        }
    }
}
