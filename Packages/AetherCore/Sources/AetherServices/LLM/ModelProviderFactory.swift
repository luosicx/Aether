import Foundation
import AetherFoundation

/// Day 13: LLM 供应商工厂。根据 ModelProvider 实例化对应的 LLMProvider client。
/// 生产侧调用点：ChatViewModel.makeLLMProvider()
public enum ModelProviderFactory {
    /// App 层注入的端侧 provider 工厂。
    ///
    /// `OfflineLLMProvider` 依赖 MLX / MLXInferenceEngine，保留在 App target，无法从
    /// AetherServices 直接引用；App 启动时（`AetherApp.sharedInit`）注入。
    /// 未注入时 `make(.onDevice)` 返回兜底 provider（上报错误后结束流），绝不 crash：
    /// 设置页可选中「端侧推理」，断网自动切换也会走到这里。
    public nonisolated(unsafe) static var onDeviceProviderFactory: (@Sendable () -> LLMProvider)?

    /// 根据 provider 返回对应的 LLMProvider 实例
    /// - Parameter provider: 供应商枚举值
    /// - Returns: 对应的 LLMProvider（DeepSeekClient / QwenClient / 端侧 provider）
    public static func make(_ provider: ModelProvider) -> LLMProvider {
        switch provider {
        case .deepseek:
            return DeepSeekClient()
        case .qwen:
            return QwenClient()
        case .onDevice:
            if let factory = onDeviceProviderFactory {
                return factory()
            }
            return UnavailableLLMProvider(
                message: NSLocalizedString("端侧推理暂不可用，请重试或切换供应商", comment: "")
            )
        }
    }

    /// Day 15: 按是否启用 BFF 代理构造 LLMProvider。
    /// - bffConfig.enabled == true → 返回 BFFProxyClient（经服务端中转，上游 key 不落设备）
    /// - 否则 → 调用现有 make(_:) 返回直连 client
    /// - Parameters:
    ///   - bffConfig: BFF 配置
    ///   - provider: 供应商枚举值
    /// - Returns: BFF 代理或直连 LLMProvider
    public static func make(bffConfig: BFFConfig, provider: ModelProvider) -> LLMProvider {
        if bffConfig.enabled {
            return BFFProxyClient(provider: provider, config: bffConfig)
        }
        return make(provider)
    }
}

/// 端侧 provider 未注入时的兜底：不发任何请求，直接上报错误并结束流。
/// 用于替代此前的 fatalError —— 设置页与断网自动切换都能把用户带到端侧推理。
private struct UnavailableLLMProvider: LLMProvider {
    let message: String

    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                await StreamTransport.report(.llmErrorOccurred(message))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func chat(
        messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String
    ) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            let task = Task {
                await StreamTransport.report(.llmErrorOccurred(message))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        throw LLMError.llmErrorOccurred(message)
    }
}
