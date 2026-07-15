import Foundation
import AetherFoundation

/// Day 13: LLM 供应商工厂。根据 ModelProvider 实例化对应的 LLMProvider client。
/// 生产侧调用点：ChatViewModel.makeLLMProvider()
public enum ModelProviderFactory {
    /// 根据 provider 返回对应的 LLMProvider 实例
    /// - Parameter provider: 供应商枚举值
    /// - Returns: 对应的 LLMProvider（DeepSeekClient / QwenClient）
    public static func make(_ provider: ModelProvider) -> LLMProvider {
        switch provider {
        case .deepseek:
            return DeepSeekClient()
        case .qwen:
            return QwenClient()
        case .onDevice:
            // Day 16: 端侧推理走 OfflineLLMProvider（内部转发 MLXInferenceEngine）
            // TODO: OfflineLLMProvider 尚未迁移到 AetherServices，待后续 Task 处理
            fatalError("OfflineLLMProvider not yet migrated to AetherServices")
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
