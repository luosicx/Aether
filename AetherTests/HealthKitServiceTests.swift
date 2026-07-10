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
    func testRequestAuthorizationFailure() async {
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
}
#endif
