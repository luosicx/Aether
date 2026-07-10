import XCTest
@testable import Aether

/// Conversation / UserPreference / DocumentChunk / ChatChunk 模型默认值与解码测试
@MainActor
final class ConversationModelTests: XCTestCase {
    func testConversationDefaults() {
        let conv = Conversation()
        XCTAssertEqual(conv.title, "新对话", "Conversation 默认 title 应为「新对话」")
        XCTAssertFalse(conv.isPinned, "Conversation 默认 isPinned 应为 false")
        XCTAssertFalse(conv.systemPrompt.isEmpty, "Conversation 默认 systemPrompt 不应为空")
        XCTAssertNotNil(conv.createdAt, "Conversation 默认 createdAt 不应为 nil")
        XCTAssertEqual(conv.messages.count, 0, "Conversation 默认 messages 应为空数组")
    }

    func testUserPreferenceDefaults() {
        let pref = UserPreference()
        XCTAssertEqual(pref.preferredTone, "默认", "UserPreference 默认 preferredTone 应为「默认」")
        XCTAssertEqual(pref.preferredTools, [], "UserPreference 默认 preferredTools 应为空数组")
        XCTAssertEqual(pref.customFact, "", "UserPreference 默认 customFact 应为空字符串")
    }

    func testDocumentChunkDefaults() {
        let chunk = DocumentChunk(content: "文本片段")
        XCTAssertEqual(chunk.embedding, [], "DocumentChunk 默认 embedding 应为空数组")
        XCTAssertEqual(chunk.chunkIndex, 0, "DocumentChunk 默认 chunkIndex 应为 0")
        XCTAssertEqual(chunk.source, "", "DocumentChunk 默认 source 应为空字符串")
        XCTAssertEqual(chunk.content, "文本片段")
    }

    func testChatChunkDecodingWithContent() throws {
        let jsonString = """
        {"id":"chatcmpl-1","choices":[{"delta":{"content":"你好"},"finish_reason":null}]}
        """
        let data = jsonString.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)
        XCTAssertEqual(chunk.id, "chatcmpl-1")
        XCTAssertEqual(chunk.choices?.count, 1)
        XCTAssertEqual(chunk.choices?.first?.delta?.content, "你好")
        XCTAssertNil(chunk.choices?.first?.delta?.tool_calls)
        XCTAssertNil(chunk.usage)
    }

    func testChatChunkDecodingWithToolCalls() throws {
        let jsonString = """
        {"id":"chatcmpl-2","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"calculate","arguments":"1+1"}}]},"finish_reason":null}]}
        """
        let data = jsonString.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)
        XCTAssertEqual(chunk.choices?.first?.delta?.tool_calls?.count, 1)
        let toolCall = chunk.choices?.first?.delta?.tool_calls?.first
        XCTAssertEqual(toolCall?.id, "call_1")
        XCTAssertEqual(toolCall?.type, "function")
        XCTAssertEqual(toolCall?.function?.name, "calculate")
        XCTAssertEqual(toolCall?.function?.arguments, "1+1")
    }

    func testChatChunkDecodingEmptyChoices() throws {
        let jsonString = """
        {"id":"chatcmpl-3","choices":[],"usage":null}
        """
        let data = jsonString.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)
        XCTAssertEqual(chunk.id, "chatcmpl-3")
        XCTAssertEqual(chunk.choices?.count, 0, "空 choices 数组应解码为 0 长度")
        XCTAssertNil(chunk.usage)
    }
}
