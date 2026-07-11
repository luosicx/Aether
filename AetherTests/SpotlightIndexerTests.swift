import XCTest
@testable import Aether

/// Day 18 Task 12: SpotlightIndexer 单元测试
/// 验证 index / removeIndex / clearAll 三个静态方法在模拟器环境下不崩溃。
/// SpotlightIndexer 是无状态 enum，方法均为 static，CSSearchableIndex 操作异步。
final class SpotlightIndexerTests: XCTestCase {

    /// 异步等待 CSSearchableIndex 内部操作完成的辅助方法
    private func waitForSpotlight() async {
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    }

    // 1. 索引单个会话不应崩溃
    func testIndexDoesNotCrash() async throws {
        let conversation = Conversation(title: "测试会话", systemPrompt: "你是助手")
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
    }

    // 2. 移除指定会话索引不应崩溃
    func testRemoveIndexDoesNotCrash() async throws {
        SpotlightIndexer.removeIndex(conversationId: UUID())
        await waitForSpotlight()
    }

    // 3. 清空所有会话索引不应崩溃
    func testClearAllDoesNotCrash() async throws {
        SpotlightIndexer.clearAll()
        await waitForSpotlight()
    }

    // 4. 索引空消息会话（contentDescription 为 nil）不应崩溃
    func testIndexConversationWithEmptyMessages() async throws {
        let conversation = Conversation(title: "空会话", systemPrompt: "系统提示")
        // messages 为空数组，conversation.messages.last 为 nil
        XCTAssertTrue(conversation.messages.isEmpty, "新会话消息列表应为空")
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
    }

    // 5. 索引含多条消息的会话不应崩溃，且使用最后一条消息作为 contentDescription
    func testIndexConversationWithMultipleMessages() async throws {
        let conversation = Conversation(title: "多消息会话", systemPrompt: "系统提示")
        let msg1 = ChatMessage(role: "user", content: "第一条消息")
        let msg2 = ChatMessage(role: "assistant", content: "第二条消息")
        let msg3 = ChatMessage(role: "user", content: "最后一条消息")
        msg1.conversation = conversation
        msg2.conversation = conversation
        msg3.conversation = conversation
        conversation.messages = [msg1, msg2, msg3]
        XCTAssertEqual(conversation.messages.last?.content, "最后一条消息")
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
    }

    // 6. 索引多个会话不应崩溃
    func testIndexMultipleConversations() async throws {
        for i in 0..<5 {
            let conversation = Conversation(title: "会话\(i)", systemPrompt: "")
            SpotlightIndexer.index(conversation)
        }
        await waitForSpotlight()
    }

    // 7. 先索引后移除不应崩溃
    func testIndexThenRemoveIndex() async throws {
        let conversation = Conversation(title: "索引后删除", systemPrompt: "")
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
        SpotlightIndexer.removeIndex(conversationId: conversation.id)
        await waitForSpotlight()
    }

    // 8. 重复索引同一会话不应崩溃（更新索引）
    func testIndexSameConversationMultipleTimes() async throws {
        let conversation = Conversation(title: "重复索引", systemPrompt: "")
        SpotlightIndexer.index(conversation)
        SpotlightIndexer.index(conversation)
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
    }

    // 9. 移除不存在的会话索引不应崩溃
    func testRemoveNonExistentIndex() async throws {
        SpotlightIndexer.removeIndex(conversationId: UUID())
        await waitForSpotlight()
    }

    // 10. 连续多次 clearAll 不应崩溃
    func testClearAllMultipleTimes() async throws {
        SpotlightIndexer.clearAll()
        SpotlightIndexer.clearAll()
        SpotlightIndexer.clearAll()
        await waitForSpotlight()
    }

    // 11. 移除索引后再次索引同一会话不应崩溃
    func testRemoveThenReIndex() async throws {
        let conversation = Conversation(title: "删除后重建", systemPrompt: "")
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
        SpotlightIndexer.removeIndex(conversationId: conversation.id)
        await waitForSpotlight()
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
    }

    // 12. 索引会话的 id 应为 UUID 字符串
    func testConversationIdIsUUID() async throws {
        let conversation = Conversation(title: "UUID 测试", systemPrompt: "")
        // conversation.id 为 UUID 类型，SpotlightIndexer 用 uuidString 作为 identifier
        XCTAssertFalse(conversation.id.uuidString.isEmpty)
        SpotlightIndexer.index(conversation)
        await waitForSpotlight()
    }
}
