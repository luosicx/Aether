import XCTest
import SwiftData
@testable import AIBuilder

/// Day 12: MessageFeedback 与 ChatStorage.feedback API 单元测试
@MainActor
final class MessageFeedbackTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var storage: ChatStorage!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: MessageFeedback.self, DocumentChunk.self, configurations: config)
        context = ModelContext(container)
        storage = ChatStorage(modelContext: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        storage = nil
        super.tearDown()
    }

    func testSaveFeedbackPersistsRecord() {
        let messageId = UUID()
        storage.saveFeedback(messageId: messageId, isPositive: true, citations: [])

        let fetched = storage.fetchFeedback(messageId: messageId)
        XCTAssertNotNil(fetched, "saveFeedback 应持久化记录")
        XCTAssertEqual(fetched?.isPositive, true, "记录的 isPositive 应为 true")
    }

    func testFetchFeedbackReturnsExisting() {
        let messageId = UUID()
        storage.saveFeedback(messageId: messageId, isPositive: false, citations: [])

        // 不同 messageId 应返回 nil
        let otherId = UUID()
        XCTAssertNil(storage.fetchFeedback(messageId: otherId), "未保存的 messageId 应返回 nil")

        // 已保存的 messageId 应返回记录
        let fetched = storage.fetchFeedback(messageId: messageId)
        XCTAssertEqual(fetched?.isPositive, false, "已保存的 messageId 应返回 isPositive=false")
    }

    func testNegativeFeedbackReducesChunkWeight() {
        let chunk = DocumentChunk(content: "test", embedding: [], source: "doc", chunkIndex: 0)
        context.insert(chunk)
        try? context.save()

        let originalWeight = chunk.weight  // 1.0
        XCTAssertEqual(originalWeight, 1.0, "默认权重应为 1.0")

        storage.saveFeedback(messageId: UUID(), isPositive: false, citations: [chunk])

        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.0001, "踩时应将权重 *= 0.8 = 0.8")
    }

    func testPositiveFeedbackRestoresChunkWeight() {
        let chunk = DocumentChunk(content: "test", embedding: [], source: "doc", chunkIndex: 0)
        chunk.weight = 0.8  // 模拟被踩后的权重
        context.insert(chunk)
        try? context.save()

        storage.saveFeedback(messageId: UUID(), isPositive: true, citations: [chunk])

        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "赞时应将权重 /= 0.8 = 1.0，但不超过 1.0 上限")
    }

    func testUpdateFeedbackSwitchesWeight() {
        // 场景：先赞（权重 1.0 → 1.0，已达上限），后切换为踩（权重 1.0 → 0.8）
        let chunk = DocumentChunk(content: "test", embedding: [], source: "doc", chunkIndex: 0)
        context.insert(chunk)
        try? context.save()

        let messageId = UUID()
        storage.saveFeedback(messageId: messageId, isPositive: true, citations: [chunk])
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "初始赞后权重应保持 1.0（上限）")

        guard let savedFeedback = storage.fetchFeedback(messageId: messageId) else {
            XCTFail("应能查询到已保存的 feedback")
            return
        }
        // 切换为踩：撤销之前提权（已在上限不再额外除），再降权
        // saveFeedback(true) 时权重从 1.0 → min(1.0/0.8, 1.0) = 1.0（已是上限，未实际变化）
        // updateFeedback(false) 触发切换：1.0 → 1.0 * 0.8 = 0.8
        storage.updateFeedback(savedFeedback, isPositive: false, citations: [chunk])
        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.0001, "切换为踩后权重应为 0.8")
        XCTAssertEqual(savedFeedback.isPositive, false, "feedback 记录的 isPositive 应更新为 false")
    }
}
