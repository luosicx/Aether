import Foundation

/// Task 19 阶段 1: 向量存储协议。抽象 ANN 向量索引的建表/插入/查询/删除操作。
///
/// 设计要点：
/// - 不直接依赖 sqlite-vec 二进制，便于运行时降级为 `BruteForceVectorStore`。
/// - 实现需保证线程安全（actor 或串行队列）。
/// - `recall` 返回 top-K 候选，相似度计算基于余弦相似度。
protocol VectorStore: Sendable {
    /// 是否可用（sqlite-vec 加载成功返回 true；降级实现恒为 true）
    /// - Note: 标记为 async 以兼容 actor 实现（actor 属性跨隔离边界访问需 await）
    var isAvailable: Bool { get async }

    /// 建表/初始化存储（幂等）
    func initialize() async throws

    /// 插入或更新一条向量记录
    /// - Parameters:
    ///   - id: 记忆唯一标识
    ///   - embedding: 向量
    ///   - metadata: 元数据（category/importance/createdAt 等，序列化为 JSON 字符串）
    func upsert(id: UUID, embedding: [Double], metadata: [String: String]) async throws

    /// 批量插入
    func upsertBatch(_ records: [(id: UUID, embedding: [Double], metadata: [String: String])]) async throws

    /// ANN 查询：返回 top-K 候选，按相似度降序
    /// - Parameters:
    ///   - query: 查询向量
    ///   - limit: 返回条数上限
    /// - Returns: 候选列表（id / 相似度 / 元数据），未启用或空时返回空数组
    func query(_ query: [Double], limit: Int) async throws -> [VectorSearchResult]

    /// 按指定 id 删除记录（幂等）
    func delete(id: UUID) async throws

    /// 删除所有记录（清空表，保留 schema）
    func deleteAll() async throws

    /// 当前存储记录数
    func count() async throws -> Int
}

/// Task 19 阶段 1: 向量检索单条结果。
struct VectorSearchResult: Sendable, Hashable {
    /// 记忆 ID
    let id: UUID
    /// 余弦相似度 0.0 - 1.0
    let similarity: Double
    /// 元数据
    let metadata: [String: String]

    init(id: UUID, similarity: Double, metadata: [String: String] = [:]) {
        self.id = id
        self.similarity = similarity
        self.metadata = metadata
    }
}

/// Task 19 阶段 1: 向量存储支持的类型。
enum VectorStoreKind: String, Sendable {
    /// sqlite-vec 扩展（性能最佳）
    case sqliteVec
    /// 纯 Swift 暴力扫描（降级方案）
    case bruteForce
}
