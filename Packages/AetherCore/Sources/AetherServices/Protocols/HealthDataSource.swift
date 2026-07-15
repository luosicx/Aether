import Foundation

/// Task 2.4: 平台无关的健康数据源协议。解耦 HealthInsightGenerator 对 HealthKit 的直接依赖。
/// iOS 通过 HealthKitAdapter 实现，macOS 注入 nil（无健康数据）。
public protocol HealthDataSource: Sendable {
    /// 按天聚合心率均值
    /// - Parameter days: 查询最近天数
    /// - Returns: [日期: 当天平均心率]，无数据日期不出现
    func fetchHeartRate(days: Int) async throws -> [Date: Double]

    /// 按天聚合睡眠时长（小时）
    /// - Parameter days: 查询最近天数
    /// - Returns: [日期: 当天睡眠小时数]
    func fetchSleepAnalysis(days: Int) async throws -> [Date: Double]

    /// 按天聚合步数总和
    /// - Parameter days: 查询最近天数
    /// - Returns: [日期: 当天步数]
    func fetchStepCount(days: Int) async throws -> [Date: Int]
}
