import Foundation
import AetherFoundation
import AetherServices

/// P2-6 Task 6: NetworkFallbackCoordinator —— 网络监听 + 端侧切换 + Provider 工厂协调器
///
/// 从 ChatViewModel 抽取的 Day 13/15/16 网络与 Provider 相关职责：
/// - `currentNetworkStatus` / `lastUsedProvider` / `didFallbackLastRequest` 状态持有
/// - `startNetworkMonitoring()` 订阅 NetworkMonitor 状态流，断网切端侧 / 联网恢复
/// - `switchToOnDevice()` / `switchToOriginalProvider()` 端侧 ↔ 云端 provider 切换
/// - `makeLLMProvider(...)` Provider 工厂：BFF / Fallback / 直连三种路径
/// - `effectiveProviderForRequest(...)` 请求时实际使用的 provider（onDevice + tools + online → fallback）
/// - `mapModelName(_:for:)` SmartRouter 输出 → 各 provider 对应模型名映射
///
/// 通过闭包回调更新 ChatViewModel 的 @Observable 属性
/// （selectedProvider / currentNetworkStatus / lastUsedProvider / didFallbackLastRequest），
/// 不直接持有 @Observable 属性。
///
/// 并发边界：本类标注 `@MainActor`，所有闭包在主 actor 上调用；
/// `networkStatusTask` 显式标注 `@MainActor`，订阅 NetworkMonitor.shared.statusStream 后
/// 在主 actor 上更新 currentNetworkStatus 与触发回调。
@MainActor
final class NetworkFallbackCoordinator: Coordinator {
    // MARK: - State（由 coordinator 持有，外部通过 getter 读取）

    /// 当前网络状态（由 NetworkMonitor 更新，供 makeLLMProvider 同步判断是否降级）
    private(set) var currentNetworkStatus: NetworkStatus = .online
    /// 最近一次请求实际命中的 provider（暴露给 DebugInfo，由 FallbackLLMProvider 写入）
    private(set) var lastUsedProvider: ModelProvider?
    /// 最近一次请求是否触发了降级
    private(set) var didFallbackLastRequest: Bool = false
    /// 断网自动切换前保存的原 provider，联网后切回
    private(set) var originalSelectedProvider: ModelProvider?
    /// 网络状态监听 Task（断网切端侧、联网切云端），由 coordinator 持有
    private(set) var networkStatusTask: Task<Void, Never>?

    // MARK: - Closure-based IO（与 ChatViewModel 双向通信）

    /// 当前 selectedProvider 查询闭包（读取 ChatViewModel 的 @Observable var selectedProvider 当前值）
    /// 用于 switchToOnDevice / switchToOriginalProvider 判断当前 provider 与是否需要保存原值
    private let selectedProviderProvider: () -> ModelProvider
    /// selectedProvider 变更回调（ChatViewModel 设置，更新 @Observable var selectedProvider）
    private let onSelectedProviderChange: (ModelProvider) -> Void
    /// currentNetworkStatus 变更回调（ChatViewModel 设置，更新 @Observable var currentNetworkStatus）
    private let onCurrentNetworkStatusChange: (NetworkStatus) -> Void
    /// lastUsedProvider 变更回调（ChatViewModel 设置，更新 @Observable var lastUsedProvider）
    private let onLastUsedProviderChange: (ModelProvider?) -> Void
    /// didFallbackLastRequest 变更回调（ChatViewModel 设置，更新 @Observable var didFallbackLastRequest）
    private let onDidFallbackLastRequestChange: (Bool) -> Void

    /// 构造器
    /// - Parameters:
    ///   - selectedProviderProvider: selectedProvider 当前值查询闭包（@MainActor）
    ///   - onSelectedProviderChange: selectedProvider 变更回调（@MainActor）
    ///   - onCurrentNetworkStatusChange: currentNetworkStatus 变更回调（@MainActor）
    ///   - onLastUsedProviderChange: lastUsedProvider 变更回调（@MainActor）
    ///   - onDidFallbackLastRequestChange: didFallbackLastRequest 变更回调（@MainActor）
    init(selectedProviderProvider: @escaping () -> ModelProvider,
         onSelectedProviderChange: @escaping (ModelProvider) -> Void,
         onCurrentNetworkStatusChange: @escaping (NetworkStatus) -> Void,
         onLastUsedProviderChange: @escaping (ModelProvider?) -> Void,
         onDidFallbackLastRequestChange: @escaping (Bool) -> Void) {
        self.selectedProviderProvider = selectedProviderProvider
        self.onSelectedProviderChange = onSelectedProviderChange
        self.onCurrentNetworkStatusChange = onCurrentNetworkStatusChange
        self.onLastUsedProviderChange = onLastUsedProviderChange
        self.onDidFallbackLastRequestChange = onDidFallbackLastRequestChange
    }

    // MARK: - 网络监听

    /// 启动网络状态监听。断网时切到端侧推理，联网后切回原 provider。
    /// 行为等价于 ChatViewModel 原始 startNetworkMonitoring 实现。
    func startNetworkMonitoring() {
        networkStatusTask?.cancel()
        networkStatusTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            // 启动全局 NetworkMonitor（内部幂等，多次调用安全）
            await NetworkMonitor.shared.start()
            // 订阅状态变化流，初始状态会立即 yield 一次
            let stream = await NetworkMonitor.shared.statusStream()
            for await status in stream {
                guard !Task.isCancelled else { return }
                self.currentNetworkStatus = status
                self.onCurrentNetworkStatusChange(status)
                if status == .offline {
                    // 断网：切到端侧推理
                    self.switchToOnDevice()
                } else {
                    // 联网（wifi/cellular/online）：切回原 provider
                    self.switchToOriginalProvider()
                }
            }
        }
    }

    // MARK: - 端侧 ↔ 云端 provider 切换

    /// 切换到端侧推理。保存当前 provider 供联网后恢复。
    /// 行为等价于 ChatViewModel 原始 switchToOnDevice 实现。
    func switchToOnDevice() {
        let current = selectedProviderProvider()
        guard current != .onDevice else { return }
        // 仅在未保存过原 provider 时保存，避免覆盖
        if originalSelectedProvider == nil {
            originalSelectedProvider = current
        }
        onSelectedProviderChange(.onDevice)
    }

    /// 切回原 provider（联网后恢复）。仅当当前处于端侧推理且有保存的原 provider 时生效。
    /// 行为等价于 ChatViewModel 原始 switchToOriginalProvider 实现。
    func switchToOriginalProvider() {
        let current = selectedProviderProvider()
        guard current == .onDevice, let original = originalSelectedProvider else { return }
        onSelectedProviderChange(original)
        originalSelectedProvider = nil
    }

    // MARK: - Provider 工厂

    /// 按 selectedProvider / fallbackProvider / bffConfig 构造 LLMProvider。
    /// 行为等价于 ChatViewModel 原始 makeLLMProvider 实现。
    /// - Parameters:
    ///   - selectedProvider: 当前请求实际使用的 provider（应由调用方先经 effectiveProviderForRequest 计算）
    ///   - fallbackProvider: 备用供应商（nil=不降级；非 nil 时用 FallbackLLMProvider 装饰主 provider）
    ///   - bffConfig: BFF 代理配置（启用后请求经服务端中转，上游 API Key 不落设备）
    ///   - injectedClient: 测试注入的 client（非 nil 时直接返回，绕过工厂构造）
    /// - Returns: 构造好的 LLMProvider（BFFProxyClient / FallbackLLMProvider / 直连 client / 注入 client）
    func makeLLMProvider(
        selectedProvider: ModelProvider,
        fallbackProvider: ModelProvider?,
        bffConfig: BFFConfig,
        injectedClient: LLMProvider?
    ) -> LLMProvider {
        // 测试侧：若注入了 client，则优先用注入的（绕过工厂）
        if let injected = injectedClient {
            return injected
        }
        // Day 15: BFF 模式启用时走 BFF 代理（服务端持有上游 key，设备只持 BFF Token）
        if bffConfig.enabled {
            return ModelProviderFactory.make(bffConfig: bffConfig, provider: selectedProvider)
        }
        let primary = ModelProviderFactory.make(selectedProvider)
        if let fb = fallbackProvider {
            let fallback = ModelProviderFactory.make(fb)
            return FallbackLLMProvider(
                primary: primary, fallback: fallback,
                primaryProvider: selectedProvider, fallbackProvider: fb
            )
        }
        return primary
    }

    /// 计算本次请求实际使用的 provider。
    /// 端侧推理不支持工具调用，若需工具且网络可用则降级到云端 fallback provider。
    /// 行为等价于 ChatViewModel 原始 effectiveProviderForRequest 实现。
    /// - Parameters:
    ///   - selectedProvider: 当前选中的 provider（ChatViewModel.selectedProvider）
    ///   - toolsEnabled: 是否启用工具调用
    /// - Returns: 实际使用的 provider（可能为 selectedProvider.fallback）
    func effectiveProviderForRequest(
        selectedProvider: ModelProvider, toolsEnabled: Bool
    ) -> ModelProvider {
        if selectedProvider == .onDevice && toolsEnabled && currentNetworkStatus != .offline {
            return selectedProvider.fallback
        }
        return selectedProvider
    }

    /// 把 SmartRouter 输出的模型名（"deepseek-chat" / "deepseek-reasoner"）映射到指定 provider 的对应模型名。
    /// - "deepseek-chat" → provider.defaultChatModel
    /// - "deepseek-reasoner" → provider.defaultReasonerModel
    /// - 其他 → 原值返回
    /// 行为等价于 ChatViewModel 原始 mapModelName 实现。
    /// - Parameters:
    ///   - name: SmartRouter 输出或用户手动选择的模型名
    ///   - provider: 实际使用的 provider（用于查找对应模型名）
    /// - Returns: 映射后的模型名
    func mapModelName(_ name: String, for provider: ModelProvider) -> String {
        switch name {
        case "deepseek-chat":
            return provider.defaultChatModel
        case "deepseek-reasoner":
            return provider.defaultReasonerModel
        default:
            return name
        }
    }

    // MARK: - State 更新方法（由 ChatViewModel.handlePreparing / handleFinishing 调用）

    /// 更新 lastUsedProvider。
    /// 由 ChatViewModel.handlePreparing（设为 effectiveProviderForRequest()）与
    /// handleFinishing（设为 FallbackLLMProvider.lastUsedProvider）调用。
    /// 同时通过 onLastUsedProviderChange 闭包同步 ChatViewModel 的 @Observable 属性。
    func updateLastUsedProvider(_ provider: ModelProvider?) {
        lastUsedProvider = provider
        onLastUsedProviderChange(provider)
    }

    /// 更新 didFallbackLastRequest。
    /// 由 ChatViewModel.handlePreparing（重置为 false）与
    /// handleFinishing（设为 FallbackLLMProvider.didFallback）调用。
    /// 同时通过 onDidFallbackLastRequestChange 闭包同步 ChatViewModel 的 @Observable 属性。
    func updateDidFallbackLastRequest(_ value: Bool) {
        didFallbackLastRequest = value
        onDidFallbackLastRequestChange(value)
    }
}
