import XCTest
@testable import AIBuilder

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
}
