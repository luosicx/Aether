import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// ChatMessage.toAPIMessage 单元测试
@MainActor
final class ChatMessageTests: XCTestCase {
    /// 与 ChatMessage.decodedToolCalls 内部 StoredToolCall 字段对齐的 Codable DTO，
    /// 用于构造合法 toolCallData
    private struct StoredToolCallDTO: Codable {
        let id: String
        let type: String
        let name: String
        let arguments: String
    }

    func testToAPIMessagePlainText() {
        let msg = ChatMessage(role: "user", content: "你好")
        let api = msg.toAPIMessage()
        XCTAssertEqual(api.role, "user")
        XCTAssertEqual(api.content, "你好")
        XCTAssertNil(api.images, "纯文本消息 images 应为 nil")
        XCTAssertNil(api.toolCalls)
        XCTAssertNil(api.toolCallId)
        XCTAssertNil(api.toolName)
    }

    func testToAPIMessageWithImageData() {
        let data = Data([0x01, 0x02, 0x03])
        let msg = ChatMessage(role: "user", content: "看图", imageData: data)
        let api = msg.toAPIMessage()
        XCTAssertEqual(api.images?.count, 1, "imageData 应映射为 1 张 base64 图片")
        XCTAssertEqual(api.images?.first, data.base64EncodedString())
    }

    func testToAPIMessageWithAttachedImage() {
        let data = Data([0x04, 0x05, 0x06])
        let msg = ChatMessage(role: "user", content: "看图", attachedImage: data)
        let api = msg.toAPIMessage()
        XCTAssertEqual(api.images?.count, 1, "attachedImage 应映射为 1 张 base64 图片")
        XCTAssertEqual(api.images?.first, data.base64EncodedString())
    }

    func testToAPIMessageWithBothImages() {
        let d1 = Data([0x01, 0x02])
        let d2 = Data([0x03, 0x04])
        let msg = ChatMessage(role: "user", content: "看两张图", imageData: d1, attachedImage: d2)
        let api = msg.toAPIMessage()
        XCTAssertEqual(api.images?.count, 2, "imageData + attachedImage 应合并为 2 张")
        XCTAssertEqual(api.images?[0], d1.base64EncodedString())
        XCTAssertEqual(api.images?[1], d2.base64EncodedString())
    }

    func testToAPIMessageWithToolCalls() throws {
        let calls = [StoredToolCallDTO(
            id: "call_1",
            type: "function",
            name: "calculate",
            arguments: "{\"expression\":\"1+1\"}"
        )]
        let data = try JSONEncoder().encode(calls)
        let msg = ChatMessage(role: "assistant", content: "", toolCallData: data)
        let api = msg.toAPIMessage()
        XCTAssertNotNil(api.toolCalls, "合法 toolCallData 应解码出 toolCalls")
        XCTAssertEqual(api.toolCalls?.count, 1)
        XCTAssertEqual(api.toolCalls?.first?.id, "call_1")
        XCTAssertEqual(api.toolCalls?.first?.type, "function")
        XCTAssertEqual(api.toolCalls?.first?.function.name, "calculate")
        XCTAssertEqual(api.toolCalls?.first?.function.arguments, "{\"expression\":\"1+1\"}")
    }

    func testToAPIMessageToolCallsDecodingFailureReturnsNil() {
        let badData = Data("{not valid json".utf8)
        let msg = ChatMessage(role: "assistant", content: "", toolCallData: badData)
        let api = msg.toAPIMessage()
        XCTAssertNil(api.toolCalls, "非法 JSON 解码失败时 toolCalls 应为 nil")
    }

    func testToAPIMessageToolCallIdAndRolePassthrough() {
        let msg = ChatMessage(
            role: "tool",
            content: "结果",
            toolCallId: "call_42",
            toolName: "calculate"
        )
        let api = msg.toAPIMessage()
        XCTAssertEqual(api.role, "tool")
        XCTAssertEqual(api.toolCallId, "call_42", "toolCallId 应透传到 APIMessage")
        XCTAssertEqual(api.toolName, "calculate", "toolName 应透传到 APIMessage")
    }
}
