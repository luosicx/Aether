import XCTest
@testable import AetherSDK
import AetherFoundation
import AetherServices

/// AetherClient+API.swift 中 internal API 的覆盖率补强测试。
///
/// 专门测试 AetherClientAPI 命名空间下的静态方法以及带 tools 分支的 chat / stream 路径，
/// 以提升 PR #26 的 new_coverage。
final class AetherClientAPIInternalTests: XCTestCase {

    // MARK: - cacheKey

    func testCacheKeyJoinsUserMessagesWithSeparator() {
        let messages = [
            AetherMessage.system("sys"),
            AetherMessage.user("hello"),
            AetherMessage.assistant("hi"),
            AetherMessage.user("world")
        ]
        let key = AetherClientAPI.cacheKey(for: messages)
        XCTAssertEqual(key, "hello\n---\nworld")
    }

    func testCacheKeyEmptyWhenNoUserMessages() {
        let messages = [
            AetherMessage.system("sys"),
            AetherMessage.assistant("hi")
        ]
        let key = AetherClientAPI.cacheKey(for: messages)
        XCTAssertTrue(key.isEmpty)
    }

    func testCacheKeySingleUserMessage() {
        let key = AetherClientAPI.cacheKey(for: [.user("solo")])
        XCTAssertEqual(key, "solo")
    }

    // MARK: - parseArguments

    func testParseArgumentsValidJSON() {
        let dict = AetherClientAPI.parseArguments(#"{"name":"test","count":42}"#)
        XCTAssertEqual(dict["name"] as? String, "test")
        XCTAssertEqual(dict["count"] as? Int, 42)
    }

    func testParseArgumentsInvalidJSONReturnsEmptyDict() {
        let dict = AetherClientAPI.parseArguments("not a json")
        XCTAssertTrue(dict.isEmpty)
    }

    func testParseArgumentsEmptyStringReturnsEmptyDict() {
        let dict = AetherClientAPI.parseArguments("")
        XCTAssertTrue(dict.isEmpty)
    }

    func testParseArgumentsNonObjectJSONReturnsEmptyDict() {
        let dict = AetherClientAPI.parseArguments("[1,2,3]")
        XCTAssertTrue(dict.isEmpty)
    }

    // MARK: - wrapError

    func testWrapErrorPassesThroughAetherError() {
        let original = AetherError.rateLimited(retryAfter: 30)
        let wrapped = AetherClientAPI.wrapError(original)
        if case .rateLimited(let retryAfter) = wrapped {
            XCTAssertEqual(retryAfter, 30)
        } else {
            XCTFail("期望 rateLimited，实际：\(wrapped)")
        }
    }

    func testWrapErrorConvertsLLMError() {
        let llmError = LLMError.apiError(code: 401, message: "unauthorized")
        let wrapped = AetherClientAPI.wrapError(llmError)
        if case .authFailed = wrapped {
            // 预期：401 → authFailed
        } else {
            XCTFail("期望 authFailed，实际：\(wrapped)")
        }
    }

    func testWrapErrorConvertsNSURLErrorToNetworkUnreachable() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let wrapped = AetherClientAPI.wrapError(urlError)
        if case .networkUnreachable = wrapped {
            // 预期：NSURLErrorDomain → networkUnreachable
        } else {
            XCTFail("期望 networkUnreachable，实际：\(wrapped)")
        }
    }

    func testWrapErrorWrapsUnknownNSErrorAsProviderError() {
        let nsError = NSError(domain: "CustomDomain", code: 999, userInfo: [NSLocalizedDescriptionKey: "custom failure"])
        let wrapped = AetherClientAPI.wrapError(nsError)
        if case .providerError(let code, let message) = wrapped {
            XCTAssertEqual(code, 999)
            XCTAssertTrue(message.contains("custom failure"))
        } else {
            XCTFail("期望 providerError，实际：\(wrapped)")
        }
    }

    // MARK: - convertMessages

    func testConvertMessagesPreservesUserRole() {
        let messages = [AetherMessage.user("hi")]
        let api = AetherClientAPI.convertMessages(messages)
        XCTAssertEqual(api.count, 1)
        XCTAssertEqual(api[0].role, "user")
        XCTAssertEqual(api[0].content, "hi")
    }

    func testConvertMessagesWithToolCalls() {
        let msg = AetherMessage(
            role: .assistant,
            content: "calling tool",
            toolCalls: [AetherToolCall(id: "c1", name: "echo", arguments: "{}")]
        )
        let api = AetherClientAPI.convertMessages([msg])
        XCTAssertEqual(api[0].toolCalls?.count, 1)
        XCTAssertEqual(api[0].toolCalls?.first?.id, "c1")
        XCTAssertEqual(api[0].toolCalls?.first?.function.name, "echo")
    }

    func testConvertMessagesWithToolRole() {
        let msg = AetherMessage.tool(name: "echo", callId: "c1", content: "result")
        let api = AetherClientAPI.convertMessages([msg])
        XCTAssertEqual(api[0].role, "tool")
        XCTAssertEqual(api[0].toolName, "echo")
        XCTAssertEqual(api[0].toolCallId, "c1")
    }

    func testConvertMessagesWithImages() {
        let msg = AetherMessage(role: .user, content: "see image", images: ["base64data"])
        let api = AetherClientAPI.convertMessages([msg])
        XCTAssertEqual(api[0].images, ["base64data"])
    }

    // MARK: - convertChatConfig

    func testConvertChatConfigUsesProviderDefaultModel() {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let chatConfig = AetherClientAPI.convertChatConfig(config)
        XCTAssertFalse(chatConfig.model.isEmpty)
        XCTAssertEqual(chatConfig.maxTokens, 2048)
        XCTAssertEqual(chatConfig.temperature, 0.7)
        XCTAssertEqual(chatConfig.systemPrompt, "")
    }

    // MARK: - convertToolDefs

    func testConvertToolDefsWithRegisteredTools() throws {
        let registry = AetherToolRegistry()
        let tool = EchoTool()
        registry.register(tool: tool)
        let defs = AetherClientAPI.convertToolDefs([tool], registry: registry)
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(defs[0].type, "function")
        XCTAssertEqual(defs[0].function.name, "echo")
    }

    func testConvertToolDefsEmptyWhenNoToolsRegistered() {
        let registry = AetherToolRegistry()
        let defs = AetherClientAPI.convertToolDefs([], registry: registry)
        XCTAssertTrue(defs.isEmpty)
    }

    // MARK: - chat 带 tools 分支

    func testChatWithToolsReturnsAccumulatedResponse() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["with", " ", "tools"]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        let tool = EchoTool()
        let response = try await client.chat(messages: [.user("hi")], tools: [tool])
        XCTAssertEqual(response, "with tools")
    }

    func testChatWithToolsRegistersAndUnregisters() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["ok"]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        let tool = EchoTool()
        _ = try await client.chat(messages: [.user("hi")], tools: [tool])
        // chat 结束后临时工具应被反注册
        XCTAssertEqual(client.registeredToolCount, 0)
    }

    // MARK: - stream 带 tools 分支

    func testStreamWithToolsYieldsChunks() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["t1", "t2"]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        let tool = EchoTool()
        var chunks: [AetherChunk] = []
        for await chunk in client.stream(messages: [.user("hi")], tools: [tool]) {
            chunks.append(chunk)
        }
        // 2 内容 chunk + 1 final
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].content, "t1")
        XCTAssertEqual(chunks[1].content, "t2")
        XCTAssertTrue(chunks[2].isFinal)
    }

    // MARK: - embed 使用 LLMProvider 分支

    func testEmbedUsesLLMProviderWhenNoEmbeddingProviderInjected() async throws {
        let mock = MockLLMProvider()
        mock.embedResponses = [[0.5, 0.6]]
        let client = try AetherClient(
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            provider: mock
        )
        let vectors = try await client.embed(texts: ["hi"])
        XCTAssertEqual(vectors, [[0.5, 0.6]])
    }

    // MARK: - retrieve 错误包装

    func testRetrieveWrapsNonAetherError() async throws {
        let mock = MockLLMProvider()
        let ragProvider = ThrowingRAGProvider(error: LLMError.apiError(code: 500, message: "rag fail"))
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-test",
            rag: RAGConfig(knowledgeBaseID: "kb-1", topK: 5)
        )
        let client = try AetherClient(config: config, provider: mock, ragProvider: ragProvider)
        do {
            _ = try await client.retrieve(query: "test")
            XCTFail("应抛出 ragRetrievalFailed")
        } catch let error as AetherError {
            if case .ragRetrievalFailed = error {
                // 预期：非 AetherError 被包装为 ragRetrievalFailed
            } else {
                XCTFail("期望 ragRetrievalFailed，实际：\(error)")
            }
        }
    }

    // MARK: - chatSingleAttempt 带 tools 分支

    func testChatSingleAttemptWithoutTools() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["chunk1", "chunk2"]
        let registry = AetherToolRegistry()
        let result = try await AetherClientAPI.chatSingleAttempt(
            provider: mock,
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            messages: [.user("hi")],
            tools: [],
            toolRegistry: registry
        )
        XCTAssertEqual(result, "chunk1chunk2")
    }

    func testChatSingleAttemptWithRegisteredToolsButNoToolCalls() async throws {
        let mock = MockLLMProvider()
        mock.chatResponses = ["hello"]
        let registry = AetherToolRegistry()
        let tool = EchoTool()
        registry.register(tool: tool)
        let result = try await AetherClientAPI.chatSingleAttempt(
            provider: mock,
            config: AetherConfig(provider: .deepSeek, apiKey: "sk-test"),
            messages: [.user("hi")],
            tools: [tool],
            toolRegistry: registry
        )
        XCTAssertEqual(result, "hello")
    }
}

// MARK: - Throwing RAGProvider

final class ThrowingRAGProvider: AetherRAGProvider, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func retrieve(query: String, topK: Int, knowledgeBaseID: String) async throws -> [AetherDocument] {
        throw error
    }
}
