import Foundation

/// Task 19 阶段 1: 向量存储工厂。
///
/// 运行时检测 sqlite-vec 是否可用：若可用返回 `SQLiteVecStore`，否则降级为 `BruteForceVectorStore`。
/// 默认实现：尝试初始化 `SQLiteVecStore`，若 `isAvailable == false` 则降级。
/// 测试可通过 `overrideStore` 注入 mock。
final class VectorStoreFactory: @unchecked Sendable {
    /// 单例（App 全局唯一）
    static let shared = VectorStoreFactory()

    /// 持有的存储实例（lazy 初始化）
    private var cachedStore: VectorStore?
    /// 持有的存储类型
    private(set) var kind: VectorStoreKind = .bruteForce
    /// 用于测试注入的覆盖存储
    private var overrideStore: VectorStore?

    /// sqlite-vec 数据库文件路径（位于 App Group 容器；CI 环境通常不可加载扩展）
    private let dbPath: String

    /// 默认初始化（路径取 App Support 目录下的 aether_vec.db）
    init(dbPath: String? = nil) {
        if let path = dbPath {
            self.dbPath = path
        } else {
            // 默认路径：App Support / aether_vec.db
            let supportDir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?.path ?? NSTemporaryDirectory()
            self.dbPath = (supportDir as NSString).appendingPathComponent("aether_vec.db")
        }
    }

    /// 获取当前可用的 VectorStore（首次调用时自动选择并缓存）。
    /// 优先使用 `SQLiteVecStore`，加载失败降级为 `BruteForceVectorStore`。
    /// 测试可通过 `setOverride(_:)` 注入 mock 直接返回。
    func store() async -> VectorStore {
        if let override = overrideStore {
            return override
        }
        if let cached = cachedStore {
            return cached
        }
        let sqliteStore = SQLiteVecStore(dbPath: dbPath)
        do {
            try await sqliteStore.initialize()
            if await sqliteStore.isAvailable {
                cachedStore = sqliteStore
                kind = .sqliteVec
                return sqliteStore
            }
        } catch {
            // 加载异常，降级
        }
        let fallback = BruteForceVectorStore()
        cachedStore = fallback
        kind = .bruteForce
        return fallback
    }

    /// 测试用：注入覆盖存储（传 nil 清除覆盖）
    func setOverride(_ store: VectorStore?) {
        overrideStore = store
        cachedStore = nil
    }

    /// 重置缓存（测试间清理）
    func reset() {
        cachedStore = nil
        overrideStore = nil
        kind = .bruteForce
    }
}
