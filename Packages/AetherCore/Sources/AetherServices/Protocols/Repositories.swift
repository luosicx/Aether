import AetherFoundation
import Foundation

// MARK: - 迁移计划（P2-4）
//
// 现状（截至 2026-07-20 审计）：
// - 4 个仓储协议（ConversationRepository / MessageRepository / MemoryRepository /
//   DocumentRepository）+ 4 个 SwiftData 实现（SwiftDataConversationRepository 等）已就绪，
//   共 38 个测试用例覆盖。
// - 但生产代码（ChatViewModel / MemoryService / RAGService / KnowledgeBaseVM 等 16+ 处）
//   仍直接访问 ModelContext，Repository 实现仅作为「平行脚手架」存在，未被任何生产路径调用。
// - ChatStorage（@MainActor，Aether/Services/Storage/ChatStorage.swift）是事实上的生产仓储，
//   与 ConversationRepository/MessageRepository 职责严重重叠。
// - 仓储协议此前无专属 Error 类型，实现侧直接抛 SwiftData / Foundation 错误，破坏抽象边界。
//
// 本批次（P2-4）最小可行修复：
// 1. 定义 `RepositoryError`，建立仓储层错误传播契约，支持 `underlying` 保留原始错误上下文
//    （修复 P2-3 审计发现的「throw XError(... error.localizedDescription) 上下文丢失」模式）。
// 2. 不强制既有 SwiftData 实现立即迁移到新 Error 类型，避免破坏 38 个测试用例。
//    实现侧可在后续批次逐步把 `catch { throw error }` 改为 `catch { throw .persistenceFailed(underlying: error) }`。
//
// 迁移优先级（建议）：
// - Phase 1（最低风险）：MemoryService / RAGService / KnowledgeBaseVM
//   这些 Service 已有协议化抽象，且无 UI 状态依赖，可直接注入对应 Repository。
// - Phase 2（中等风险）：ChatViewModel
//   ChatViewModel 中 `conversationRepo` / `messageRepo` 属性已声明但从未读取，
//   需替换 16+ 处 `modelContext.fetch` / `modelContext.save` 调用。
// - Phase 3（最高风险）：ChatStorage 替换决策
//   ChatStorage 提供了 Repository 协议尚未覆盖的方法：
//     - reorder([Conversation]) — 拖拽排序
//     - cleanupEmptyConversations() — 清理空对话
//     - forkConversation(from:at:) — 分叉对话
//     - fetchPreference() / savePreference(...) — 用户偏好读写
//     - wipeAllData() — UITEST 重置
//   迁移前需在 Repository 协议补齐上述方法，或保留 ChatStorage 作为 Repository 的
//   「扩展层」承载非 CRUD 操作，避免协议过度膨胀。
//
// 长期方向：仓储协议下沉到 AetherCore，ChatStorage 拆分为 ConversationRepository 实现 +
// UI 专属 helper（索引/分叉/偏好），彻底消除职责重叠。

/// 仓储层专属错误类型，建立跨层错误传播契约。
///
/// 设计原则：
/// - 所有 Repository 实现应在 catch 中包装底层错误为 `persistenceFailed(underlying:)`，
///   保留原始错误上下文（避免 `error.localizedDescription` 丢失类型信息）。
/// - 调用方可根据 case 进行业务分支（如 `.notFound` 触发 404 UI，`.conflict` 触发重试）。
/// - `Equatable` 仅基于 case 关联值的「类型可判等」语义，`underlying` Error 不参与判等
///   （Error 不一定 Equatable），故未声明 Equatable。
public enum RepositoryError: Error, LocalizedError {
    /// 实体未找到（按 ID 查询返回空，且业务上视为错误时）
    case notFound(entity: String, id: String)
    /// 数据校验失败（必填字段为空、格式非法等）
    case validationFailed(reason: String)
    /// 持久化失败（SwiftData save / fetch 抛错、磁盘已满、schema migration 失败等）
    /// - Parameter underlying: 原始底层错误（SwiftData / Foundation 等），保留用于诊断
    case persistenceFailed(underlying: Error)
    /// 并发冲突（乐观锁版本不匹配、context 被外部 invalidate 等）
    case conflict(reason: String)
    /// 不支持的操作（如只读 Repository 调用 write 方法）
    case unsupported(operation: String)

    /// 用户可见的错误描述（中文本地化）。
    /// 注意：`persistenceFailed` 的 `underlying` 仅在 Debug 环境暴露完整描述，
    /// 生产环境仅返回通用提示，避免泄露底层错误细节。
    public var errorDescription: String? {
        switch self {
        case .notFound(let entity, let id):
            return String(format: NSLocalizedString("%@（ID=%@）未找到", comment: ""), entity, id)
        case .validationFailed(let reason):
            return String(format: NSLocalizedString("数据校验失败：%@", comment: ""), reason)
        case .persistenceFailed:
            return NSLocalizedString("数据持久化失败，请稍后重试", comment: "")
        case .conflict(let reason):
            return String(format: NSLocalizedString("数据并发冲突：%@", comment: ""), reason)
        case .unsupported(let operation):
            return String(format: NSLocalizedString("不支持的操作：%@", comment: ""), operation)
        }
    }

    /// 诊断描述（含 underlying 信息），用于日志输出，不直接展示给用户。
    /// 调用方在 Logger.error 时应使用此属性而非 errorDescription，以保留底层错误。
    public var diagnosticDescription: String {
        switch self {
        case .notFound(let entity, let id):
            return "RepositoryError.notFound(\(entity), id=\(id))"
        case .validationFailed(let reason):
            return "RepositoryError.validationFailed(\(reason))"
        case .persistenceFailed(let underlying):
            return "RepositoryError.persistenceFailed(underlying: \(type(of: underlying)): \(underlying.localizedDescription))"
        case .conflict(let reason):
            return "RepositoryError.conflict(\(reason))"
        case .unsupported(let operation):
            return "RepositoryError.unsupported(\(operation))"
        }
    }
}

// MARK: - 仓储协议

/// 平台无关的会话仓储协议
///
/// 定义会话的增删改查契约，由各平台提供具体实现（如 SwiftDataConversationRepository）。
/// DTO 用 ConversationDTO，隔离底层持久化模型（如 SwiftData @Model）。
public protocol ConversationRepository: Sendable {
    /// 获取所有会话，按 updated_at 降序
    func fetchAll() async throws -> [ConversationDTO]
    /// 按 id 获取单个会话
    func fetch(id: UUID) async throws -> ConversationDTO?
    /// 保存（创建或更新）会话
    func save(_ conversation: ConversationDTO) async throws
    /// 删除指定会话（级联删除其消息）
    func delete(id: UUID) async throws
    /// 按关键词搜索会话标题和最后消息预览
    func search(query: String) async throws -> [ConversationDTO]
    /// 获取子对话（分叉）
    func fetchChildren(parentId: UUID) async throws -> [ConversationDTO]
}

/// 平台无关的消息仓储协议
///
/// 定义聊天消息的持久化与检索契约。
public protocol MessageRepository: Sendable {
    /// 获取指定会话的所有消息，按时间升序
    func fetchMessages(conversationId: UUID) async throws -> [ChatMessageDTO]
    /// 保存单条消息
    func save(_ message: ChatMessageDTO) async throws
    /// 删除指定会话的所有消息
    func delete(conversationId: UUID) async throws
    /// 删除单条消息
    func delete(messageId: UUID) async throws
    /// 提交消息反馈（-1/0/1）
    func submitFeedback(messageId: UUID, isPositive: Bool?, citations: [String]?) async throws
}

/// 平台无关的记忆仓储协议
///
/// 用于跨会话的长期记忆持久化与检索。检索可基于关键词（简化版）
/// 或向量相似度（未来扩展）。
public protocol MemoryRepository: Sendable {
    /// 获取所有记忆，按重要性降序
    func fetchAll() async throws -> [MemoryDTO]
    /// 保存（创建或更新）记忆
    func save(_ memory: MemoryDTO) async throws
    /// 按关键词搜索相关记忆，按重要性降序，限制数量
    func searchRelevant(query: String, limit: Int) async throws -> [MemoryDTO]
    /// 按 id 删除记忆
    func delete(id: UUID) async throws
}

/// 平台无关的文档仓储协议（用于 RAG 知识库）
///
/// 定义文档分块的索引与检索契约。向量检索可由具体实现
/// 决定（简化版用文本匹配，未来扩展为向量相似度）。
public protocol DocumentRepository: Sendable {
    /// 索引文档分块（批量保存）
    func indexDocument(_ chunks: [DocumentChunkDTO]) async throws
    /// 按关键词搜索文档分块，限制数量
    func search(query: String, limit: Int) async throws -> [DocumentChunkDTO]
    /// 调整分块权重（被赞/被踩时）
    func updateWeight(chunkId: UUID, factor: Float) async throws
    /// 删除指定来源的所有分块
    func deleteBySource(_ source: String) async throws
}
