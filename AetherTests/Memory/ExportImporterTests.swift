import XCTest
import SwiftData
@testable import Aether

/// Task 19 阶段 4: ExportImporter 单元测试。
///
/// 覆盖：JSON 导出格式、加密导出、明文导入、加密导入、ID 去重、清空、错误处理。
@MainActor
final class ExportImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var stub: StubEmbeddingService!
    private var service: MemoryService!
    private var factory: VectorStoreFactory!
    private var exporter: ExportImporter!

    override func setUpWithError() throws {
        // 隔离 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        try KeychainManager.shared.saveAPIKey("test-key", for: .qwen)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Memory.self, configurations: config)
        context = ModelContext(container)

        stub = StubEmbeddingService()
        factory = VectorStoreFactory()
        factory.reset()
        factory.setOverride(BruteForceVectorStore())

        service = MemoryService(modelContext: context, embeddingService: stub, vectorStoreFactory: factory)
        exporter = ExportImporter(memoryService: service)

        // 重置加密层
        EncryptionLayer.shared.clearKey()
    }

    override func tearDownWithError() throws {
        EncryptionLayer.shared.clearKey()
        factory.reset()
        exporter = nil
        service = nil
        stub = nil
        context = nil
        container = nil
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    // MARK: - 桩 EmbeddingService

    final class StubEmbeddingService: EmbeddingService {
        var embeddingMap: [String: [Float]] = [:]
        var defaultEmbedding: [Float] = [0, 0, 0]

        override func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            return texts.map { embeddingMap[$0] ?? defaultEmbedding }
        }
    }

    // MARK: - 辅助

    /// 创建并插入一条 Memory
    private func makeMemory(
        content: String,
        embedding: [Double] = [1, 0],
        category: String = "context",
        importance: Double = 0.5,
        isUserExplicit: Bool = false
    ) -> Memory {
        let memory = Memory(
            content: content,
            embedding: embedding,
            category: category,
            importance: importance,
            isUserExplicit: isUserExplicit
        )
        context.insert(memory)
        try? context.save()
        return memory
    }

    // MARK: - 导出测试

    /// 空仓库导出应返回有效 JSON
    func testExportEmptyReturnsValidJSON() async throws {
        let data = try await exporter.exportAllMemories()

        // 验证可解码
        let file = try makeISO8601Decoder().decode(MemoryExportFile.self, from: data)
        XCTAssertEqual(file.version, 1, "版本应为 1")
        XCTAssertEqual(file.count, 0, "空仓库 count=0")
        XCTAssertTrue(file.memories.isEmpty)
    }

    /// 导出应包含所有记忆字段
    func testExportIncludesAllFields() async throws {
        _ = makeMemory(content: "测试", embedding: [0.1, 0.2], category: "preference", importance: 0.8)

        let data = try await exporter.exportAllMemories()
        let file = try makeISO8601Decoder().decode(MemoryExportFile.self, from: data)

        XCTAssertEqual(file.count, 1)
        let record = file.memories[0]
        XCTAssertEqual(record.content, "测试")
        XCTAssertEqual(record.embedding, [0.1, 0.2])
        XCTAssertEqual(record.category, "preference")
        XCTAssertEqual(record.importance, 0.8, accuracy: 0.001)
        XCTAssertNotNil(record.createdAt)
    }

    /// 导出多条记忆应正确计数
    func testExportMultipleMemories() async throws {
        _ = makeMemory(content: "A")
        _ = makeMemory(content: "B")
        _ = makeMemory(content: "C")

        let data = try await exporter.exportAllMemories()
        let file = try makeISO8601Decoder().decode(MemoryExportFile.self, from: data)

        XCTAssertEqual(file.count, 3)
        XCTAssertEqual(file.memories.count, 3)
    }

    /// 加密导出应返回非 JSON 数据
    func testEncryptedExportProducesNonJSON() async throws {
        _ = makeMemory(content: "加密测试")
        EncryptionLayer.shared.enable()

        let data = try await exporter.exportAllMemories(encrypt: true)

        // 应无法直接解码为 JSON（加密后）
        XCTAssertThrowsError(try makeISO8601Decoder().decode(MemoryExportFile.self, from: data), "加密数据不应能直接解码为 JSON")
    }

    // MARK: - 导入测试

    /// 导入明文 JSON 应添加新记忆
    func testImportPlainJSONAddsMemories() async throws {
        // 准备导出数据
        _ = makeMemory(content: "原始记忆")
        let exportData = try await exporter.exportAllMemories()

        // 清空后导入
        _ = try await exporter.clearAllMemories()
        let result = try await exporter.importFromData(exportData)

        XCTAssertEqual(result.importedCount, 1, "应导入 1 条")
        XCTAssertEqual(result.skippedCount, 0, "无重复")
        XCTAssertEqual(result.totalCount, 1)
        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "原始记忆")
    }

    /// 导入加密 JSON 应正确还原
    func testImportEncryptedJSON() async throws {
        _ = makeMemory(content: "加密记忆")
        EncryptionLayer.shared.enable()
        let exportData = try await exporter.exportAllMemories(encrypt: true)

        // 清空后导入
        _ = try await exporter.clearAllMemories()
        let result = try await exporter.importFromData(exportData)

        XCTAssertEqual(result.importedCount, 1, "加密数据应能导入")
        let all = try service.getAllMemories()
        XCTAssertEqual(all.first?.content, "加密记忆")
    }

    /// 导入重复 ID 应跳过
    func testImportSkipsDuplicateIDs() async throws {
        let memory = makeMemory(content: "已存在")
        let exportData = try await exporter.exportAllMemories()

        // 不清空直接导入（ID 重复）
        let result = try await exporter.importFromData(exportData)

        XCTAssertEqual(result.importedCount, 0, "重复 ID 应跳过")
        XCTAssertEqual(result.skippedCount, 1, "应跳过 1 条")
        XCTAssertEqual(result.totalCount, 1)
        // 原记忆仍存在
        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, memory.id)
    }

    /// 部分重复导入应正确处理
    func testImportPartialDuplicates() async throws {
        // 已存在 1 条
        let existing = makeMemory(content: "已存在")

        // 构造导出文件（含已存在 + 新增）
        let newID = UUID()
        let now = Date()
        let records = [
            MemoryExportRecord(
                id: existing.id,  // 重复
                content: "已存在",
                embedding: [1, 0],
                createdAt: now,
                category: "context",
                importance: 0.5,
                lastAccessedAt: nil,
                isUserExplicit: false,
                archivedAt: nil,
                sourceConversationID: nil
            ),
            MemoryExportRecord(
                id: newID,  // 新增
                content: "新导入",
                embedding: [0, 1],
                createdAt: now,
                category: "fact",
                importance: 0.9,
                lastAccessedAt: nil,
                isUserExplicit: true,
                archivedAt: nil,
                sourceConversationID: nil
            )
        ]
        let file = MemoryExportFile(version: 1, exportedAt: now, count: records.count, memories: records)
        let exportData = try JSONEncoder().encode(file)

        let result = try await exporter.importFromData(exportData)

        XCTAssertEqual(result.importedCount, 1, "应导入 1 条新记忆")
        XCTAssertEqual(result.skippedCount, 1, "应跳过 1 条重复")
        // 验证新增记忆
        let all = try service.getAllMemories()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.id == newID })
    }

    /// 损坏的 JSON 应抛出错误
    func testImportCorruptedJSONThrows() async {
        let badData = Data("not json".utf8)
        do {
            _ = try await exporter.importFromData(badData)
            XCTFail("损坏的 JSON 应抛出错误")
        } catch {
            // 预期抛出
        }
    }

    // MARK: - 清空测试

    /// clearAllMemories 应删除所有记忆
    func testClearAllMemoriesRemovesAll() async throws {
        _ = makeMemory(content: "A")
        _ = makeMemory(content: "B")
        XCTAssertEqual(try service.getAllMemories().count, 2)

        let count = try await exporter.clearAllMemories()

        XCTAssertEqual(count, 2, "应删除 2 条")
        XCTAssertEqual(try service.getAllMemories().count, 0, "清空后应为 0")
    }

    /// 清空空仓库应返回 0
    func testClearEmptyRepositoryReturnsZero() async throws {
        let count = try await exporter.clearAllMemories()
        XCTAssertEqual(count, 0)
    }

    // MARK: - 文件操作

    /// 导出到文件再导入应正确还原
    func testExportToFileAndImportFromFile() async throws {
        _ = makeMemory(content: "文件测试")
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aether_test_export_\(UUID().uuidString).json")

        let exportedCount = try await exporter.exportToFile(url: url)
        XCTAssertEqual(exportedCount, 1)

        // 清空后从文件导入
        _ = try await exporter.clearAllMemories()
        let result = try await exporter.importFromFile(url: url)

        XCTAssertEqual(result.importedCount, 1)
        let all = try service.getAllMemories()
        XCTAssertEqual(all.first?.content, "文件测试")

        // 清理
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 数据模型

    /// MemoryExportRecord 编解码应正确
    func testMemoryExportRecordCoding() throws {
        let id = UUID()
        let conversationID = UUID()
        let now = Date()
        let record = MemoryExportRecord(
            id: id,
            content: "测试",
            embedding: [0.1, 0.2],
            createdAt: now,
            category: "preference",
            importance: 0.8,
            lastAccessedAt: now,
            isUserExplicit: true,
            archivedAt: nil,
            sourceConversationID: conversationID
        )
        let file = MemoryExportFile(version: 1, exportedAt: now, count: 1, memories: [record])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MemoryExportFile.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.memories[0].id, id)
        XCTAssertEqual(decoded.memories[0].content, "测试")
        XCTAssertEqual(decoded.memories[0].importance, 0.8, accuracy: 0.001)
        XCTAssertTrue(decoded.memories[0].isUserExplicit)
        XCTAssertEqual(decoded.memories[0].sourceConversationID, conversationID)
    }
}

// MARK: - JSONDecoder 便捷函数（仅测试用）

private func makeISO8601Decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
