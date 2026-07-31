import XCTest
@testable import Aether

/// v3.0: Apple Intelligence Provider 测试
final class AppleIntelligenceProviderTests: XCTestCase {

    // MARK: - Provider 基本属性

    func testProviderName() {
        XCTAssertEqual(AppleIntelligenceProvider.providerName, "Apple Intelligence")
    }

    func testInitWithDefaults() {
        let provider = AppleIntelligenceProvider()
        XCTAssertEqual(provider.modelIdentifier, "apple-intelligence-default")
        // enabled 由平台可用性决定（CI 环境 FoundationModels 不可用，应为 false）
        // 不断言具体值，因为不同环境可能不同
    }

    func testInitWithCustomModel() {
        let provider = AppleIntelligenceProvider(modelIdentifier: "apple-3b-v1", enabled: false)
        XCTAssertEqual(provider.modelIdentifier, "apple-3b-v1")
        XCTAssertFalse(provider.enabled)
    }

    func testInitWithEnabledTrue() {
        let provider = AppleIntelligenceProvider(enabled: true)
        XCTAssertTrue(provider.enabled)
    }

    func testInitWithEnabledFalse() {
        let provider = AppleIntelligenceProvider(enabled: false)
        XCTAssertFalse(provider.enabled)
    }

    // MARK: - 平台可用性

    func testIsAvailableReturnsBool() {
        // 仅验证返回 Bool 类型，不断言具体值
        let _ = AppleIntelligenceProvider.isAvailable
    }

    // MARK: - chat 流式接口

    func testChatReturnsStream() async {
        let provider = AppleIntelligenceProvider(enabled: false)
        let messages = [APIMessage(role: "user", content: "你好")]
        let config = ChatConfig.default

        var chunks: [String] = []
        for await chunk in provider.chat(messages: messages, config: config, apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertFalse(chunks.isEmpty, "占位模式应返回至少一个 chunk")
        XCTAssertTrue(chunks.first?.contains("占位") == true, "占位模式应包含'占位'提示")
    }

    func testChatWithToolsReturnsStream() async {
        let provider = AppleIntelligenceProvider(enabled: false)
        let messages = [APIMessage(role: "user", content: "调用工具")]
        let config = ChatConfig.default
        let tools: [ToolDef] = []

        var chunks: [ParsedChunk] = []
        for await chunk in provider.chat(messages: messages, config: config, tools: tools, apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertFalse(chunks.isEmpty, "应返回至少一个 chunk")
        XCTAssertNotNil(chunks.first?.content, "占位 chunk 应有 content")
    }

    func testChatDisabledModeContent() async {
        let provider = AppleIntelligenceProvider(enabled: false)
        let messages = [APIMessage(role: "user", content: "测试")]
        let config = ChatConfig.default

        var content = ""
        for await chunk in provider.chat(messages: messages, config: config, apiKey: "") {
            content += chunk
        }
        XCTAssertTrue(content.contains("占位"), "禁用模式应返回占位提示")
    }

    // MARK: - embed 嵌入

    func testEmbedReturnsVectors() async throws {
        let provider = AppleIntelligenceProvider(enabled: false)
        let texts = ["你好", "世界"]
        let vectors = try await provider.embed(texts: texts, apiKey: "")
        XCTAssertEqual(vectors.count, 2, "应返回 2 个向量")
        XCTAssertEqual(vectors[0].count, 384, "占位向量应为 384 维")
    }

    func testEmbedEmptyTexts() async throws {
        let provider = AppleIntelligenceProvider(enabled: false)
        let vectors = try await provider.embed(texts: [], apiKey: "")
        XCTAssertTrue(vectors.isEmpty, "空输入应返回空数组")
    }

    // MARK: - prompt 构建

    func testChatWithMultipleMessages() async {
        let provider = AppleIntelligenceProvider(enabled: false)
        let messages = [
            APIMessage(role: "system", content: "你是助手"),
            APIMessage(role: "user", content: "问题1"),
            APIMessage(role: "assistant", content: "回答1"),
            APIMessage(role: "user", content: "问题2")
        ]
        let config = ChatConfig.default

        var content = ""
        for await chunk in provider.chat(messages: messages, config: config, apiKey: "") {
            content += chunk
        }
        XCTAssertFalse(content.isEmpty)
    }

    func testChatWithCustomConfig() async {
        let provider = AppleIntelligenceProvider(enabled: false)
        let messages = [APIMessage(role: "user", content: "测试")]
        let config = ChatConfig(model: "custom-model", systemPrompt: "自定义", maxTokens: 100, temperature: 0.5)

        var content = ""
        for await chunk in provider.chat(messages: messages, config: config, apiKey: "") {
            content += chunk
        }
        XCTAssertFalse(content.isEmpty)
    }

    // MARK: - Sendable 一致性

    func testProviderIsSendable() {
        // 编译期验证 Sendable（若不满足则编译失败）
        let provider = AppleIntelligenceProvider()
        let _ = provider as LLMProvider
    }
}
