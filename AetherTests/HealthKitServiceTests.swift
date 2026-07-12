#if os(iOS)
import XCTest
@testable import Aether

/// Day 17: HealthKitService 单元测试
///
/// 注意：HealthKit 在模拟器上可能可用但无实际数据，测试用例需容忍这种情况。
/// 需要真实数据的断言用 XCTSkip 跳过。
final class HealthKitServiceTests: XCTestCase {

    /// 测试 1: HealthKitService 初始化后 isAuthorized == false
    func testIsAuthorizedInitialFalse() {
        let service = HealthKitService()
        XCTAssertFalse(service.isAuthorized, "新实例的 isAuthorized 应为 false")
    }

    /// 测试 2: 未授权时 fetchHeartRate 返回空字典
    func testFetchHeartRateReturnsEmptyWhenNotAuthorized() async throws {
        let service = HealthKitService()
        // 未调用 requestAuthorization，isAuthorized 应为 false
        XCTAssertFalse(service.isAuthorized)
        let result = try await service.fetchHeartRate(days: 7)
        XCTAssertTrue(result.isEmpty, "未授权时 fetchHeartRate 应返回空字典")
    }

    /// 测试 3: fetchDailySummary 返回的 HealthDailySummary 字段结构正确
    func testFetchDailySummaryStructure() async throws {
        let service = HealthKitService()
        // 未授权时返回全零摘要，验证字段结构存在
        let summary = try await service.fetchDailySummary()
        // 验证三个字段都存在（值为 0 或实际数据）
        _ = summary.sleepHours
        _ = summary.avgHeartRate
        _ = summary.stepCount
        // 未授权时应为全零
        if !service.isAuthorized {
            XCTAssertEqual(summary.sleepHours, 0, "未授权时 sleepHours 应为 0")
            XCTAssertEqual(summary.avgHeartRate, 0, "未授权时 avgHeartRate 应为 0")
            XCTAssertEqual(summary.stepCount, 0, "未授权时 stepCount 应为 0")
        }
    }

    /// 测试 4: 模拟授权失败（模拟器无 HealthKit），验证抛错或 isAuthorized 保持 false
    func testRequestAuthorizationFailure() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "跳过：CI 环境无法处理 HealthKit 权限弹窗")
        let service = HealthKitService()
        do {
            try await service.requestAuthorization()
            // 若成功授权（真机或支持 HealthKit 的环境），isAuthorized 应为 true
            XCTAssertTrue(service.isAuthorized, "授权成功后 isAuthorized 应为 true")
        } catch {
            // 授权失败（模拟器无 HealthKit 或用户拒绝），isAuthorized 应保持 false
            XCTAssertFalse(service.isAuthorized, "授权失败时 isAuthorized 应保持 false")
        }
    }

    // MARK: - HealthKitError 枚举

    /// HealthKitError.notAvailable 应提供非空用户友好描述
    /// 注：使用 NSLocalizedString，CI 英文环境下返回英文文案，不断言中文关键词
    func testHealthKitErrorNotAvailableDescription() {
        let error = HealthKitError.notAvailable
        XCTAssertNotNil(error.errorDescription, "notAvailable 的 errorDescription 不应为 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty == true,
                      "notAvailable 的 errorDescription 不应为空")
    }

    /// HealthKitError.notAuthorized 应提供非空用户友好描述
    /// 注：使用 NSLocalizedString，CI 英文环境下返回英文文案，不断言中文关键词
    func testHealthKitErrorNotAuthorizedDescription() {
        let error = HealthKitError.notAuthorized
        XCTAssertNotNil(error.errorDescription, "notAuthorized 的 errorDescription 不应为 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty == true,
                      "notAuthorized 的 errorDescription 不应为空")
    }

    // MARK: - HealthDailySummary

    /// HealthDailySummary 应支持 Codable 编解码往返
    func testHealthDailySummaryCodableRoundTrip() throws {
        let original = HealthDailySummary(sleepHours: 7.5, avgHeartRate: 72.0, stepCount: 8500)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthDailySummary.self, from: data)

        XCTAssertEqual(decoded.sleepHours, 7.5, accuracy: 0.001, "编解码后 sleepHours 应一致")
        XCTAssertEqual(decoded.avgHeartRate, 72.0, accuracy: 0.001, "编解码后 avgHeartRate 应一致")
        XCTAssertEqual(decoded.stepCount, 8500, "编解码后 stepCount 应一致")
    }

    /// HealthDailySummary 默认值应为全零
    func testHealthDailySummaryDefaultValues() {
        let summary = HealthDailySummary(sleepHours: 0, avgHeartRate: 0, stepCount: 0)
        XCTAssertEqual(summary.sleepHours, 0, "默认 sleepHours 应为 0")
        XCTAssertEqual(summary.avgHeartRate, 0, "默认 avgHeartRate 应为 0")
        XCTAssertEqual(summary.stepCount, 0, "默认 stepCount 应为 0")
    }

    // MARK: - 空数据降级

    /// 未授权时 fetchSleepAnalysis 应返回空字典
    func testFetchSleepAnalysisReturnsEmptyWhenNotAuthorized() async throws {
        let service = HealthKitService()
        XCTAssertFalse(service.isAuthorized, "未授权时 isAuthorized 应为 false")
        let result = try await service.fetchSleepAnalysis(days: 7)
        XCTAssertTrue(result.isEmpty, "未授权时 fetchSleepAnalysis 应返回空字典")
    }

    /// 未授权时 fetchStepCount 应返回空字典
    func testFetchStepCountReturnsEmptyWhenNotAuthorized() async throws {
        let service = HealthKitService()
        XCTAssertFalse(service.isAuthorized, "未授权时 isAuthorized 应为 false")
        let result = try await service.fetchStepCount(days: 7)
        XCTAssertTrue(result.isEmpty, "未授权时 fetchStepCount 应返回空字典")
    }

    /// fetchHeartRate days=0 应不崩溃（边界值）
    func testFetchHeartRateDaysZeroDoesNotCrash() async throws {
        let service = HealthKitService()
        // 未授权时直接返回空字典，days=0 不影响
        let result = try await service.fetchHeartRate(days: 0)
        XCTAssertTrue(result.isEmpty, "未授权时 days=0 也应返回空字典")
    }

    /// fetchStepCount days=1 应不崩溃（边界值）
    func testFetchStepCountDaysOneDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchStepCount(days: 1)
        XCTAssertTrue(result.isEmpty, "未授权时 days=1 也应返回空字典")
    }

    /// fetchSleepAnalysis days=0 应不崩溃（边界值）
    func testFetchSleepAnalysisDaysZeroDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchSleepAnalysis(days: 0)
        XCTAssertTrue(result.isEmpty, "未授权时 days=0 也应返回空字典")
    }

    /// fetchDailySummary 未授权时应返回全零 HealthDailySummary
    func testFetchDailySummaryReturnsZeroWhenNotAuthorized() async throws {
        let service = HealthKitService()
        XCTAssertFalse(service.isAuthorized, "未授权时 isAuthorized 应为 false")

        let summary = try await service.fetchDailySummary()

        XCTAssertEqual(summary.sleepHours, 0, "未授权时 sleepHours 应为 0")
        XCTAssertEqual(summary.avgHeartRate, 0, "未授权时 avgHeartRate 应为 0")
        XCTAssertEqual(summary.stepCount, 0, "未授权时 stepCount 应为 0")
    }

    /// 多次 fetchDailySummary 应稳定返回（验证无状态泄漏）
    func testFetchDailySummaryMultipleCallsStable() async throws {
        let service = HealthKitService()

        let summary1 = try await service.fetchDailySummary()
        let summary2 = try await service.fetchDailySummary()

        XCTAssertEqual(summary1.sleepHours, summary2.sleepHours, "多次调用 sleepHours 应一致")
        XCTAssertEqual(summary1.avgHeartRate, summary2.avgHeartRate, "多次调用 avgHeartRate 应一致")
        XCTAssertEqual(summary1.stepCount, summary2.stepCount, "多次调用 stepCount 应一致")
    }

    /// 多个 HealthKitService 实例应独立（isAuthorized 不共享）
    func testMultipleInstancesIndependentAuthorization() {
        let service1 = HealthKitService()
        let service2 = HealthKitService()
        XCTAssertFalse(service1.isAuthorized)
        XCTAssertFalse(service2.isAuthorized)
        // 两个实例的 isAuthorized 应各自独立
        XCTAssertEqual(service1.isAuthorized, service2.isAuthorized,
                       "两个新实例的 isAuthorized 应都为 false")
    }

    // MARK: - HealthDailySummary 进阶 Codable 测试

    /// HealthDailySummary 编码应产生预期的 JSON 结构（键名正确）
    func testHealthDailySummaryEncodingStructure() throws {
        let summary = HealthDailySummary(sleepHours: 8.0, avgHeartRate: 65.5, stepCount: 10000)
        let data = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json, "编码后应为有效 JSON")
        XCTAssertEqual(json?["sleepHours"] as? Double, 8.0, "sleepHours 键应正确编码")
        XCTAssertEqual(json?["avgHeartRate"] as? Double, 65.5, "avgHeartRate 键应正确编码")
        XCTAssertEqual(json?["stepCount"] as? Int, 10000, "stepCount 键应正确编码")
    }

    /// HealthDailySummary 应支持负值（异常数据情况）
    func testHealthDailySummaryNegativeValues() throws {
        let summary = HealthDailySummary(sleepHours: -1.0, avgHeartRate: -50.0, stepCount: -100)
        XCTAssertEqual(summary.sleepHours, -1.0, accuracy: 0.001)
        XCTAssertEqual(summary.avgHeartRate, -50.0, accuracy: 0.001)
        XCTAssertEqual(summary.stepCount, -100)

        // 负值也应可编解码
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(HealthDailySummary.self, from: data)
        XCTAssertEqual(decoded.sleepHours, -1.0, accuracy: 0.001)
        XCTAssertEqual(decoded.stepCount, -100)
    }

    /// HealthDailySummary 应支持极大值编解码
    func testHealthDailySummaryLargeValues() throws {
        let summary = HealthDailySummary(
            sleepHours: 1e15,
            avgHeartRate: 1e10,
            stepCount: Int.max
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(HealthDailySummary.self, from: data)
        XCTAssertEqual(decoded.sleepHours, 1e15, accuracy: 1.0)
        XCTAssertEqual(decoded.avgHeartRate, 1e10, accuracy: 1.0)
        XCTAssertEqual(decoded.stepCount, Int.max)
    }

    /// HealthDailySummary 应保留小数精度
    func testHealthDailySummaryDecimalPrecision() throws {
        let summary = HealthDailySummary(sleepHours: 7.123456789, avgHeartRate: 72.5, stepCount: 8500)
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(HealthDailySummary.self, from: data)
        XCTAssertEqual(decoded.sleepHours, 7.123456789, accuracy: 0.000000001)
        XCTAssertEqual(decoded.avgHeartRate, 72.5, accuracy: 0.001)
    }

    /// HealthDailySummary Codable 应容忍 JSON 中的额外字段
    func testHealthDailySummaryCodableToleratesExtraFields() throws {
        let json = """
        {"sleepHours": 6.5, "avgHeartRate": 70.0, "stepCount": 5000, "extraField": "ignored"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HealthDailySummary.self, from: data)
        XCTAssertEqual(decoded.sleepHours, 6.5, accuracy: 0.001)
        XCTAssertEqual(decoded.avgHeartRate, 70.0, accuracy: 0.001)
        XCTAssertEqual(decoded.stepCount, 5000)
    }

    /// HealthDailySummary 作为值类型应支持独立拷贝
    func testHealthDailySummaryValueSemantics() {
        var summary1 = HealthDailySummary(sleepHours: 8.0, avgHeartRate: 70.0, stepCount: 10000)
        let summary2 = summary1

        summary1.sleepHours = 5.0
        summary1.stepCount = 5000

        // 值类型：修改 summary1 不影响 summary2
        XCTAssertEqual(summary2.sleepHours, 8.0, "值类型拷贝应独立")
        XCTAssertEqual(summary2.stepCount, 10000, "值类型拷贝应独立")
        XCTAssertEqual(summary1.sleepHours, 5.0, "原值应被修改")
    }

    /// HealthDailySummary 各字段可独立修改
    func testHealthDailySummaryFieldMutation() {
        var summary = HealthDailySummary(sleepHours: 0, avgHeartRate: 0, stepCount: 0)
        summary.sleepHours = 6.5
        summary.avgHeartRate = 68.0
        summary.stepCount = 7500

        XCTAssertEqual(summary.sleepHours, 6.5, accuracy: 0.001)
        XCTAssertEqual(summary.avgHeartRate, 68.0, accuracy: 0.001)
        XCTAssertEqual(summary.stepCount, 7500)
    }

    /// HealthDailySummary 数组应支持 map/filter/reduce 操作
    func testHealthDailySummaryArrayOperations() {
        let summaries = [
            HealthDailySummary(sleepHours: 8.0, avgHeartRate: 70.0, stepCount: 10000),
            HealthDailySummary(sleepHours: 6.0, avgHeartRate: 75.0, stepCount: 8000),
            HealthDailySummary(sleepHours: 7.0, avgHeartRate: 68.0, stepCount: 9000),
        ]

        let avgSleep = summaries.map { $0.sleepHours }.reduce(0, +) / Double(summaries.count)
        XCTAssertEqual(avgSleep, 7.0, accuracy: 0.001, "平均睡眠应为 7.0 小时")

        let totalSteps = summaries.map { $0.stepCount }.reduce(0, +)
        XCTAssertEqual(totalSteps, 27000, "总步数应为 27000")

        let highHR = summaries.filter { $0.avgHeartRate > 72.0 }
        XCTAssertEqual(highHR.count, 1, "心率 > 72 的应有 1 个")
    }

    /// HealthDailySummary 可通过字段比较实现相等性判断
    func testHealthDailySummaryCanBeCompared() {
        let s1 = HealthDailySummary(sleepHours: 7.5, avgHeartRate: 70.0, stepCount: 8000)
        let s2 = HealthDailySummary(sleepHours: 7.5, avgHeartRate: 70.0, stepCount: 8000)
        let s3 = HealthDailySummary(sleepHours: 6.0, avgHeartRate: 70.0, stepCount: 8000)

        XCTAssertTrue(s1.sleepHours == s2.sleepHours && s1.avgHeartRate == s2.avgHeartRate && s1.stepCount == s2.stepCount,
                     "相同值的 summary 应相等")
        XCTAssertFalse(s1.sleepHours == s3.sleepHours, "不同 sleepHours 的 summary 应不等")
    }

    // MARK: - HealthKitError 进阶测试

    /// HealthKitError.notAvailable 与 .notAuthorized 应为不同 case
    func testHealthKitErrorCasesAreDistinct() {
        let error1 = HealthKitError.notAvailable
        let error2 = HealthKitError.notAuthorized

        switch error1 {
        case .notAvailable:
            break
        case .notAuthorized:
            XCTFail("应为 .notAvailable")
        }

        switch error2 {
        case .notAvailable:
            XCTFail("应为 .notAuthorized")
        case .notAuthorized:
            break
        }
    }

    /// HealthKitError 可在 do-catch 中被捕获并区分
    func testHealthKitErrorCanBeCaughtAndDifferentiated() {
        func throwError(_ error: HealthKitError) throws {
            throw error
        }

        do {
            try throwError(.notAvailable)
            XCTFail("应抛出错误")
        } catch HealthKitError.notAvailable {
            // 正确捕获
        } catch {
            XCTFail("应捕获 .notAvailable，实际：\(error)")
        }

        do {
            try throwError(.notAuthorized)
            XCTFail("应抛出错误")
        } catch HealthKitError.notAuthorized {
            // 正确捕获
        } catch {
            XCTFail("应捕获 .notAuthorized，实际：\(error)")
        }
    }

    /// HealthKitError 两个 case 的 errorDescription 应互不相同
    func testHealthKitErrorDescriptionsAreDifferent() {
        let desc1 = HealthKitError.notAvailable.errorDescription
        let desc2 = HealthKitError.notAuthorized.errorDescription
        XCTAssertNotEqual(desc1, desc2, "两个 case 的 errorDescription 应不同")
    }

    /// HealthKitError 应符合 LocalizedError 协议
    func testHealthKitErrorConformsToLocalizedError() {
        let error: Any = HealthKitError.notAvailable
        XCTAssertTrue(error is LocalizedError, "HealthKitError 应符合 LocalizedError")

        let error2: Any = HealthKitError.notAuthorized
        XCTAssertTrue(error2 is LocalizedError, "HealthKitError 应符合 LocalizedError")
    }

    // MARK: - 边界值与异常输入测试

    /// fetchHeartRate days 为负数时应不崩溃（返回空字典）
    func testFetchHeartRateNegativeDaysDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchHeartRate(days: -1)
        XCTAssertTrue(result.isEmpty, "未授权时负数 days 也应返回空字典")
    }

    /// fetchSleepAnalysis days 为负数时应不崩溃
    func testFetchSleepAnalysisNegativeDaysDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchSleepAnalysis(days: -1)
        XCTAssertTrue(result.isEmpty, "未授权时负数 days 也应返回空字典")
    }

    /// fetchStepCount days 为负数时应不崩溃
    func testFetchStepCountNegativeDaysDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchStepCount(days: -1)
        XCTAssertTrue(result.isEmpty, "未授权时负数 days 也应返回空字典")
    }

    /// fetchHeartRate days 为极大值时应不崩溃
    func testFetchHeartRateLargeDaysDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchHeartRate(days: 36500)
        XCTAssertTrue(result.isEmpty, "未授权时大 days 也应返回空字典")
    }

    /// fetchStepCount days 为极大值时应不崩溃
    func testFetchStepCountLargeDaysDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchStepCount(days: 36500)
        XCTAssertTrue(result.isEmpty, "未授权时大 days 也应返回空字典")
    }

    /// fetchSleepAnalysis days 为极大值时应不崩溃
    func testFetchSleepAnalysisLargeDaysDoesNotCrash() async throws {
        let service = HealthKitService()
        let result = try await service.fetchSleepAnalysis(days: 36500)
        XCTAssertTrue(result.isEmpty, "未授权时大 days 也应返回空字典")
    }

    /// fetchHeartRate 和 fetchStepCount 交叉调用应不互相影响
    func testCrossFetchMethodsDoNotInterfere() async throws {
        let service = HealthKitService()
        let hr = try await service.fetchHeartRate(days: 3)
        let steps = try await service.fetchStepCount(days: 3)
        let sleep = try await service.fetchSleepAnalysis(days: 3)

        // 未授权时都应返回空
        if !service.isAuthorized {
            XCTAssertTrue(hr.isEmpty)
            XCTAssertTrue(steps.isEmpty)
            XCTAssertTrue(sleep.isEmpty)
        }
    }

    // MARK: - 并发与线程安全

    /// isAuthorized 在并发读取下应保持一致
    func testIsAuthorizedConcurrentReadsConsistent() async {
        let service = HealthKitService()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask { service.isAuthorized }
            }
            for await value in group {
                XCTAssertFalse(value, "并发读取 isAuthorized 应都为 false")
            }
        }
    }

    /// fetchDailySummary 并发调用应稳定返回
    func testFetchDailySummaryConcurrentCallsStable() async throws {
        let service = HealthKitService()

        await withTaskGroup(of: HealthDailySummary?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await service.fetchDailySummary()
                }
            }
            for await summary in group {
                XCTAssertNotNil(summary, "并发调用 fetchDailySummary 不应抛错")
                if let summary = summary, !service.isAuthorized {
                    XCTAssertEqual(summary.sleepHours, 0, "未授权时并发调用也应返回 0")
                    XCTAssertEqual(summary.avgHeartRate, 0, "未授权时并发调用也应返回 0")
                    XCTAssertEqual(summary.stepCount, 0, "未授权时并发调用也应返回 0")
                }
            }
        }
    }

    /// 多个 fetch 方法混合并发调用应不崩溃
    func testMixedFetchConcurrentCallsDoNotCrash() async throws {
        let service = HealthKitService()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    _ = try? await service.fetchHeartRate(days: 1)
                }
                group.addTask {
                    _ = try? await service.fetchSleepAnalysis(days: 1)
                }
                group.addTask {
                    _ = try? await service.fetchStepCount(days: 1)
                }
                group.addTask {
                    _ = try? await service.fetchDailySummary()
                }
            }
        }

        XCTAssertTrue(true, "混合并发调用应不崩溃")
    }

    // MARK: - requestAuthorization 跳过逻辑

    /// requestAuthorization 在 CI 环境应被跳过
    func testRequestAuthorizationSkippedInCI() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "跳过：CI 环境无法处理 HealthKit 权限弹窗")
        let service = HealthKitService()
        do {
            try await service.requestAuthorization()
        } catch {
            // 预期可能抛错（模拟器无 HealthKit）
        }
        // 不强制断言 isAuthorized，因为模拟器环境不确定
    }
}
#endif
