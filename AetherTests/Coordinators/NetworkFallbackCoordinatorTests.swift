import XCTest
import AetherFoundation
import AetherServices
@testable import Aether

/// P2-6 Task 6: NetworkFallbackCoordinator 单元测试
///
/// 验证 NetworkFallbackCoordinator 正确封装：
/// - 网络状态监听 + 端侧切换（断网→onDevice，联网→恢复）
/// - Provider 工厂（BFF / Fallback / OnDevice / 直连四种路径）
/// - 模型名映射（SmartRouter 输出 → 各 provider 对应模型名）
/// - effectiveProviderForRequest 降级逻辑（onDevice + tools + online → fallback）
/// 通过闭包回调更新外部状态（ChatViewModel 的 @Observable 属性），不直接持有 @Observable 属性。
@MainActor
final class NetworkFallbackCoordinatorTests: XCTestCase {

    // MARK: - 辅助

    /// NetworkFallbackCoordinator 测试夹具：构造 coordinator 同时持有闭包回调写入的 Box，便于断言。
    /// 使用 struct 而非多元组返回，避免触发 SwiftLint large_tuple（warning 阈值 4）。
    private struct NetworkFallbackFixture {
        let coordinator: NetworkFallbackCoordinator
        let selectedProvider: NonIsolatedBox<ModelProvider>
        let currentNetworkStatus: NonIsolatedBox<NetworkStatus>
        let lastUsedProvider: NonIsolatedBox<ModelProvider?>
        let didFallbackLastRequest: NonIsolatedBox<Bool>
    }

    /// 构造一个 NetworkFallbackCoordinator 并捕获闭包回调值，便于断言。
    /// selectedProvider 初值由参数指定（默认 .deepseek），由 NonIsolatedBox 持有以模拟 ChatViewModel 的 @Observable var selectedProvider。
    private func makeCoordinator(
        initialSelectedProvider: ModelProvider = .deepseek
    ) -> NetworkFallbackFixture {
        let selectedBox = NonIsolatedBox<ModelProvider>(initialSelectedProvider)
        let networkStatusBox = NonIsolatedBox<NetworkStatus>(.online)
        let lastUsedBox = NonIsolatedBox<ModelProvider?>(nil)
        let didFallbackBox = NonIsolatedBox<Bool>(false)
        let coordinator = NetworkFallbackCoordinator(
            selectedProviderProvider: { selectedBox.value },
            onSelectedProviderChange: { selectedBox.value = $0 },
            onCurrentNetworkStatusChange: { networkStatusBox.value = $0 },
            onLastUsedProviderChange: { lastUsedBox.value = $0 },
            onDidFallbackLastRequestChange: { didFallbackBox.value = $0 }
        )
        return NetworkFallbackFixture(
            coordinator: coordinator,
            selectedProvider: selectedBox,
            currentNetworkStatus: networkStatusBox,
            lastUsedProvider: lastUsedBox,
            didFallbackLastRequest: didFallbackBox
        )
    }

    // MARK: - switchToOnDevice / switchToOriginalProvider

    /// switchToOnDevice：从 .deepseek 切换到 .onDevice 时应保存原 provider 并通知 .onDevice。
    func testSwitchToOnDeviceSavesOriginalProvider() {
        let fx = makeCoordinator(initialSelectedProvider: .deepseek)

        fx.coordinator.switchToOnDevice()

        XCTAssertEqual(fx.selectedProvider.value, .onDevice,
                       "switchToOnDevice 应通过 onSelectedProviderChange 通知 .onDevice")
        XCTAssertEqual(fx.coordinator.originalSelectedProvider, .deepseek,
                       "原 provider .deepseek 应被保存到 originalSelectedProvider")
    }

    /// switchToOriginalProvider：处于 .onDevice 且有保存的原 provider 时应恢复并清空 originalSelectedProvider。
    func testSwitchToOriginalProviderRestoresOriginal() {
        let fx = makeCoordinator(initialSelectedProvider: .deepseek)

        // 前置：先切到端侧，保存原 provider
        fx.coordinator.switchToOnDevice()
        XCTAssertEqual(fx.coordinator.originalSelectedProvider, .deepseek, "前置：原 provider 已保存")
        XCTAssertEqual(fx.selectedProvider.value, .onDevice, "前置：selectedProvider 已切到 .onDevice")

        fx.coordinator.switchToOriginalProvider()

        XCTAssertEqual(fx.selectedProvider.value, .deepseek,
                       "switchToOriginalProvider 应通过 onSelectedProviderChange 恢复 .deepseek")
        XCTAssertNil(fx.coordinator.originalSelectedProvider,
                     "恢复后 originalSelectedProvider 应清空")
    }

    /// switchToOnDevice 守卫：已处于 .onDevice 时不应重复保存原 provider，也不应触发回调。
    func testSwitchToOnDeviceGuardWhenAlreadyOnDevice() {
        let fx = makeCoordinator(initialSelectedProvider: .onDevice)

        fx.coordinator.switchToOnDevice()

        XCTAssertEqual(fx.selectedProvider.value, .onDevice,
                       "已是 .onDevice 时 selectedProvider 应保持不变（不触发回调）")
        XCTAssertNil(fx.coordinator.originalSelectedProvider,
                     "已是 .onDevice 时不应保存原 provider")
    }

    /// switchToOriginalProvider 守卫：非 .onDevice 状态时不应触发恢复。
    func testSwitchToOriginalProviderGuardWhenNotOnDevice() {
        let fx = makeCoordinator(initialSelectedProvider: .qwen)

        fx.coordinator.switchToOriginalProvider()

        XCTAssertEqual(fx.selectedProvider.value, .qwen,
                       "非 .onDevice 时 selectedProvider 应保持不变（不触发回调）")
    }

    // MARK: - effectiveProviderForRequest

    /// onDevice + toolsEnabled + online → 降级到 fallback provider（onDevice.fallback = .deepseek）。
    /// 端侧推理不支持工具调用，在线时需切到云端 fallback 以支持 function calling。
    func testEffectiveProviderForRequestOnDeviceWithToolsDegradesToFallback() {
        let fx = makeCoordinator(initialSelectedProvider: .onDevice)
        // currentNetworkStatus 默认为 .online（init 初值）

        let result = fx.coordinator.effectiveProviderForRequest(
            selectedProvider: .onDevice, toolsEnabled: true
        )

        XCTAssertEqual(result, .deepseek,
                       "onDevice + tools + online 应降级到 onDevice.fallback = .deepseek")
    }

    // MARK: - makeLLMProvider

    /// BFF 启用且无注入 client 时，工厂应返回 BFFProxyClient 实例。
    func testMakeLLMProviderBFFPath() {
        let fx = makeCoordinator(initialSelectedProvider: .deepseek)
        var bffConfig = BFFConfig.default
        bffConfig.enabled = true

        let provider = fx.coordinator.makeLLMProvider(
            selectedProvider: .deepseek,
            fallbackProvider: nil,
            bffConfig: bffConfig,
            injectedClient: nil
        )

        XCTAssertTrue(provider is BFFProxyClient,
                      "BFF 启用且无注入 client 时应返回 BFFProxyClient")
    }

    /// fallbackProvider 非空且无注入 client 时，工厂应返回 FallbackLLMProvider 装饰实例。
    func testMakeLLMProviderFallbackPath() {
        let fx = makeCoordinator(initialSelectedProvider: .deepseek)

        let provider = fx.coordinator.makeLLMProvider(
            selectedProvider: .deepseek,
            fallbackProvider: .qwen,
            bffConfig: .default,
            onDeviceConfig: .default,
            injectedClient: nil
        )

        XCTAssertTrue(provider is FallbackLLMProvider,
                      "fallbackProvider 非空时应返回 FallbackLLMProvider")
    }

    // MARK: - mapModelName

    /// mapModelName：把 SmartRouter 输出的 "deepseek-chat" / "deepseek-reasoner"
    /// 映射到各 provider 的对应模型名；未知模型名原样返回。
    func testMapModelNameSmartRouter() {
        let fx = makeCoordinator()

        // deepseek-chat 映射到各 provider 的 defaultChatModel
        XCTAssertEqual(fx.coordinator.mapModelName("deepseek-chat", for: .deepseek), "deepseek-chat",
                       "deepseek + deepseek-chat → deepseek-chat")
        XCTAssertEqual(fx.coordinator.mapModelName("deepseek-chat", for: .qwen), "qwen-plus",
                       "qwen + deepseek-chat → qwen-plus")
        XCTAssertEqual(fx.coordinator.mapModelName("deepseek-chat", for: .onDevice), "llama-3.2-1b-instruct",
                       "onDevice + deepseek-chat → llama-3.2-1b-instruct")

        // deepseek-reasoner 映射到各 provider 的 defaultReasonerModel
        XCTAssertEqual(fx.coordinator.mapModelName("deepseek-reasoner", for: .deepseek), "deepseek-reasoner",
                       "deepseek + deepseek-reasoner → deepseek-reasoner")
        XCTAssertEqual(fx.coordinator.mapModelName("deepseek-reasoner", for: .qwen), "qwq-32b",
                       "qwen + deepseek-reasoner → qwq-32b")

        // 未知模型名应原样返回
        XCTAssertEqual(fx.coordinator.mapModelName("custom-model-v1", for: .deepseek), "custom-model-v1",
                       "未知模型名应原样返回")
    }

    // MARK: - startNetworkMonitoring

    /// startNetworkMonitoring：启动后 currentNetworkStatus 应同步为 NetworkMonitor.shared.currentStatus。
    func testNetworkMonitoringUpdatesCurrentNetworkStatus() async throws {
        // 先停止监控器，避免其它测试残留状态干扰
        await NetworkMonitor.shared.stop()
        let fx = makeCoordinator()

        fx.coordinator.startNetworkMonitoring()

        // 轮询等待 networkStatusTask 启动并同步状态
        var synced = false
        for _ in 0..<50 {
            let monitorStatus = await NetworkMonitor.shared.currentStatus
            if fx.coordinator.currentNetworkStatus == monitorStatus {
                synced = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        XCTAssertTrue(synced,
                      "网络监控启动后 currentNetworkStatus 应与 NetworkMonitor.shared.currentStatus 一致")
        XCTAssertEqual(fx.currentNetworkStatus.value, fx.coordinator.currentNetworkStatus,
                       "应通过 onCurrentNetworkStatusChange 闭包通知外部状态")

        // 清理：取消 task 并停止监控器
        fx.coordinator.networkStatusTask?.cancel()
        await NetworkMonitor.shared.stop()
    }

    // MARK: - onDevice provider skip apiKey check

    /// 注入 client 时工厂直接返回注入实例，不调用 ModelProviderFactory.make(.onDevice)（避免 fatalError）。
    /// 这是 onDevice provider 能跳过 apiKey 检查的前提：注入的 mock client 不需要 apiKey。
    func testOnDeviceProviderSkipsAPIKeyCheck() {
        let fx = makeCoordinator(initialSelectedProvider: .onDevice)
        let mock = MockLLMProvider()
        mock.chatChunks = ["端侧回复"]

        let provider = fx.coordinator.makeLLMProvider(
            selectedProvider: .onDevice,
            fallbackProvider: nil,
            bffConfig: .default,
            injectedClient: mock
        )

        // 验证返回的是注入的 mock（同一实例），而不是 ModelProviderFactory.make(.onDevice) 触发 fatalError
        guard let returned = provider as? MockLLMProvider else {
            XCTFail("注入 client 时工厂应直接返回注入的实例（MockLLMProvider）")
            return
        }
        XCTAssertTrue(returned === mock,
                      "注入 client 时工厂应返回同一实例（identity 相等）")
    }
}
