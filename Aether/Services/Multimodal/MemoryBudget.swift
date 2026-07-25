import Foundation

/// v1.3: 全局内存预算器。
///
/// 统一调度 VLM / Whisper / SD / VoiceCloner 等多模态引擎的内存占用，
/// 避免并发加载多个模型导致 OOM 崩溃。
///
/// 设计参考 MASTER_PLAN §6.5 风险点：
/// > v1.3 同期交付内存预算器，统一调度
///
/// 工作原理：
/// 1. 初始化时按设备能力设置总预算（如 iPhone 15 Pro 3000MB）
/// 2. 引擎加载模型前调用 `reserve(mb:)` 申请内存
/// 3. 引擎卸载模型后调用 `release(mb:)` 释放内存
/// 4. 申请超过剩余额度时抛 `MultimodalError.memoryBudgetExceeded`
public actor MemoryBudget {
    /// 单例
    public static let shared = MemoryBudget()

    /// 总预算（MB），按设备能力自动设置
    private let totalBudgetMB: Int

    /// 已用预算（MB）
    private var usedBudgetMB: Int = 0

    /// 历史峰值（MB，用于诊断）
    private var peakBudgetMB: Int = 0

    public init() {
        self.totalBudgetMB = DeviceCapability.current.recommendedMemoryBudgetMB
    }

    /// 测试可注入的初始化器
    /// - Parameter totalBudgetMB: 总预算（MB）
    public init(totalBudgetMB: Int) {
        self.totalBudgetMB = totalBudgetMB
    }

    /// 总预算（MB）
    public var total: Int { totalBudgetMB }

    /// 已用预算（MB）
    public var used: Int { usedBudgetMB }

    /// 剩余预算（MB）
    public var available: Int {
        max(0, totalBudgetMB - usedBudgetMB)
    }

    /// 历史峰值（MB）
    public var peak: Int { peakBudgetMB }

    /// 申请内存
    /// - Parameter mb: 申请的内存大小（MB）
    /// - Returns: 申请成功后剩余可用内存（MB）
    /// - Throws: `MultimodalError.memoryBudgetExceeded` 当申请超过剩余额度
    public func reserve(mb: Int) async throws -> Int {
        guard mb > 0 else {
            throw MultimodalError.memoryBudgetExceeded(requestedMB: mb, availableMB: available)
        }
        guard mb <= available else {
            throw MultimodalError.memoryBudgetExceeded(requestedMB: mb, availableMB: available)
        }
        usedBudgetMB += mb
        if usedBudgetMB > peakBudgetMB {
            peakBudgetMB = usedBudgetMB
        }
        return available
    }

    /// 释放内存
    /// - Parameter mb: 释放的内存大小（MB）
    /// - Returns: 释放后剩余可用内存（MB）
    public func release(mb: Int) async -> Int {
        usedBudgetMB = max(0, usedBudgetMB - mb)
        return available
    }

    /// 重置（释放所有已申请内存，仅测试用）
    public func reset() async {
        usedBudgetMB = 0
        peakBudgetMB = 0
    }

    /// 当前预算状态快照（用于 UI 展示与日志诊断）
    public func snapshot() async -> BudgetSnapshot {
        BudgetSnapshot(
            totalMB: totalBudgetMB,
            usedMB: usedBudgetMB,
            availableMB: available,
            peakMB: peakBudgetMB,
            utilization: totalBudgetMB > 0 ? Double(usedBudgetMB) / Double(totalBudgetMB) : 0
        )
    }
}

/// v1.3: 内存预算状态快照
public struct BudgetSnapshot: Sendable, Equatable {
    /// 总预算（MB）
    public let totalMB: Int
    /// 已用（MB）
    public let usedMB: Int
    /// 剩余（MB）
    public let availableMB: Int
    /// 峰值（MB）
    public let peakMB: Int
    /// 利用率（0.0 - 1.0）
    public let utilization: Double

    /// 利用率百分比（0-100，保留 1 位小数）
    public var utilizationPercentage: Double {
        round(utilization * 1000) / 10
    }
}
