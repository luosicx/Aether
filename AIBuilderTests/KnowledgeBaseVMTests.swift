import XCTest
import SwiftData
@testable import AIBuilder

/// KnowledgeBaseVM 单元测试
@MainActor
final class KnowledgeBaseVMTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var vm: KnowledgeBaseVM!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
        vm = KnowledgeBaseVM()
    }

    override func tearDownWithError() throws {
        vm = nil
        context = nil
        container = nil
    }

    /// Helper：为指定 source 插入 N 个 chunk，createdAt 从 baseTime 起递增
    private func insertChunks(source: String, count: Int, baseTime: TimeInterval) {
        for i in 0..<count {
            let chunk = DocumentChunk(
                content: "chunk \(i) of \(source)",
                embedding: [Float(i)],
                source: source,
                chunkIndex: i
            )
            chunk.createdAt = Date(timeIntervalSince1970: baseTime + Double(i))
            context.insert(chunk)
        }
        try? context.save()
    }

    /// load 聚合 chunkCount 并按 createdAt 降序
    func testLoadAggregatesChunkCountAndSorts() {
        // Source A：3 chunks，createdAt 较旧（1000-1002）
        insertChunks(source: "A.pdf", count: 3, baseTime: 1000)
        // Source B：2 chunks，createdAt 较新（2000-2001）
        insertChunks(source: "B.pdf", count: 2, baseTime: 2000)

        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.count, 2, "应聚合为 2 个文档")

        // 按 createdAt 降序：B（max=2001）在前，A（max=1002）在后
        XCTAssertEqual(vm.documents.map(\.source), ["B.pdf", "A.pdf"],
                       "应按 createdAt 降序排序")

        // chunkCount 正确
        let docB = vm.documents.first { $0.source == "B.pdf" }
        XCTAssertEqual(docB?.chunkCount, 2, "B.pdf 应聚合 2 chunks")
        let docA = vm.documents.first { $0.source == "A.pdf" }
        XCTAssertEqual(docA?.chunkCount, 3, "A.pdf 应聚合 3 chunks")

        // createdAt 字段应取该 source 下所有 chunk 的最大值
        XCTAssertEqual(docB?.createdAt, Date(timeIntervalSince1970: 2001),
                       "B 的 createdAt 应为其所有 chunk 的最大 createdAt")
        XCTAssertEqual(docA?.createdAt, Date(timeIntervalSince1970: 1002),
                       "A 的 createdAt 应为其所有 chunk 的最大 createdAt")
    }

    /// deleteDocument(source:) 删除指定 source 的所有 chunks
    func testDeleteDocumentRemovesAllChunks() throws {
        insertChunks(source: "A.pdf", count: 3, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 2, baseTime: 2000)

        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 2)

        // 删除 source A
        vm.deleteDocument(source: "A.pdf", modelContext: context)

        // vm.documents 应只剩 B
        XCTAssertEqual(vm.documents.count, 1, "删除 A 后应只剩 1 个文档")
        XCTAssertEqual(vm.documents.first?.source, "B.pdf")

        // context 中 A 的所有 chunks 应被删除
        let allChunks = try context.fetch(FetchDescriptor<DocumentChunk>())
        let remainingA = allChunks.filter { $0.source == "A.pdf" }
        XCTAssertEqual(remainingA.count, 0, "context 中 A 的所有 chunks 应被删除")

        // B 的 chunks 应保留
        let remainingB = allChunks.filter { $0.source == "B.pdf" }
        XCTAssertEqual(remainingB.count, 2, "B 的 chunks 应保留")
    }
}
