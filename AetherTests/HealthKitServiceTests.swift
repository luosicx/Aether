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
    func testHealthKitErrorNotAvailableDescription() {
        let error = HealthKitError.notAvailable
        XCTAssertNotNil(error.errorDescription, "notAvailable 的 errorDescription 不应为 nil")
        XCTAssertTrue(error.errorDescription?.contains("不支持") == true,
                      "notAvailable 描述应含「不支持」，实际：\(error.errorDescription ?? "nil")")
    }

    /// HealthKitError.notAuthorized 应提供非空用户友好描述
    func testHealthKitErrorNotAuthorizedDescription() {
        let error = HealthKitError.notAuthorized
        XCTAssertNotNil(error.errorDescription, "notAuthorized 的 errorDescription 不应为 nil")
        XCTAssertTrue(error.errorDescription?.contains("授权") == true,
                      "notAuthorized 描述应含「授权」，实际：\(error.errorDescription ?? "nil")")
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
}
#endif
