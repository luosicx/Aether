import XCTest
import SwiftData
@testable import Aether

/// DocumentChunk 单元测试
/// DocumentChunk 是 SwiftData @Model，使用 in-memory ModelContainer 测试。
/// weight 衰减逻辑（*= 0.8 / /= 0.8）在 ChatStorage 中实现，
/// 本测试验证 weight 属性的默认值、边界值以及外部衰减逻辑的数值正确性。
@MainActor
final class DocumentChunkTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: DocumentChunk.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - 初始化

    /// 默认参数初始化：embedding 为空、source 为空、chunkIndex 为 0、weight 为 1.0
    func testInitWithDefaults() {
        let chunk = DocumentChunk(content: "测试内容")
        XCTAssertEqual(chunk.content, "测试内容", "content 应为传入值")
        XCTAssertEqual(chunk.embedding, [], "默认 embedding 应为空数组")
        XCTAssertEqual(chunk.source, "", "默认 source 应为空字符串")
        XCTAssertEqual(chunk.chunkIndex, 0, "默认 chunkIndex 应为 0")
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "默认 weight 应为 1.0")
        XCTAssertNotNil(chunk.id, "id 应非 nil")
    }

    /// 全参数初始化：所有字段应正确赋值
    func testInitWithAllParameters() {
        let embedding: [Float] = [0.1, 0.2, 0.3]
        let chunk = DocumentChunk(
            content: "完整内容",
            embedding: embedding,
            source: "doc.pdf",
            chunkIndex: 5
        )
        XCTAssertEqual(chunk.content, "完整内容")
        XCTAssertEqual(chunk.embedding, embedding, "embedding 应为传入的向量")
        XCTAssertEqual(chunk.source, "doc.pdf")
        XCTAssertEqual(chunk.chunkIndex, 5)
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "weight 默认仍为 1.0")
    }

    /// 多次初始化应生成不同的 UUID
    func testInitGeneratesUniqueIDs() {
        let chunk1 = DocumentChunk(content: "a")
        let chunk2 = DocumentChunk(content: "b")
        XCTAssertNotEqual(chunk1.id, chunk2.id, "不同实例的 id 应不同")
    }

    /// createdAt 应在初始化时被设置为当前时间附近
    func testCreatedAtIsSetOnInit() {
        let before = Date()
        let chunk = DocumentChunk(content: "时间测试")
        let after = Date()
        XCTAssertTrue(chunk.createdAt >= before, "createdAt 应不早于创建前的时间")
        XCTAssertTrue(chunk.createdAt <= after, "createdAt 应不晚于创建后的时间")
    }

    // MARK: - weight 边界值与衰减逻辑

    /// weight 默认值应为 1.0
    func testWeightDefaultValue() {
        let chunk = DocumentChunk(content: "测试")
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "weight 默认应为 1.0")
    }

    /// weight 衰减：模拟踩（*= 0.8）后应变为 0.8
    /// 对应 ChatStorage.saveFeedback(isPositive: false) 的逻辑
    func testWeightDecayOnNegativeFeedback() {
        let chunk = DocumentChunk(content: "测试")
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001)

        // 模拟 ChatStorage 中的降权逻辑：chunk.weight *= 0.8
        chunk.weight *= 0.8
        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.0001, "一次踩后 weight 应为 0.8")

        // 二次踩
        chunk.weight *= 0.8
        XCTAssertEqual(chunk.weight, 0.64, accuracy: 0.0001, "两次踩后 weight 应为 0.64")
    }

    /// weight 恢复：模拟赞（/= 0.8，上限 1.0）后应恢复
    /// 对应 ChatStorage.saveFeedback(isPositive: true) 的逻辑
    func testWeightRecoverOnPositiveFeedback() {
        let chunk = DocumentChunk(content: "测试")
        // 先踩一次降到 0.8
        chunk.weight *= 0.8
        XCTAssertEqual(chunk.weight, 0.8, accuracy: 0.0001)

        // 模拟 ChatStorage 中的提权逻辑：chunk.weight = min(chunk.weight / 0.8, 1.0)
        chunk.weight = min(chunk.weight / 0.8, 1.0)
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "一次赞后 weight 应恢复到 1.0")
    }

    /// weight 上限：赞的提权不应超过 1.0
    func testWeightUpperBoundOnPositiveFeedback() {
        let chunk = DocumentChunk(content: "测试")
        // weight 已为 1.0，再赞应被 min 截断为 1.0
        chunk.weight = min(chunk.weight / 0.8, 1.0)
        XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "weight 上限应为 1.0")
    }

    /// weight 多次踩后趋于 0 但不为 0
    func testWeightMultipleDecaysTrendTowardZero() {
        let chunk = DocumentChunk(content: "测试")
        for _ in 0..<10 {
            chunk.weight *= 0.8
        }
        XCTAssertGreaterThan(chunk.weight, 0, "多次踩后 weight 应大于 0")
        XCTAssertLessThan(chunk.weight, 0.2, "10 次踩后 weight 应小于 0.2")
    }

    /// weight 为 0 时手动设置应可读取（边界值）
    func testWeightZeroBoundary() {
        let chunk = DocumentChunk(content: "测试")
        chunk.weight = 0
        XCTAssertEqual(chunk.weight, 0, accuracy: 0.0001, "weight 应可为 0")
    }

    /// weight 为负数时手动设置应可读取（边界值，虽然业务上不应出现）
    func testWeightNegativeBoundary() {
        let chunk = DocumentChunk(content: "测试")
        chunk.weight = -1.0
        XCTAssertEqual(chunk.weight, -1.0, accuracy: 0.0001, "weight 应可为负数（业务约束在外部）")
    }

    // MARK: - embedding 属性

    /// embedding 可在创建后回填
    func testEmbeddingBackfill() {
        let chunk = DocumentChunk(content: "待嵌入")
        XCTAssertEqual(chunk.embedding, [], "初始 embedding 应为空")

        let vector: [Float] = [0.5, 0.5, 0.5]
        chunk.embedding = vector
        XCTAssertEqual(chunk.embedding, vector, "回填后 embedding 应为传入向量")
    }

    /// 空内容字符串可被存储（边界值）
    func testEmptyContent() {
        let chunk = DocumentChunk(content: "")
        XCTAssertEqual(chunk.content, "", "空字符串 content 应可存储")
    }

    // MARK: - SwiftData 持久化

    /// 插入并 fetch 应返回存储的 chunk
    func testSwiftDataInsertAndFetch() throws {
        let chunk = DocumentChunk(content: "持久化测试", source: "test.pdf", chunkIndex: 0)
        context.insert(chunk)
        try context.save()

        let descriptor = FetchDescriptor<DocumentChunk>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "应 fetch 到 1 条记录")
        XCTAssertEqual(fetched.first?.content, "持久化测试")
        XCTAssertEqual(fetched.first?.source, "test.pdf")
    }

    /// 插入多条后 fetch 应返回全部，且 weight 默认值保持
    func testSwiftDataInsertMultipleChunks() throws {
        for i in 0..<5 {
            let chunk = DocumentChunk(content: "chunk \(i)", source: "doc.pdf", chunkIndex: i)
            context.insert(chunk)
        }
        try context.save()

        let descriptor = FetchDescriptor<DocumentChunk>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 5, "应 fetch 到 5 条记录")
        for chunk in fetched {
            XCTAssertEqual(chunk.weight, 1.0, accuracy: 0.0001, "所有 chunk 的 weight 默认应为 1.0")
        }
    }

    /// 按 source 过滤 fetch（使用 fetch + filter，避免 #Predicate 宏在测试目标中的限制）
    func testSwiftDataFetchBySource() throws {
        context.insert(DocumentChunk(content: "a", source: "A.pdf", chunkIndex: 0))
        context.insert(DocumentChunk(content: "b", source: "B.pdf", chunkIndex: 0))
        context.insert(DocumentChunk(content: "c", source: "A.pdf", chunkIndex: 1))
        try context.save()

        let descriptor = FetchDescriptor<DocumentChunk>()
        let allChunks = try context.fetch(descriptor)
        let fetched = allChunks.filter { $0.source == "A.pdf" }
        XCTAssertEqual(fetched.count, 2, "source=A.pdf 应有 2 条记录")
        XCTAssertTrue(fetched.allSatisfy { $0.source == "A.pdf" })
    }

    /// 修改 weight 后持久化，fetch 应返回新值
    func testSwiftDataWeightPersistenceAfterMutation() throws {
        let chunk = DocumentChunk(content: "权重测试", source: "w.pdf")
        context.insert(chunk)
        chunk.weight *= 0.8  // 衰减一次
        try context.save()

        let descriptor = FetchDescriptor<DocumentChunk>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        let persistedWeight = try XCTUnwrap(fetched.first?.weight, "fetch 到的 chunk weight 应非 nil")
        XCTAssertEqual(Double(persistedWeight), 0.8, accuracy: 0.0001,
                       "持久化后 fetch 的 weight 应为衰减后的 0.8")
    }
}
