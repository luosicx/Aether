#if os(iOS)
import Foundation
import HealthKit
import os
import AetherServices

/// Day 17: 一天的健康数据聚合摘要，供 HealthInsightGenerator 与 ChatViewModel 注入上下文使用。
struct HealthDailySummary: Codable, Sendable {
    /// 睡眠时长（小时）
    var sleepHours: Double
    /// 平均心率（bpm）
    var avgHeartRate: Double
    /// 步数
    var stepCount: Int
}

/// Day 17: HealthKit 相关错误类型
enum HealthKitError: LocalizedError, Sendable {
    /// 设备不支持 HealthKit（HKHealthStore.isHealthDataAvailable() 返回 false）
    case notAvailable
    /// 用户未授权或授权被拒绝
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return NSLocalizedString("当前设备不支持 HealthKit", comment: "")
        case .notAuthorized:
            return NSLocalizedString("未获得 HealthKit 授权", comment: "")
        }
    }
}

/// Day 17: 封装 HealthKit 数据读取，提供心率、睡眠、步数的按天聚合查询。
///
/// 设计要点：
/// - 用 `HKHealthStore.isHealthDataAvailable()` 判断是否可用，模拟器上可能为 true 但无数据
/// - 未授权时所有查询返回空数据（不抛错），便于上层优雅降级
/// - `fetchDailySummary()` 聚合最近 1 天数据为 `HealthDailySummary`
/// - 类标记 `@unchecked Sendable`：HKHealthStore 本身线程安全，isAuthorized 用 OSAllocatedUnfairLock 保护（async 安全）
final class HealthKitService: HealthDataSource, @unchecked Sendable {
    /// HealthKit 存储，设备不支持时为 nil
    private let healthStore: HKHealthStore?
    /// 授权状态锁，async 安全的 OSAllocatedUnfairLock
    private let isAuthorizedLock = OSAllocatedUnfairLock(initialState: false)

    /// 当前授权状态（线程安全读取）
    var isAuthorized: Bool {
        isAuthorizedLock.withLock { $0 }
    }

    init() {
        healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    /// 请求 HealthKit 读取授权（心率 / 睡眠 / 步数）。设备不支持时抛 `.notAvailable`。
    func requestAuthorization() async throws {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        let heartRateType = HKQuantityType(.heartRate)
        let sleepType = HKCategoryType(.sleepAnalysis)
        let stepCountType = HKQuantityType(.stepCount)
        let typesToRead: Set<HKObjectType> = [heartRateType, sleepType, stepCountType]
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
        isAuthorizedLock.withLock { $0 = true }
    }

    /// 按天聚合心率均值。未授权返回空字典。
    /// - Parameter days: 查询最近天数
    /// - Returns: [日期: 当天平均心率]，无数据日期不出现
    func fetchHeartRate(days: Int) async throws -> [Date: Double] {
        guard let healthStore = healthStore, isAuthorized else { return [:] }
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: now) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)

        // 按天聚合，使用 HKStatisticsCollectionQuery
        let interval = DateComponents(day: 1)
        let anchorDate = calendar.startOfDay(for: now)
        let quantityType = HKQuantityType(.heartRate)
        // 心率单位 = count / minute（bpm）
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: Self.averageByDay(results, from: startDate, to: now, unit: unit, calendar: calendar))
            }
            healthStore.execute(query)
        }
    }

    /// 统计集合按天取均值，无数据日期不出现。
    private static func averageByDay(
        _ statistics: HKStatisticsCollection?,
        from startDate: Date,
        to endDate: Date,
        unit: HKUnit,
        calendar: Calendar
    ) -> [Date: Double] {
        var result: [Date: Double] = [:]
        statistics?.enumerateStatistics(from: startDate, to: endDate) { stat, _ in
            if let quantity = stat.averageQuantity()?.doubleValue(for: unit) {
                result[calendar.startOfDay(for: stat.startDate)] = quantity
            }
        }
        return result
    }

    /// 按天聚合睡眠时长（小时）。未授权返回空字典。
    /// - Parameter days: 查询最近天数
    /// - Returns: [日期: 当天睡眠小时数]
    func fetchSleepAnalysis(days: Int) async throws -> [Date: Double] {
        guard let healthStore = healthStore, isAuthorized else { return [:] }
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: now) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sleepType = HKCategoryType(.sleepAnalysis)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: Self.sleepHoursByDay(samples, calendar: calendar))
            }
            healthStore.execute(query)
        }
    }

    /// 累计每天的 asleep 类别样本时长（秒 → 小时）。
    private static func sleepHoursByDay(_ samples: [HKSample]?, calendar: Calendar) -> [Date: Double] {
        var dailySeconds: [Date: TimeInterval] = [:]
        // 只累计 asleep 类别的样本（asleep / asleepDeep / asleepCore / asleepREM / asleepUnspecified）
        if let categorySamples = samples as? [HKCategorySample] {
            for sample in categorySamples {
                let isAsleep: Bool
                if let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    switch value {
                    case .asleep, .asleepDeep, .asleepCore, .asleepREM, .asleepUnspecified:
                        isAsleep = true
                    default:
                        isAsleep = false
                    }
                } else {
                    isAsleep = false
                }
                guard isAsleep else { continue }
                let day = calendar.startOfDay(for: sample.startDate)
                dailySeconds[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
            }
        }
        return dailySeconds.mapValues { $0 / 3600.0 }
    }

    /// 按天聚合步数总和。未授权返回空字典。
    /// - Parameter days: 查询最近天数
    /// - Returns: [日期: 当天步数]
    func fetchStepCount(days: Int) async throws -> [Date: Int] {
        guard let healthStore = healthStore, isAuthorized else { return [:] }
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: now) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)

        let interval = DateComponents(day: 1)
        let anchorDate = calendar.startOfDay(for: now)
        let quantityType = HKQuantityType(.stepCount)
        let unit = HKUnit.count()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: Self.sumByDay(results, from: startDate, to: now, unit: unit, calendar: calendar))
            }
            healthStore.execute(query)
        }
    }

    /// 统计集合按天求和，无数据日期不出现。
    private static func sumByDay(
        _ statistics: HKStatisticsCollection?,
        from startDate: Date,
        to endDate: Date,
        unit: HKUnit,
        calendar: Calendar
    ) -> [Date: Int] {
        var result: [Date: Int] = [:]
        statistics?.enumerateStatistics(from: startDate, to: endDate) { stat, _ in
            if let quantity = stat.sumQuantity()?.doubleValue(for: unit) {
                result[calendar.startOfDay(for: stat.startDate)] = Int(quantity)
            }
        }
        return result
    }

    /// 聚合最近 1 天的健康数据为 HealthDailySummary。未授权或无数据时返回全零摘要。
    func fetchDailySummary() async throws -> HealthDailySummary {
        // 未授权或设备不支持时直接返回全零摘要（不抛错）
        guard healthStore != nil, isAuthorized else {
            return HealthDailySummary(sleepHours: 0, avgHeartRate: 0, stepCount: 0)
        }
        let heartRate = (try? await fetchHeartRate(days: 1)) ?? [:]
        let sleep = (try? await fetchSleepAnalysis(days: 1)) ?? [:]
        let steps = (try? await fetchStepCount(days: 1)) ?? [:]

        let avgHR = heartRate.isEmpty ? 0.0 : heartRate.values.reduce(0, +) / Double(heartRate.count)
        let totalSleep = sleep.values.reduce(0, +)
        let totalSteps = steps.values.reduce(0, +)

        return HealthDailySummary(
            sleepHours: totalSleep,
            avgHeartRate: avgHR,
            stepCount: totalSteps
        )
    }
}
#endif
