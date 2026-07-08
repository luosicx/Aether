import Foundation
import SwiftData

/// 持久化文档分块（用于 RAG 知识库）
@Model
final class DocumentChunk {
    /// 分块唯一标识
    var id: UUID
    /// 分块文本
    var content: String
    /// 向量嵌入，Float 数组，检索时按 cosine 相似度排序
    var embedding: [Float]
    /// 来源文件名，用于去重和删除
    var source: String
    /// 同一 source 中的分块序号，从 0 递增
    var chunkIndex: Int
    /// 创建时间，用于排序
    var createdAt: Date
    /// 文档分块权重，被用户踩时 *= 0.8 衰减，被赞时 /= 0.8 恢复，上限 1.0
    var weight: Float = 1.0

    /// 创建 DocumentChunk 实例
    /// - Parameters:
    ///   - content: 分块文本（必填）
    ///   - embedding: 向量嵌入，默认空数组（待后续 embedding 生成后回填）
    ///   - source: 来源文件名，默认空字符串
    ///   - chunkIndex: 同一 source 中的分块序号，默认 0
    init(content: String, embedding: [Float] = [], source: String = "", chunkIndex: Int = 0) {
        self.id = UUID()
        self.content = content
        self.embedding = embedding
        self.source = source
        self.chunkIndex = chunkIndex
        self.createdAt = Date()
    }
}
