import Foundation

/// Day 19: 性能监控，记录关键操作耗时（毫秒）。
/// 用 actor 保证并发安全，通过 `measure` 包装异步操作并自动计时。
actor PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private init() {}

    /// 各指标耗时（毫秒）
    private var metrics: [String: Double] = [:]

    /// 测量异步操作耗时并记录。block 抛错时不记录指标，错误继续向上抛出。
    func measure<T>(_ name: String, _ block: () async throws -> T) async rethrows -> T {
        let start = Date()
        let result = try await block()
        let elapsed = Date().timeIntervalSince(start) * 1000
        metrics[name] = elapsed
        return result
    }

    /// 读取所有指标
    func getMetrics() -> [String: Double] {
        metrics
    }

    /// 清除所有指标
    func clear() {
        metrics.removeAll()
    }
}
