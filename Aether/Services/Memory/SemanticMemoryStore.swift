import Foundation

/// 语义记忆存储，封装 MemoryService 的检索能力，提供格式化注入 systemPrompt 的文本。
///
/// 设计要点：
/// - retrieveRelevantMemories：委托 RecallEngine 做复合召回（相似度 + importance + 时间衰减）。
/// - formatMemoriesForPrompt：将记忆格式化为可注入 systemPrompt 的文本块。
///
/// Task 19 阶段 2: 对外接口不变，内部 recall 委托从 `MemoryService.recall` 改为 `RecallEngine`。
/// RecallEngine 通过 VectorStore 取 ANN top-20 候选，再复合评分 + 同 category 去重取 top-5。
final class SemanticMemoryStore {
    /// MemoryService 实例（用于生成 query embedding 与加载 SwiftData Memory）
    private let memoryService: MemoryService
    /// RecallEngine 实例（Task 19 阶段 2 引入）
    private let recallEngine: RecallEngine

    /// 创建 SemanticMemoryStore 实例
    /// - Parameters:
    ///   - memoryService: MemoryService 实例
    ///   - recallEngine: RecallEngine 实例，nil 时自动创建（默认走 VectorStoreFactory.shared）
    init(memoryService: MemoryService, recallEngine: RecallEngine? = nil) {
        self.memoryService = memoryService
        self.recallEngine = recallEngine ?? RecallEngine()
    }

    /// 检索与查询相关的记忆。Task 19 阶段 2: 委托 RecallEngine 做复合召回。
    /// - Parameters:
    ///   - query: 查询文本
    ///   - limit: 返回条数上限，默认 3
    /// - Returns: 按相似度降序排列的记忆数组
    func retrieveRelevantMemories(query: String, limit: Int = 3) async throws -> [Memory] {
        // 1. 生成 query embedding（与 MemoryService.recall 路径一致）
        guard let queryEmbedding = try? await generateQueryEmbedding(for: query),
              !queryEmbedding.isEmpty else {
            return []
        }
        // 2. 加载全部 Memory（活跃、未归档）作为候选
        let allMemories = try fetchActiveMemories()
        // 3. 委托 RecallEngine 复合召回
        return await recallEngine.recall(query: queryEmbedding, memories: allMemories, limit: limit)
    }

    /// 格式化记忆为 systemPrompt 注入文本。
    /// 格式：
    /// ```
    /// 【相关记忆】
    /// 1. [preference] 用户偏好简洁回答
    /// 2. [fact] 用户是素食者
    /// 3. [instruction] 回答使用正式语气
    /// ```
    /// - Parameter memories: 记忆数组
    /// - Returns: 格式化文本；空数组返回空字符串
    func formatMemoriesForPrompt(_ memories: [Memory]) -> String {
        guard !memories.isEmpty else { return "" }
        var lines = ["【相关记忆】"]
        for (index, memory) in memories.enumerated() {
            lines.append("\(index + 1). [\(memory.category)] \(memory.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 私有辅助

    /// 生成 query 的 embedding（复用 MemoryService 的 embeddingService）。
    /// 通过反射调用 MemoryService 私有方法不可行，故此处走与 MemoryService 一致的 embedding 路径。
    private func generateQueryEmbedding(for query: String) async throws -> [Double] {
        // 委托 MemoryService.recall 的内部逻辑：调用 MemoryService.recall 但丢弃结果，仅取 embedding
        // 为避免重复 embedding，直接复用 memoryService.recall 的 query 嵌入路径
        // Task 19 阶段 2: 这里通过 MemoryService 的 recall（仅返回 top 记忆），但 RecallEngine 需要原始 embedding
        // 为保持接口稳定，引入 memoryService.generateQueryEmbedding 暴露的内部 API
        return try await memoryService.generateQueryEmbedding(for: query)
    }

    /// 加载所有活跃（未归档）的 Memory
    private func fetchActiveMemories() throws -> [Memory] {
        // 仅加载未归档记忆（archivedAt == nil）
        let active = try memoryService.getAllMemories()
        return active.filter { $0.archivedAt == nil }
    }
}
