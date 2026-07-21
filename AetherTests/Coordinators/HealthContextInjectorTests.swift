#if os(iOS)
import XCTest
import AetherServices
@testable import Aether

/// P2-6 Task 5: HealthContextInjector 单元测试
///
/// 验证 HealthContextInjector 正确封装 HealthKit 上下文注入职责：
/// - 启用且已授权时构建健康摘要片段（睡眠/心率/步数）
/// - 未授权时返回空字符串（不抛错）
/// - 未启用注入开关时返回空字符串（NoOp）
/// - healthKitService 为 nil 时返回空字符串
///
/// HealthKitService 为 final 类无法子类化，真实授权需权限，
/// 故涉及真实 HealthKit 调用的测试通过 SIMULATOR_DEVICE_NAME / CI 环境变量守卫跳过；
/// 未授权 / 未启用 / nil 服务三个测试不触及 HealthKit API，可在模拟器运行。
@MainActor
final class HealthContextInjectorTests: XCTestCase {

    /// 模拟器环境标识（CI 模拟器无 HealthKit 支持）
    private var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }

    /// CI 环境标识
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    // MARK: - testHealthContextInjectionAppendsHealthSummary

    /// 启用健康上下文注入且服务已授权时，buildHealthContextSnippet 返回的片段应包含
    /// 睡眠 / 心率 / 步数关键词之一。
    /// 注：HealthKitService 为 final 类，无法注入 mock；真实授权需权限，故在模拟器/CI 跳过。
    func testHealthContextInjectionAppendsHealthSummary() async throws {
        try XCTSkipIf(isSimulator || isCI,
                      "跳过：HealthKitService 为 final 类，测试模块无法注入 mock，真实授权需权限")
        let healthService = HealthKitService()
        try await healthService.requestAuthorization()
        let injector = HealthContextInjector(
            healthKitServiceProvider: { healthService },
            injectHealthContextProvider: { true }
        )

        let snippet = await injector.buildHealthContextSnippet()

        XCTAssertTrue(snippet.contains("睡眠") || snippet.contains("心率") || snippet.contains("步数"),
                      "授权后 snippet 应包含健康摘要信息，实际值：\(snippet)")
    }

    // MARK: - testHealthContextNotAuthorizedDoesNotAppendSummary

    /// 启用健康上下文注入但 HealthKitService 未授权时，buildHealthContextSnippet 应返回空字符串。
    /// 新实例的 isAuthorized 锁初始为 false，无需请求真实权限，可在模拟器运行。
    func testHealthContextNotAuthorizedDoesNotAppendSummary() async throws {
        let healthService = HealthKitService()
        XCTAssertFalse(healthService.isAuthorized, "新实例应处于未授权状态")
        let injector = HealthContextInjector(
            healthKitServiceProvider: { healthService },
            injectHealthContextProvider: { true }
        )

        let snippet = await injector.buildHealthContextSnippet()

        XCTAssertEqual(snippet, "", "未授权时 snippet 应为空字符串")
    }

    // MARK: - testHealthContextDisabledNoOp

    /// injectHealthContextProvider 返回 false 时，buildHealthContextSnippet 应返回空字符串（NoOp），
    /// 即使 healthKitService 已授权也不应构建片段。
    func testHealthContextDisabledNoOp() async throws {
        let healthService = HealthKitService()
        let injector = HealthContextInjector(
            healthKitServiceProvider: { healthService },
            injectHealthContextProvider: { false }
        )

        let snippet = await injector.buildHealthContextSnippet()

        XCTAssertEqual(snippet, "", "禁用注入时 snippet 应为空字符串")
    }

    // MARK: - testHealthKitServiceNilReturnsEmptyString

    /// healthKitServiceProvider 返回 nil 时，buildHealthContextSnippet 应返回空字符串，
    /// 无论 injectHealthContextProvider 返回 true 还是 false。
    func testHealthKitServiceNilReturnsEmptyString() async throws {
        let injector = HealthContextInjector(
            healthKitServiceProvider: { nil },
            injectHealthContextProvider: { true }
        )

        let snippet = await injector.buildHealthContextSnippet()

        XCTAssertEqual(snippet, "", "healthKitService 为 nil 时 snippet 应为空字符串")
    }
}
#endif
