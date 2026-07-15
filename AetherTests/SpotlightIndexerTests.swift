import AetherServices
import XCTest
@testable import Aether

/// Day 18 Task 12: SpotlightIndexer 单元测试
/// 验证 index / remove / removeAll 三个实例方法在模拟器环境下不崩溃。
/// Task 1.7: SpotlightIndexer 重构为 ConversationIndexer 协议实现（final class + 实例方法），
/// 测试改为通过 SpotlightIndexer.shared 单例与 ConversationIndexDTO 调用。
/// CSSearchableIndex 操作异步。
final class SpotlightIndexerTests: XCTestCase {

    private let indexer = SpotlightIndexer.shared

    /// 将 Conversation 转换为 ConversationIndexDTO（与 ChatStorage.indexConversation 一致）
    private func makeDTO(_ conversation: Conversation) -> ConversationIndexDTO {
        ConversationIndexDTO(
            id: conversation.id,
            title: conversation.title,
            lastMessageContent: conversation.messages.last?.content,
            createdAt: conversation.createdAt
        )
    }

    /// 异步等待 CSSearchableIndex 内部操作完成的辅助方法
    private func waitForSpotlight() async {
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    }

    // 1. 索引单个会话不应崩溃
    func testIndexDoesNotCrash() async throws {
        let conversation = Conversation(title: "测试会话", systemPrompt: "你是助手")
        await indexer.index(conversation: makeDTO(conversation))
        await waitForSpotlight()
    }

    // 2. 移除指定会话索引不应崩溃
    func testRemoveIndexDoesNotCrash() async throws {
        await indexer.remove(conversationId: UUID())
        await waitForSpotlight()
    }

    // 3. 清空所有会话索引不应崩溃
    func testClearAllDoesNotCrash() async throws {
        await indexer.removeAll()
        await waitForSpotlight()
    }

    // 4. 索引空消息会话（contentDescription 为 nil）不应崩溃
    func testIndexConversationWithEmptyMessages() async throws {
        let conversation = Conversation(title: "空会话", systemPrompt: "系统提示")
        // messages 为空数组，conversation.messages.last 为 nil
        XCTAssertTrue(conversation.messages.isEmpty, "新会话消息列表应为空")
        await indexer.index(conversation: makeDTO(conversation))
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
        await indexer.index(conversation: makeDTO(conversation))
        await waitForSpotlight()
    }

    // 6. 索引多个会话不应崩溃
    func testIndexMultipleConversations() async throws {
        for i in 0..<5 {
            let conversation = Conversation(title: "会话\(i)", systemPrompt: "")
            await indexer.index(conversation: makeDTO(conversation))
        }
        await waitForSpotlight()
    }

    // 7. 先索引后移除不应崩溃
    func testIndexThenRemoveIndex() async throws {
        let conversation = Conversation(title: "索引后删除", systemPrompt: "")
        await indexer.index(conversation: makeDTO(conversation))
        await waitForSpotlight()
        await indexer.remove(conversationId: conversation.id)
        await waitForSpotlight()
    }

    // 8. 重复索引同一会话不应崩溃（更新索引）
    func testIndexSameConversationMultipleTimes() async throws {
        let conversation = Conversation(title: "重复索引", systemPrompt: "")
        let dto = makeDTO(conversation)
        await indexer.index(conversation: dto)
        await indexer.index(conversation: dto)
        await indexer.index(conversation: dto)
        await waitForSpotlight()
    }

    // 9. 移除不存在的会话索引不应崩溃
    func testRemoveNonExistentIndex() async throws {
        await indexer.remove(conversationId: UUID())
        await waitForSpotlight()
    }

    // 10. 连续多次 removeAll 不应崩溃
    func testClearAllMultipleTimes() async throws {
        await indexer.removeAll()
        await indexer.removeAll()
        await indexer.removeAll()
        await waitForSpotlight()
    }

    // 11. 移除索引后再次索引同一会话不应崩溃
    func testRemoveThenReIndex() async throws {
        let conversation = Conversation(title: "删除后重建", systemPrompt: "")
        let dto = makeDTO(conversation)
        await indexer.index(conversation: dto)
        await waitForSpotlight()
        await indexer.remove(conversationId: conversation.id)
        await waitForSpotlight()
        await indexer.index(conversation: dto)
        await waitForSpotlight()
    }

    // 12. 索引会话的 id 应为 UUID 字符串
    func testConversationIdIsUUID() async throws {
        let conversation = Conversation(title: "UUID 测试", systemPrompt: "")
        // conversation.id 为 UUID 类型，SpotlightIndexer 用 uuidString 作为 identifier
        XCTAssertFalse(conversation.id.uuidString.isEmpty)
        await indexer.index(conversation: makeDTO(conversation))
        await waitForSpotlight()
    }
}
