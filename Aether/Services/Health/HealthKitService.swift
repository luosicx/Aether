#if os(iOS)
import Foundation
import HealthKit
import os

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
final class HealthKitService: @unchecked Sendable {
    /// HealthKit 存储，设备不支持时为 nil；测试可注入 mock store
    private let healthStore: HKHealthStore?
    /// 授权状态锁，async 安全的 OSAllocatedUnfairLock
    private let isAuthorizedLock = OSAllocatedUnfairLock(initialState: false)

    /// 当前授权状态（线程安全读取）
    var isAuthorized: Bool {
        isAuthorizedLock.withLock { $0 }
    }

    init(healthStore: HKHealthStore? = nil) {
        self.healthStore = healthStore ?? (HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil)
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
        // 修正：requestAuthorization 不返回用户是否同意，必须查询各 type 的实际授权状态。
        // 只有所有请求的读取类型都被授权时，才将 isAuthorized 设为 true；否则保持 false。
        let allAuthorized = typesToRead.allSatisfy {
            healthStore.authorizationStatus(for: $0) == .sharingAuthorized
        }
        isAuthorizedLock.withLock { $0 = allAuthorized }
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
                var result: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: now, with: { stat, _ in
                    if let quantity = stat.averageQuantity()?.doubleValue(for: unit) {
                        result[calendar.startOfDay(for: stat.startDate)] = quantity
                    }
                })
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
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
                var dailySeconds: [Date: TimeInterval] = [:]
                // 睡眠类别样本：仅累计 asleep 类别（HKCategoryValueSleepAnalysis.asleep / .asleepDeep / .asleepCore / .asleepREM / .asleepUnspecified）
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
                // 秒 → 小时
                let result = dailySeconds.mapValues { $0 / 3600.0 }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
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
                var result: [Date: Int] = [:]
                results?.enumerateStatistics(from: startDate, to: now, with: { stat, _ in
                    if let quantity = stat.sumQuantity()?.doubleValue(for: unit) {
                        result[calendar.startOfDay(for: stat.startDate)] = Int(quantity)
                    }
                })
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
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
