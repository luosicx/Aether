import Foundation
#if canImport(os)
import os
#endif

/// Task 19 阶段 1: 向量存储工厂。
///
/// 运行时检测 sqlite-vec 是否可用：若可用返回 `SQLiteVecStore`，否则降级为 `BruteForceVectorStore`。
/// 默认实现：尝试初始化 `SQLiteVecStore`，若 `isAvailable == false` 则降级。
/// 测试可通过 `overrideStore` 注入 mock。
///
/// 线程安全：所有可变状态（cachedStore / overrideStore / kind）均通过 `OSAllocatedUnfairLock`
/// 包装的 State 结构体保护。`store()` async 内部的 await 在锁外执行，避免死锁；
/// 慢速路径的并发初始化可能导致 SQLiteVecStore.initialize() 被多次调用，但该操作幂等无副作用，
/// 最终通过双重检查锁保证首次写入的实例胜出。
final class VectorStoreFactory: @unchecked Sendable {
    /// 单例（App 全局唯一）
    static let shared = VectorStoreFactory()

    /// 所有可变状态的统一容器（受 stateLock 保护）。
    /// State 自身是 Sendable（VectorStore 是 Sendable 协议，VectorStoreKind 是 Sendable enum）。
    private struct State {
        var cachedStore: VectorStore?
        var overrideStore: VectorStore?
        var kind: VectorStoreKind = .bruteForce
    }

    /// 状态锁（OSAllocatedUnfairLock 比 NSLock 更快，且无锁竞争时零开销）
    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// 持有的存储类型（受 stateLock 保护，读取通过快照）
    var kind: VectorStoreKind {
        stateLock.withLock { $0.kind }
    }

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
    ///
    /// - Note: 慢速路径（首次初始化）不持锁，允许并发触发 `SQLiteVecStore.initialize()`；
    ///   多次初始化幂等无副作用，最终通过双重检查锁保证首次写入的实例胜出。
    func store() async -> VectorStore {
        // 快速路径：持锁读取 override / cached
        var fastPathStore: VectorStore?
        stateLock.withLock { state in
            if let override = state.overrideStore {
                fastPathStore = override
            } else if let cached = state.cachedStore {
                fastPathStore = cached
            }
        }
        if let store = fastPathStore {
            return store
        }

        // 慢速路径：初始化（不持锁，避免 await 时死锁）
        let sqliteStore = SQLiteVecStore(dbPath: dbPath)
        let chosen: VectorStore
        let chosenKind: VectorStoreKind
        do {
            try await sqliteStore.initialize()
            if await sqliteStore.isAvailable {
                chosen = sqliteStore
                chosenKind = .sqliteVec
            } else {
                chosen = BruteForceVectorStore()
                chosenKind = .bruteForce
            }
        } catch {
            // 加载异常，降级
            chosen = BruteForceVectorStore()
            chosenKind = .bruteForce
        }

        // 写入缓存（持锁）：双重检查防止重复写入
        // 若其他并发调用已写入 cached，则使用已缓存的实例（首次写入胜出）
        return stateLock.withLock { state -> VectorStore in
            if let cached = state.cachedStore {
                return cached
            }
            state.cachedStore = chosen
            state.kind = chosenKind
            return chosen
        }
    }

    /// 测试用：注入覆盖存储（传 nil 清除覆盖）
    func setOverride(_ store: VectorStore?) {
        stateLock.withLock { state in
            state.overrideStore = store
            state.cachedStore = nil
        }
    }

    /// 重置缓存（测试间清理）
    func reset() {
        stateLock.withLock { state in
            state.cachedStore = nil
            state.overrideStore = nil
            state.kind = .bruteForce
        }
    }
}
