import XCTest
@testable import AIBuilder

/// Day 13: FallbackLLMProvider 装饰器单元测试
final class FallbackLLMProviderTests: XCTestCase {

    // MARK: - Stub

    final class StubLLMProvider: LLMProvider {
        var chatContents: [String] = []
        var shouldFail: Bool = false
        var embedResult: [[Float]] = []
        var embedError: Error?

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { cont in
                if !self.shouldFail {
                    for content in self.chatContents {
                        cont.yield(content)
                    }
                }
                cont.finish()
            }
        }

        func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
            AsyncStream { cont in
                if !self.shouldFail {
                    for content in self.chatContents {
                        cont.yield(ParsedChunk(content: content, toolCalls: nil))
                    }
                }
                cont.finish()
            }
        }

        func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            if let err = embedError { throw err }
            return embedResult
        }
    }

    // MARK: - 测试用例

    func testPrimarySuccessNoFallback() async {
        let primary = StubLLMProvider()
        primary.chatContents = ["Hello", " World"]
        let fallback = StubLLMProvider()
        fallback.chatContents = ["Fallback"]

        let provider = FallbackLLMProvider(
            primary: primary, fallback: fallback,
            primaryProvider: .deepseek, fallbackProvider: .qwen
        )

        var collected = ""
        for await content in provider.chat(messages: [], config: .default, apiKey: "key") {
            collected += content
        }

        XCTAssertEqual(collected, "Hello World", "应使用主 provider 的内容")
        XCTAssertEqual(provider.lastUsedProvider, .deepseek, "lastUsedProvider 应为 primary")
        XCTAssertEqual(provider.didFallback, false, "不应触发降级")
    }

    func testPrimaryErrorTriggersFallback() async {
        let primary = StubLLMProvider()
        primary.shouldFail = true  // 模拟主 provider 失败
        let fallback = StubLLMProvider()
        fallback.chatContents = ["Fallback"]

        let provider = FallbackLLMProvider(
            primary: primary, fallback: fallback,
            primaryProvider: .deepseek, fallbackProvider: .qwen
        )

        var collected = ""
        for await content in provider.chat(messages: [], config: .default, apiKey: "key") {
            collected += content
        }

        XCTAssertEqual(collected, "Fallback", "主失败应用 fallback 内容")
        XCTAssertEqual(provider.lastUsedProvider, .qwen, "lastUsedProvider 应为 fallback")
        XCTAssertEqual(provider.didFallback, true, "应触发降级")
    }

    func testBothFailYieldsNothing() async {
        // 主和备用都失败（不 yield 任何内容），最终 collected 为空，lastUsedProvider 为 fallback
        let primary = StubLLMProvider()
        primary.shouldFail = true
        let fallback = StubLLMProvider()
        fallback.shouldFail = true

        let provider = FallbackLLMProvider(
            primary: primary, fallback: fallback,
            primaryProvider: .deepseek, fallbackProvider: .qwen
        )

        var collected = ""
        for await content in provider.chat(messages: [], config: .default, apiKey: "key") {
            collected += content
        }

        XCTAssertEqual(collected, "", "两者都失败时 collected 应为空")
        // 触发了 fallback 路径（虽然 fallback 也没产出），lastUsedProvider 应为 fallback
        XCTAssertEqual(provider.lastUsedProvider, .qwen, "fallback 路径已被触发，lastUsedProvider 应为 fallback")
        XCTAssertEqual(provider.didFallback, true, "应标记触发降级")
    }

    func testEmbedDoesNotFallback() async {
        // embed 路径不降级，primary 抛错直接传出
        let primary = StubLLMProvider()
        primary.embedError = LLMError.apiKeyInvalid
        let fallback = StubLLMProvider()
        fallback.embedResult = [[0.1, 0.2]]

        let provider = FallbackLLMProvider(
            primary: primary, fallback: fallback,
            primaryProvider: .deepseek, fallbackProvider: .qwen
        )

        do {
            _ = try await provider.embed(texts: ["test"], apiKey: "key")
            XCTFail("primary 抛错时应直接传出错误")
        } catch {
            // 验证抛的是 LLMError.apiKeyInvalid
            XCTAssertTrue(error is LLMError, "应抛 LLMError 类型")
        }
        XCTAssertEqual(provider.lastUsedProvider, .deepseek, "embed 路径不降级，lastUsedProvider 应保持 primary")
        XCTAssertEqual(provider.didFallback, false, "embed 不应触发降级")
    }
}
