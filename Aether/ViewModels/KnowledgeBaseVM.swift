import Foundation
import SwiftData
import AetherFoundation
import AetherServices

/// 知识库 ViewModel，管理文档导入与列表展示。使用 @Observable + @MainActor 隔离。
@Observable
@MainActor
final class KnowledgeBaseVM {
    /// 文档列表行（聚合 source 计 chunkCount）
    struct DocumentRow: Identifiable, Hashable {
        /// 唯一标识（即 source）
        let id: String
        /// 文档来源文件名
        let source: String
        /// 该 source 下的分块数量
        let chunkCount: Int
        /// 该 source 下分块的最大创建时间（用于排序展示）
        let createdAt: Date
    }

    /// 文档列表
    var documents: [DocumentRow] = []
    /// 是否正在导入
    var isImporting = false
    /// 错误消息
    var errorMessage: String?

    /// RAG 服务
    private let ragService: RAGService
    /// 当前供应商
    let provider: ModelProvider
    /// 实际用于 embedding 的供应商（DeepSeek 降级到 Qwen）
    private let embeddingProvider: ModelProvider

    init(provider: ModelProvider = .deepseek) {
        self.provider = provider
        let resolved = EmbeddingService.resolveEmbedding(for: provider) ?? (DeepSeekClient(), provider)
        self.ragService = RAGService(embeddingService: EmbeddingService(client: resolved.0))
        self.embeddingProvider = resolved.1
    }

    /// 加载文档列表。
    /// 聚合逻辑：fetch 全部 DocumentChunk，按 source 聚合计 chunkCount，
    /// 取最大 createdAt 作为行时间，按 createdAt 降序排序。
    func load(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DocumentChunk>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let chunks = try? modelContext.fetch(descriptor) else {
            documents = []
            return
        }
        var seen: [String: (count: Int, createdAt: Date)] = [:]
        for chunk in chunks {
            if let existing = seen[chunk.source] {
                seen[chunk.source] = (existing.count + 1, max(existing.createdAt, chunk.createdAt))
            } else {
                seen[chunk.source] = (1, chunk.createdAt)
            }
        }
        documents = seen
            .map { DocumentRow(id: $0.key, source: $0.key, chunkCount: $0.value.count, createdAt: $0.value.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 删除指定 source 的全部分块
    func deleteDocument(source: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DocumentChunk>(
            predicate: #Predicate { $0.source == source }
        )
        guard let chunks = try? modelContext.fetch(descriptor) else { return }
        for chunk in chunks { modelContext.delete(chunk) }
        try? modelContext.save()
        documents.removeAll { $0.source == source }
    }

    /// 导入文档。
    /// 流程：1) 区分 pdf（PDFExtractor）与纯文本（String(contentsOf:)）；
    ///       2) 后台读 apiKey；3) ragService.indexDocument 索引；4) 重新 load 刷新列表。
    func importDocument(url: URL, modelContext: ModelContext) async {
        let source = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        var text: String?
        // 1) 区分 pdf 与纯文本
        if ext == "pdf" {
            text = PDFExtractor.extractText(from: url)
        } else {
            text = try? String(contentsOf: url, encoding: .utf8)
        }
        guard let content = text, !content.isEmpty else {
            errorMessage = String(format: NSLocalizedString("无法读取文档内容：%@", comment: ""), source)
            return
        }
        // DeepSeek 不支持 embedding，实时解析当前可用的 embedding provider（避免 init 时缓存 stale state）
        guard let resolved = EmbeddingService.resolveEmbedding(for: provider) else {
            errorMessage = NSLocalizedString("DeepSeek 不支持知识库嵌入，请在设置中配置 Qwen API Key 或切换供应商为 Qwen", comment: "")
            return
        }
        let resolvedClient = resolved.0
        let resolvedProvider = resolved.1
        // 2) 后台线程读取 apiKey（使用实时解析的 provider），避免主线程阻塞
        let embProvider = resolvedProvider
        let apiKey = await Task.detached(priority: .userInitiated) {
            KeychainManager.shared.getAPIKey(for: embProvider) ?? ""
        }.value
        // 校验 apiKey 非空，避免无效调用 embedding API
        guard !apiKey.isEmpty else {
            errorMessage = NSLocalizedString("请先在设置中配置 API Key", comment: "")
            return
        }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            // 3) 索引文档（使用实时解析的 RAGService）
            let resolvedRagService = RAGService(embeddingService: EmbeddingService(client: resolvedClient))
            try await resolvedRagService.indexDocument(text: content, source: source, modelContext: modelContext, apiKey: apiKey)
            // 4) 刷新列表
            load(modelContext: modelContext)
        } catch {
            errorMessage = String(format: NSLocalizedString("导入失败：%@", comment: ""), error.localizedDescription)
        }
    }
}
