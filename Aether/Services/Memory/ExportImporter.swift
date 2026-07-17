import Foundation
import SwiftData

/// Task 19 阶段 4: 记忆导出/导入器。
///
/// JSON 导出格式：
/// ```json
/// {
///   "version": 1,
///   "exportedAt": "2026-07-18T08:00:00Z",
///   "count": 2,
///   "memories": [
///     {
///       "id": "uuid",
///       "content": "记忆内容",
///       "embedding": [0.1, 0.2, ...],
///       "createdAt": "2026-07-01T08:00:00Z",
///       "category": "preference",
///       "importance": 0.8,
///       "lastAccessedAt": "2026-07-10T08:00:00Z",
///       "isUserExplicit": true,
///       "archivedAt": null,
///       "sourceConversationID": null
///     }
///   ]
/// }
/// ```
///
/// 设计要点：
/// - 导出：序列化全部 Memory（含已归档），可选是否加密。
/// - 导入：合并到当前 ModelContext，按 ID 去重（已存在则跳过）。
@MainActor
final class ExportImporter {
    /// 导出文件版本
    static let formatVersion: Int = 1

    /// MemoryService 实例（用于访问 SwiftData）
    private let memoryService: MemoryService
    /// 加密层（可选，启用后导出加密的 JSON）
    private let encryptionLayer: EncryptionLayer

    /// 创建 ExportImporter 实例
    /// - Parameters:
    ///   - memoryService: MemoryService 实例
    ///   - encryptionLayer: 加密层实例，默认单例
    init(memoryService: MemoryService, encryptionLayer: EncryptionLayer = .shared) {
        self.memoryService = memoryService
        self.encryptionLayer = encryptionLayer
    }

    // MARK: - 导出

    /// 导出全部记忆为 JSON 数据。
    /// - Parameter encrypt: 是否加密导出（默认 false；true 时返回密文 Data）
    /// - Returns: JSON 或加密后的 Data
    /// - Throws: 编码或加密失败
    func exportAllMemories(encrypt: Bool = false) async throws -> Data {
        let memories = try memoryService.getAllMemories()
        let now = Date()
        let records = memories.map { memory in
            MemoryExportRecord(
                id: memory.id,
                content: memory.content,
                embedding: memory.embedding,
                createdAt: memory.createdAt,
                category: memory.category,
                importance: memory.importance,
                lastAccessedAt: memory.lastAccessedAt,
                isUserExplicit: memory.isUserExplicit,
                archivedAt: memory.archivedAt,
                sourceConversationID: memory.sourceConversationID
            )
        }
        let exportFile = MemoryExportFile(
            version: Self.formatVersion,
            exportedAt: now,
            count: records.count,
            memories: records
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportFile)
        if encrypt && encryptionLayer.isEnabled {
            return try encryptionLayer.encrypt(jsonData)
        }
        return jsonData
    }

    /// 导出全部记忆到指定 URL（写入文件）。
    /// - Parameters:
    ///   - url: 目标文件 URL
    ///   - encrypt: 是否加密导出
    /// - Returns: 导出的记忆数
    @discardableResult
    func exportToFile(url: URL, encrypt: Bool = false) async throws -> Int {
        let data = try await exportAllMemories(encrypt: encrypt)
        try data.write(to: url, options: .atomic)
        let file = try JSONDecoder().decode(MemoryExportFile.self, from: data)
        return file.count
    }

    // MARK: - 导入

    /// 从 JSON Data 导入记忆。
    /// - Parameter data: JSON 或加密的 Data
    /// - Returns: 导入结果统计
    /// - Throws: 解码或解密失败
    @discardableResult
    func importFromData(_ data: Data) async throws -> MemoryImportResult {
        // 尝试解密（若数据为加密格式）
        let jsonData: Data
        if encryptionLayer.isEnabled {
            // 优先尝试解密
            do {
                jsonData = try encryptionLayer.decrypt(data)
            } catch {
                // 解密失败：可能是明文 JSON，直接使用原数据
                jsonData = data
            }
        } else {
            jsonData = data
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(MemoryExportFile.self, from: jsonData)
        // 加载现有记忆 ID 集合用于去重
        let existing = try memoryService.getAllMemories()
        let existingIDs = Set(existing.map { $0.id })
        var imported = 0
        var skipped = 0
        for record in file.memories {
            if existingIDs.contains(record.id) {
                skipped += 1
                continue
            }
            let memory = Memory(
                content: record.content,
                embedding: record.embedding,
                category: record.category,
                importance: record.importance,
                sourceConversationID: record.sourceConversationID,
                isUserExplicit: record.isUserExplicit
            )
            // 设置可变字段
            memory.id = record.id
            memory.createdAt = record.createdAt
            memory.lastAccessedAt = record.lastAccessedAt
            memory.archivedAt = record.archivedAt
            memoryService.insertImported(memory)
            imported += 1
        }
        return MemoryImportResult(
            importedCount: imported,
            skippedCount: skipped,
            totalCount: file.count
        )
    }

    /// 从文件 URL 导入记忆。
    /// - Parameter url: 源文件 URL
    /// - Returns: 导入结果统计
    func importFromFile(url: URL) async throws -> MemoryImportResult {
        let data = try Data(contentsOf: url)
        return try await importFromData(data)
    }

    // MARK: - 清空

    /// 清空全部记忆（包括 SwiftData 与 VectorStore）。
    /// - Returns: 已删除的记忆数
    @discardableResult
    func clearAllMemories() async throws -> Int {
        let memories = try memoryService.getAllMemories()
        let count = memories.count
        for memory in memories {
            try await memoryService.delete(memory: memory)
        }
        return count
    }
}

// MARK: - 导出/导入数据模型

/// 导出文件根结构。
struct MemoryExportFile: Codable {
    /// 格式版本
    let version: Int
    /// 导出时间
    let exportedAt: Date
    /// 记忆数
    let count: Int
    /// 记忆记录数组
    let memories: [MemoryExportRecord]
}

/// 单条记忆导出记录。
struct MemoryExportRecord: Codable {
    let id: UUID
    let content: String
    let embedding: [Double]
    let createdAt: Date
    let category: String
    let importance: Double
    let lastAccessedAt: Date?
    let isUserExplicit: Bool
    let archivedAt: Date?
    let sourceConversationID: UUID?
}

/// 导入结果统计。
struct MemoryImportResult: Sendable {
    /// 新导入数
    let importedCount: Int
    /// 跳过数（ID 重复）
    let skippedCount: Int
    /// 文件中总数
    let totalCount: Int
}
