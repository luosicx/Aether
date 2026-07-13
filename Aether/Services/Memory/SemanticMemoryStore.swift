import Foundation

/// 语义记忆存储，封装 MemoryService 的检索能力，提供格式化注入 systemPrompt 的文本。
///
/// 设计要点：
/// - retrieveRelevantMemories：委托 MemoryService.recall 做语义检索，返回与查询最相关的记忆。
/// - formatMemoriesForPrompt：将记忆格式化为可注入 systemPrompt 的文本块。
final class SemanticMemoryStore {
    /// MemoryService 实例
    private let memoryService: MemoryService

    /// 创建 SemanticMemoryStore 实例
    /// - Parameter memoryService: MemoryService 实例
    init(memoryService: MemoryService) {
        self.memoryService = memoryService
    }

    /// 检索与查询相关的记忆。委托 MemoryService.recall 做语义检索。
    /// - Parameters:
    ///   - query: 查询文本
    ///   - limit: 返回条数上限，默认 3
    /// - Returns: 按相似度降序排列的记忆数组
    func retrieveRelevantMemories(query: String, limit: Int = 3) async throws -> [Memory] {
        try await memoryService.recall(query: query, limit: limit)
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
}
