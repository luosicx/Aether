import XCTest
@testable import AetherSDK
import AetherFoundation
import AetherServices

/// Task 24 阶段 1: AetherClient 骨架测试
final class AetherClientTests: XCTestCase {

    // MARK: - 初始化

    func testInitWithValidConfig() throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let client = try AetherClient(config: config)
        XCTAssertEqual(client.config.provider, .deepSeek)
        XCTAssertEqual(client.config.apiKey, "sk-test")
    }

    func testInitWithInvalidConfigThrows() {
        let config = AetherConfig(provider: .deepSeek, apiKey: "")
        XCTAssertThrowsError(try AetherClient(config: config)) { error in
            if case .invalidConfig(let reason) = error as? AetherError {
                XCTAssertTrue(reason.contains("apiKey"))
            } else {
                XCTFail("期望 invalidConfig 错误，实际：\(error)")
            }
        }
    }

    func testInitWithInjectedProvider() throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let mock = MockLLMProvider()
        let client = try AetherClient(config: config, provider: mock)
        XCTAssertNotNil(client)
    }

    func testInitOnDeviceWithoutProviderThrows() {
        let config = AetherConfig(provider: .onDevice, apiKey: "")
        XCTAssertThrowsError(try AetherClient(config: config)) { error in
            if case .invalidConfig(let reason) = error as? AetherError {
                XCTAssertTrue(reason.contains("onDevice"))
            } else {
                XCTFail("期望 invalidConfig 错误，实际：\(error)")
            }
        }
    }

    // MARK: - 工具注册 API

    func testRegisterTool() throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let client = try AetherClient(config: config, provider: MockLLMProvider())
        let tool = EchoTool()
        client.register(tool: tool)
        XCTAssertEqual(client.registeredToolCount, 1)
        XCTAssertTrue(client.registeredToolNames.contains("echo"))
    }

    func testUnregisterTool() throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let client = try AetherClient(config: config, provider: MockLLMProvider())
        client.register(tool: EchoTool())
        XCTAssertEqual(client.registeredToolCount, 1)
        client.unregister(tool: "echo")
        XCTAssertEqual(client.registeredToolCount, 0)
    }

    func testSetToolPermission() throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let client = try AetherClient(config: config, provider: MockLLMProvider())
        client.register(tool: EchoTool())
        XCTAssertEqual(client.toolPermission(for: "echo"), .alwaysAllow)
        client.setToolPermission(name: "echo", .requireApproval)
        XCTAssertEqual(client.toolPermission(for: "echo"), .requireApproval)
        client.setToolPermission(name: "echo", .deny)
        XCTAssertEqual(client.toolPermission(for: "echo"), .deny)
    }

    // MARK: - Sendable

    func testClientIsSendable() throws {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let client = try AetherClient(config: config, provider: MockLLMProvider())
        let closure: @Sendable () -> AetherProvider = { client.config.provider }
        XCTAssertEqual(closure(), .deepSeek)
    }

    // MARK: - AetherMessage 便捷构造

    func testAetherMessageSystemConvenience() {
        let msg = AetherMessage.system("hello")
        XCTAssertEqual(msg.role, .system)
        XCTAssertEqual(msg.content, "hello")
        XCTAssertNil(msg.images)
        XCTAssertNil(msg.toolCallId)
        XCTAssertNil(msg.toolName)
        XCTAssertNil(msg.toolCalls)
    }

    func testAetherMessageUserConvenience() {
        let msg = AetherMessage.user("question")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "question")
    }

    func testAetherMessageAssistantConvenience() {
        let msg = AetherMessage.assistant("answer")
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.content, "answer")
    }

    func testAetherMessageToolConvenience() {
        let msg = AetherMessage.tool(name: "calc", callId: "call-1", content: "42")
        XCTAssertEqual(msg.role, .tool)
        XCTAssertEqual(msg.content, "42")
        XCTAssertEqual(msg.toolName, "calc")
        XCTAssertEqual(msg.toolCallId, "call-1")
    }

    func testAetherMessageInitWithImages() {
        let msg = AetherMessage(role: .user, content: "multi", images: ["base64-img"])
        XCTAssertEqual(msg.images, ["base64-img"])
    }

    func testAetherMessageRoleRawValues() {
        XCTAssertEqual(AetherMessage.Role.system.rawValue, "system")
        XCTAssertEqual(AetherMessage.Role.user.rawValue, "user")
        XCTAssertEqual(AetherMessage.Role.assistant.rawValue, "assistant")
        XCTAssertEqual(AetherMessage.Role.tool.rawValue, "tool")
    }

    // MARK: - AetherToolCall

    func testAetherToolCallDefaultType() {
        let call = AetherToolCall(id: "call-1", name: "echo", arguments: "{}")
        XCTAssertEqual(call.type, "function")
        XCTAssertEqual(call.id, "call-1")
        XCTAssertEqual(call.name, "echo")
        XCTAssertEqual(call.arguments, "{}")
    }

    func testAetherToolCallCustomType() {
        let call = AetherToolCall(id: "call-2", type: "custom", name: "search", arguments: "{\"q\":\"a\"}")
        XCTAssertEqual(call.type, "custom")
    }

    // MARK: - AetherChunk 便捷构造

    func testAetherChunkTextConvenience() {
        let chunk = AetherChunk.text("hello")
        XCTAssertEqual(chunk.content, "hello")
        XCTAssertNil(chunk.toolCalls)
        XCTAssertFalse(chunk.isFinal)
    }

    func testAetherChunkToolCallsConvenience() {
        let calls = [AetherToolCall(id: "c1", name: "echo", arguments: "{}")]
        let chunk = AetherChunk.toolCalls(calls)
        XCTAssertNil(chunk.content)
        XCTAssertEqual(chunk.toolCalls?.count, 1)
        XCTAssertFalse(chunk.isFinal)
    }

    func testAetherChunkFinalConvenience() {
        let chunk = AetherChunk.final()
        XCTAssertNil(chunk.content)
        XCTAssertNil(chunk.toolCalls)
        XCTAssertTrue(chunk.isFinal)
    }

    func testAetherChunkDefaultInit() {
        let chunk = AetherChunk()
        XCTAssertNil(chunk.content)
        XCTAssertNil(chunk.toolCalls)
        XCTAssertFalse(chunk.isFinal)
    }

    // MARK: - AetherDocument

    func testAetherDocumentInitWithDefaultMetadata() {
        let doc = AetherDocument(content: "c", source: "s", score: 0.9)
        XCTAssertEqual(doc.content, "c")
        XCTAssertEqual(doc.source, "s")
        XCTAssertEqual(doc.score, 0.9, accuracy: 0.001)
        XCTAssertEqual(doc.metadata, [:])
    }

    func testAetherDocumentInitWithMetadata() {
        let doc = AetherDocument(content: "c", source: "s", score: 0.5, metadata: ["page": "1"])
        XCTAssertEqual(doc.metadata["page"], "1")
    }
}

// MARK: - Mock LLMProvider

/// 测试用 LLMProvider mock
final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    /// chat 流：每次 yield 一个字符
    var chatResponses: [String] = ["Hello, world!"]
    var embedResponses: [[Float]] = [[0.1, 0.2, 0.3]]
    var shouldThrowEmbed = false

    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            for response in self.chatResponses {
                continuation.yield(response)
            }
            continuation.finish()
        }
    }

    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            for response in self.chatResponses {
                continuation.yield(ParsedChunk(content: response, toolCalls: nil))
            }
            continuation.finish()
        }
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        if shouldThrowEmbed {
            throw LLMError.apiError(code: 401, message: "unauthorized")
        }
        return embedResponses
    }
}

// MARK: - Echo Tool（测试用 AetherTool 实现）

struct EchoTool: AetherTool {
    let definition = AetherToolDefinition(
        name: "echo",
        description: "回显输入参数",
        parameters: [
            "type": "object",
            "properties": [
                "text": ["type": "string", "description": "要回显的文本"]
            ],
            "required": ["text"]
        ]
    )

    func execute(arguments: [String: Any]) async throws -> String {
        if let text = arguments["text"] as? String {
            return "echo: \(text)"
        }
        return "echo: \(arguments)"
    }
}
