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
            // 授权成功后（所有请求的读取类型均为 sharingAuthorized），isAuthorized 才应为 true
            XCTAssertTrue(service.isAuthorized, "授权成功后 isAuthorized 应为 true")
        } catch {
            // 授权失败（模拟器无 HealthKit 或用户拒绝），isAuthorized 应保持 false
            XCTAssertFalse(service.isAuthorized, "授权失败时 isAuthorized 应保持 false")
        }
    }

    /// 测试 5: 用户拒绝授权时，isAuthorized 必须保持 false。
    /// 覆盖修复：旧代码在 requestAuthorization 完成后无条件将 isAuthorized 设为 true，
    /// 导致即使用户拒绝，应用仍会读取健康数据。
    func testRequestAuthorizationDeniedKeepsIsAuthorizedFalse() async throws {
        let mockStore = MockHealthStore()
        mockStore.authorizationStatusValue = .sharingDenied
        let service = HealthKitService(healthStore: mockStore)

        try await service.requestAuthorization()

        XCTAssertFalse(service.isAuthorized, "用户拒绝授权后 isAuthorized 必须为 false")
    }

    /// 测试 6: 用户授权全部类型后，isAuthorized 才为 true。
    func testRequestAuthorizationGrantedSetsIsAuthorizedTrue() async throws {
        let mockStore = MockHealthStore()
        mockStore.authorizationStatusValue = .sharingAuthorized
        let service = HealthKitService(healthStore: mockStore)

        try await service.requestAuthorization()

        XCTAssertTrue(service.isAuthorized, "用户授权后 isAuthorized 应为 true")
    }

    /// 测试 7: 部分类型未授权时，isAuthorized 为 false。
    func testRequestAuthorizationPartiallyGrantedKeepsIsAuthorizedFalse() async throws {
        let mockStore = MockHealthStore()
        // 只有心率授权，睡眠/步数未授权；使用 type identifier 作为 key 避免实例比较问题
        mockStore.authorizationStatusByType = [
            HKQuantityType(.heartRate).identifier: .sharingAuthorized,
            HKCategoryType(.sleepAnalysis).identifier: .sharingDenied,
            HKQuantityType(.stepCount).identifier: .notDetermined
        ]
        let service = HealthKitService(healthStore: mockStore)

        try await service.requestAuthorization()

        XCTAssertFalse(service.isAuthorized, "部分类型未授权时 isAuthorized 必须为 false")
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
}

// MARK: - MockHealthStore

/// 用于 HealthKitService 单元测试的 HKHealthStore 子类。
/// 覆盖 requestAuthorization 与 authorizationStatus(for:)，避免依赖真实系统权限弹窗。
final class MockHealthStore: HKHealthStore {
    /// 默认返回的授权状态（用于所有 type）
    var authorizationStatusValue: HKAuthorizationStatus = .notDetermined
    /// 按 type identifier 返回的授权状态（优先级高于 authorizationStatusValue）
    var authorizationStatusByType: [String: HKAuthorizationStatus]?
    /// 是否让 requestAuthorization 抛错
    var shouldThrowOnRequest = false

    override func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        authorizationStatusByType?[type.identifier] ?? authorizationStatusValue
    }

    override func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>?,
        read typesToRead: Set<HKObjectType>?
    ) async throws {
        if shouldThrowOnRequest {
            throw NSError(domain: "MockHealthStore", code: 1, userInfo: nil)
        }
        // 不修改授权状态，由调用方通过 authorizationStatus(for:) 查询
    }
}
#endif
