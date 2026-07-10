import XCTest
@testable import Aether

/// APIConfig 常量与 ChatConfig.default 单元测试
final class APIConfigTests: XCTestCase {
    func testAPIConfigConstantsNotEmpty() {
        XCTAssertFalse(APIConfig.deepseekBaseURL.isEmpty, "deepseekBaseURL 不应为空")
        XCTAssertFalse(APIConfig.chatEndpoint.isEmpty, "chatEndpoint 不应为空")
        XCTAssertFalse(APIConfig.embeddingEndpoint.isEmpty, "embeddingEndpoint 不应为空")
        XCTAssertFalse(APIConfig.defaultModel.isEmpty, "defaultModel 不应为空")
        XCTAssertFalse(APIConfig.embeddingModel.isEmpty, "embeddingModel 不应为空")
    }

    func testChatConfigDefault() {
        let def = ChatConfig.default
        XCTAssertEqual(def.model, "deepseek-chat", "ChatConfig.default.model 应为 deepseek-chat")
        XCTAssertEqual(def.model, APIConfig.defaultModel, "ChatConfig.default.model 应等于 APIConfig.defaultModel")
        XCTAssertFalse(def.systemPrompt.isEmpty, "ChatConfig.default.systemPrompt 不应为空")
        XCTAssertEqual(def.maxTokens, 2048, "ChatConfig.default.maxTokens 应为 2048")
        XCTAssertEqual(def.temperature, 0.7, accuracy: 0.001, "ChatConfig.default.temperature 应为 0.7")
    }
}
