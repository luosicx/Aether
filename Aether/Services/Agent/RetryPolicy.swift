import Foundation

/// Task 20 阶段 3: 重试策略（指数退避）。
///
/// 配置：
/// - `maxAttempts`：最大尝试次数（默认 3）
/// - `initialDelay`：首次重试前延迟（默认 1s）
/// - `backoffMultiplier`：退避倍数（默认 2.0）
///
/// 退避序列（默认）：1s → 2s → 4s（共 3 次重试）
///
/// 用尽后由 `DAGExecutionEngine` 标记节点为 failed 并触发用户干预。
struct RetryPolicy: Sendable {
    /// 最大尝试次数（含首次执行）
    let maxAttempts: Int
    /// 首次重试前延迟（秒）
    let initialDelay: TimeInterval
    /// 退避倍数
    let backoffMultiplier: Double

    /// 创建 RetryPolicy
    /// - Parameters:
    ///   - maxAttempts: 最大尝试次数，默认 3
    ///   - initialDelay: 首次重试前延迟（秒），默认 1.0
    ///   - backoffMultiplier: 退避倍数，默认 2.0
    init(maxAttempts: Int = 3, initialDelay: TimeInterval = 1.0, backoffMultiplier: Double = 2.0) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelay = max(0, initialDelay)
        self.backoffMultiplier = max(1.0, backoffMultiplier)
    }

    /// 默认策略：3 次尝试，1s/2s/4s 退避
    static let `default` = RetryPolicy()

    /// 计算第 N 次失败后的退避延迟（秒）
    /// - Parameter attempt: 失败的尝试序号（0 表示首次失败，1 表示第二次失败，以此类推）
    /// - Returns: 重试前应等待的秒数；返回 0 表示无需等待
    func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return 0 }
        // attempt 0 → initialDelay * multiplier^0 = initialDelay
        // attempt 1 → initialDelay * multiplier^1 = initialDelay * multiplier
        // attempt 2 → initialDelay * multiplier^2
        return initialDelay * pow(backoffMultiplier, Double(attempt))
    }

    /// 计算完整退避序列（用于审计与测试）
    /// - Returns: 退避延迟数组，长度为 `maxAttempts - 1`（最后一次失败后不再等待）
    func backoffSequence() -> [TimeInterval] {
        guard maxAttempts > 1 else { return [] }
        return (0..<(maxAttempts - 1)).map { delay(forAttempt: $0) }
    }

    /// 是否还有重试机会
    /// - Parameter currentAttempt: 当前尝试序号（0-based）
    /// - Returns: true 表示可以继续重试
    func canRetry(afterAttempt currentAttempt: Int) -> Bool {
        currentAttempt + 1 < maxAttempts
    }
}
