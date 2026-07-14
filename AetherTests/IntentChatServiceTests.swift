import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Day 18 Task 11: IntentChatService 单元测试
/// 通过注入 LLMProvider 与 API Key 闭包验证 ask(query:) 的错误处理与流式累积逻辑，
/// 避免依赖真实 Keychain 与网络。
final class IntentChatServiceTests: XCTestCase {

    /// 可配置 chunk 序列的 LLMProvider 桩，用于验证流式累积
    final class StubStreamingProvider: LLMProvider {
        /// chat 流式返回的 chunk 序列
        var chunks: [String] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { cont in
                for chunk in self.chunks {
                    cont.yield(chunk)
                }
                cont.finish()
            }
        }

        func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
            AsyncStream { $0.finish() }
        }

        func embed(texts: [String], apiKey: String) async throws -> [[Float]] { [] }
    }

    // 1. 无 API Key 时 ask 应抛 LLMError.apiKeyMissing，不应实际调用 LLM
    func testAskReturnsErrorWhenAPIKeyMissing() async throws {
        let provider = StubStreamingProvider()
        provider.chunks = ["不应该被调用"]
        let service = IntentChatService(
            llmProvider: provider,
            apiKeyProvider: { nil }
        )

        do {
            _ = try await service.ask(query: "你好")
            XCTFail("无 API Key 时 ask 应抛 LLMError.apiKeyMissing")
        } catch LLMError.apiKeyMissing {
            // 预期错误：API Key 缺失
        } catch {
            XCTFail("应抛 LLMError.apiKeyMissing，实际抛出: \(error)")
        }
    }

    // 2. 注入 mock provider 后 ask 返回非空字符串
    func testAskReturnsNonEmptyStringWithMockProvider() async throws {
        let provider = StubStreamingProvider()
        provider.chunks = ["Hello"]
        let service = IntentChatService(
            llmProvider: provider,
            apiKeyProvider: { "test-key" }
        )

        let reply = try await service.ask(query: "你好")
        XCTAssertFalse(reply.isEmpty, "ask 返回的回复不应为空")
        XCTAssertEqual(reply, "Hello")
    }

    // 3. 多个 chunk 被正确累积拼接为完整文本
    func testAskAccumulatesStreamChunks() async throws {
        let provider = StubStreamingProvider()
        provider.chunks = ["Hello", " ", "World"]
        let service = IntentChatService(
            llmProvider: provider,
            apiKeyProvider: { "test-key" }
        )

        let reply = try await service.ask(query: "你好")
        XCTAssertEqual(reply, "Hello World", "多个 chunk 应被正确累积拼接")
    }
}
