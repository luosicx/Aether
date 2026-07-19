import Foundation
import SwiftData
#if os(iOS)
import BackgroundTasks
#endif

/// Task 19 阶段 3: 老化压缩器。
///
/// 定期（每周）执行老化、归档、压缩三类任务：
/// 1. 老化：90 天未被召回命中的记忆 `importance *= 0.8`（衰减）。
/// 2. 归档：180 天且 `importance < 0.2` 的记忆归档（移除 VectorStore 向量，保留 SwiftData 元数据 + `archivedAt`）。
/// 3. 压缩：同 `category` 中相似度 > 0.92 的记忆合并，保留 `importance` 更高的版本，其余归档。
/// 4. 30 天可恢复窗口：归档未满 30 天的记忆可通过 `restore(memory:)` 恢复。
///
/// 平台策略：
/// - iOS：通过 `BGTaskScheduler` 注册每周后台任务（`BGTaskScheduler.TaskIdentifier`）。
/// - macOS：iOS 框架不可用，使用 `Timer` 每 7 天触发一次（macOS 后台无限制）。
@MainActor
final class AgingCompactor {
    /// 后台任务标识符（iOS）
    static let backgroundTaskIdentifier = "com.aether.memory.aging"

    /// 老化阈值：90 天未命中触发 importance 衰减
    static let agingThresholdSeconds: TimeInterval = 90 * 24 * 60 * 60
    /// 归档阈值：180 天触发归档候选
    static let archiveAgeThresholdSeconds: TimeInterval = 180 * 24 * 60 * 60
    /// 归档 importance 阈值：低于此值才归档
    static let archiveImportanceThreshold: Double = 0.2
    /// 老化衰减因子：每次老化 importance *= 0.8
    static let agingDecayFactor: Double = 0.8
    /// 压缩相似度阈值：超过此值视为重复
    static let compressionSimilarityThreshold: Double = 0.92
    /// 可恢复窗口：归档后 30 天内可恢复
    static let restoreWindowSeconds: TimeInterval = 30 * 24 * 60 * 60
    /// 调度周期（macOS Timer）：7 天
    static let schedulingIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// MemoryService 实例（用于访问 SwiftData 与 VectorStore）
    private let memoryService: MemoryService
    /// 向量存储工厂（用于压缩阶段的相似度计算与归档阶段的向量移除）
    private let vectorStoreFactory: VectorStoreFactory?
    /// macOS Timer 引用（仅 macOS 持有）
    #if !os(iOS)
    private var macOSTimer: Timer?
    #endif

    /// 创建 AgingCompactor 实例
    /// - Parameters:
    ///   - memoryService: MemoryService 实例
    ///   - vectorStoreFactory: 向量存储工厂，nil 时使用单例
    init(memoryService: MemoryService, vectorStoreFactory: VectorStoreFactory? = nil) {
        self.memoryService = memoryService
        self.vectorStoreFactory = vectorStoreFactory
    }

    // MARK: - 调度

    /// 注册后台任务调度。
    /// - iOS：调用 `BGTaskScheduler.register` 注册 perodic 任务，并调用 `scheduleNextRun`。
    /// - macOS：启动 `Timer` 每 `schedulingIntervalSeconds` 触发 `runCycle(now:)`。
    func registerAndSchedule() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.handleBackgroundTask(bgTask)
            }
        }
        scheduleNextIOSRun()
        #else
        startMacOSTimer()
        #endif
    }

    /// 取消调度（用于测试清理或 App 退出）
    func cancelScheduling() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        #else
        macOSTimer?.invalidate()
        macOSTimer = nil
        #endif
    }

    #if os(iOS)
    /// 调度下一次 iOS 后台任务执行（一周后）
    private func scheduleNextIOSRun() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.schedulingIntervalSeconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 调度失败静默降级（App 前台运行时下次启动会重试）
        }
    }

    /// 处理 iOS 后台任务执行
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        let now = Date()
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        do {
            try await runCycle(now: now)
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
        scheduleNextIOSRun()
    }
    #endif

    #if !os(iOS)
    /// 启动 macOS Timer 周期任务
    private func startMacOSTimer() {
        macOSTimer?.invalidate()
        // macOS 后台无限制，使用 Timer 每 7 天触发一次
        let timer = Timer(timeInterval: Self.schedulingIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                _ = try? await self.runCycle(now: Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        macOSTimer = timer
    }
    #endif

    // MARK: - 执行周期

    /// 执行一次完整的老化压缩周期。
    /// 顺序：老化 → 归档 → 压缩。
    /// - Parameter now: 当前时间（便于测试注入）
    /// - Returns: 周期执行结果统计
    func runCycle(now: Date = Date()) async throws -> AgingCompactionResult {
        let agingCount = try applyAging(now: now)
        let archivedCount = try await applyArchival(now: now)
        let compressedCount = try applyCompression(now: now)
        return AgingCompactionResult(
            agedCount: agingCount,
            archivedCount: archivedCount,
            compressedCount: compressedCount,
            runAt: now
        )
    }

    // MARK: - 老化规则

    /// 老化规则：90 天未被召回命中（`lastAccessedAt` 早于 90 天前或 nil 且 `createdAt` 早于 90 天前）的活跃记忆 `importance *= 0.8`。
    /// 用户主动记忆不参与老化（importance 固定 0.8）。
    /// - Parameter now: 当前时间
    /// - Returns: 老化的记忆数
    @discardableResult
    func applyAging(now: Date = Date()) throws -> Int {
        let memories = try memoryService.getAllMemories()
        let threshold = now.addingTimeInterval(-Self.agingThresholdSeconds)
        var count = 0
        for memory in memories {
            // 跳过已归档与用户主动记忆
            if memory.archivedAt != nil { continue }
            if memory.isUserExplicit { continue }
            // 取 lastAccessedAt 或 createdAt 作为最后访问时间
            let lastAccess = memory.lastAccessedAt ?? memory.createdAt
            guard lastAccess < threshold else { continue }
            // 老化衰减
            memory.importance *= Self.agingDecayFactor
            count += 1
        }
        return count
    }

    // MARK: - 归档规则

    /// 归档规则：180 天且 `importance < 0.2` 的记忆归档。
    /// 归档操作：设置 `archivedAt`，从 VectorStore 移除向量（保留 SwiftData 元数据）。
    /// - Parameter now: 当前时间
    /// - Returns: 归档的记忆数
    @discardableResult
    func applyArchival(now: Date = Date()) async throws -> Int {
        let memories = try memoryService.getAllMemories()
        let ageThreshold = now.addingTimeInterval(-Self.archiveAgeThresholdSeconds)
        var count = 0
        for memory in memories {
            // 跳过已归档
            if memory.archivedAt != nil { continue }
            // 用户主动记忆不归档
            if memory.isUserExplicit { continue }
            let lastAccess = memory.lastAccessedAt ?? memory.createdAt
            guard lastAccess < ageThreshold else { continue }
            guard memory.importance < Self.archiveImportanceThreshold else { continue }
            // 执行归档
            memory.archivedAt = now
            // 从 VectorStore 移除向量
            if let factory = vectorStoreFactory {
                let store = await factory.store()
                try? await store.delete(id: memory.id)
            } else {
                let store = await VectorStoreFactory.shared.store()
                try? await store.delete(id: memory.id)
            }
            count += 1
        }
        return count
    }

    // MARK: - 压缩规则

    /// 压缩规则：同 `category` 中相似度 > 0.92 的记忆合并，保留 `importance` 更高的版本，其余归档。
    /// 仅对有 embedding 的活跃记忆执行。
    /// - Parameter now: 当前时间
    /// - Returns: 被压缩（归档）的记忆数
    @discardableResult
    func applyCompression(now: Date = Date()) throws -> Int {
        let memories = try memoryService.getAllMemories()
            .filter { $0.archivedAt == nil && !$0.embedding.isEmpty }
        // 按 category 分组
        let grouped = Dictionary(grouping: memories, by: { $0.category })
        var compressedCount = 0
        for (_, group) in grouped {
            compressedCount += compressGroup(group, now: now)
        }
        return compressedCount
    }

    /// 压缩单个 category 分组：两两计算相似度，超过阈值的合并。
    private func compressGroup(_ group: [Memory], now: Date) -> Int {
        var count = 0
        // 按 importance 降序，保留 importance 高的版本
        let sorted = group.sorted { $0.importance > $1.importance }
        var kept: [Memory] = []
        for candidate in sorted {
            var isDuplicate = false
            for keptMemory in kept {
                let sim = BruteForceVectorStore.cosineSimilarity(candidate.embedding, keptMemory.embedding)
                if sim > Self.compressionSimilarityThreshold {
                    isDuplicate = true
                    break
                }
            }
            if isDuplicate {
                // 归档重复项（保留 importance 更高的版本）
                candidate.archivedAt = now
                count += 1
            } else {
                kept.append(candidate)
            }
        }
        return count
    }

    // MARK: - 恢复

    /// 恢复归档记忆（30 天可恢复窗口内）。
    /// - Parameters:
    ///   - memory: 待恢复的记忆
    ///   - now: 当前时间（便于测试注入）
    /// - Returns: 是否恢复成功（超时返回 false）
    @discardableResult
    func restore(memory: Memory, now: Date = Date()) async throws -> Bool {
        guard let archivedAt = memory.archivedAt else { return false }
        // 检查 30 天可恢复窗口
        let elapsed = now.timeIntervalSince(archivedAt)
        guard elapsed <= Self.restoreWindowSeconds else { return false }
        // 恢复：清除 archivedAt，重新写入 VectorStore
        memory.archivedAt = nil
        // 重新写入向量
        let store: VectorStore
        if let factory = vectorStoreFactory {
            store = await factory.store()
        } else {
            store = await VectorStoreFactory.shared.store()
        }
        let metadata: [String: String] = [
            "category": memory.category,
            "importance": String(memory.importance),
            "createdAt": String(memory.createdAt.timeIntervalSince1970),
            "content": memory.content
        ]
        try? await store.upsert(id: memory.id, embedding: memory.embedding, metadata: metadata)
        return true
    }
}

/// Task 19 阶段 3: 老化压缩周期执行结果。
struct AgingCompactionResult: Sendable {
    /// 老化的记忆数
    let agedCount: Int
    /// 归档的记忆数
    let archivedCount: Int
    /// 压缩（合并后归档）的记忆数
    let compressedCount: Int
    /// 执行时间
    let runAt: Date

    /// 总影响记忆数
    var totalAffected: Int {
        agedCount + archivedCount + compressedCount
    }
}
