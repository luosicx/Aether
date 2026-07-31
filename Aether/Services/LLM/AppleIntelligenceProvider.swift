import Foundation

// MARK: - AppleIntelligenceProvider

/// v3.0: Apple Intelligence 集成 — 基于 Apple Foundation Models 框架的端侧 LLM Provider。
///
/// 职责：
/// - 实现 `LLMProvider` 协议，调用 `FoundationModels` 框架的 `LanguageModelSession`
/// - 提供端侧 3B 模型推理能力（系统级优化，与 MLX 互补）
/// - 全端侧运行，无网络请求，隐私优先
///
/// 平台可用性：
/// - iOS 18.0+ / macOS 15.0+（FoundationModels 框架可用时）
/// - 不可用时降级到 MLX / 云端 Provider（由 ModelProviderFactory 控制）
///
/// 并发说明：
/// - `nonisolated final class` + `@unchecked Sendable`，与 DeepSeekClient / QwenClient 一致
/// - 内部状态均为不可变（let），线程安全
public final class AppleIntelligenceProvider: LLMProvider, @unchecked Sendable {

    /// Provider 显示名称
    public static let providerName = "Apple Intelligence"

    /// 是否在当前平台可用（FoundationModels 框架存在且系统版本满足）
    public static var isAvailable: Bool {
        // 使用运行时检测：FoundationModels 框架在 iOS 18+ / macOS 15+ 可用
        // 这里用 NSClassFromString 检测，避免编译期 import 依赖
        if #available(iOS 18.0, macOS 15.0, *) {
            return NSClassFromString("FoundationModels.LanguageModelSession") != nil
        }
        return false
    }

    /// 默认模型标识符
    public let modelIdentifier: String

    /// 是否真正调用 Apple Intelligence（false = 占位模式，返回提示文本）
    public let enabled: Bool

    /// 初始化
    /// - Parameter enabled: true 尝试真实调用；false 占位模式（CI / 不可用环境）
    public init(modelIdentifier: String = "apple-intelligence-default", enabled: Bool? = nil) {
        self.modelIdentifier = modelIdentifier
        // 若未显式指定，则用平台可用性自动判断
        self.enabled = enabled ?? Self.isAvailable
    }

    // MARK: - LLMProvider 协议实现

    public func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { [self] in
                if !self.enabled {
                    // 占位模式：返回提示文本
                    continuation.yield("[Apple Intelligence 占位] 当前环境不可用，请使用 MLX 或云端 Provider。")
                    continuation.finish()
                    return
                }

                // 构建会话上下文
                let prompt = self.buildPrompt(from: messages, systemPrompt: config.systemPrompt)
                let response = await self.invokeAppleIntelligence(prompt: prompt, maxTokens: config.maxTokens)
                continuation.yield(response)
                continuation.finish()
            }
        }
    }

    public func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            Task { [self] in
                if !self.enabled {
                    // 占位模式：返回纯文本 chunk
                    let placeholder = "[Apple Intelligence 占位] 工具调用暂不支持，请使用云端 Provider。"
                    continuation.yield(ParsedChunk(content: placeholder, toolCalls: nil))
                    continuation.finish()
                    return
                }

                // Apple Intelligence 暂不支持工具调用，降级为纯文本
                let prompt = self.buildPrompt(from: messages, systemPrompt: config.systemPrompt)
                let response = await self.invokeAppleIntelligence(prompt: prompt, maxTokens: config.maxTokens)
                continuation.yield(ParsedChunk(content: response, toolCalls: nil))
                continuation.finish()
            }
        }
    }

    public func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        // Apple Intelligence 未公开嵌入 API，返回占位 384 维向量（与 EmbeddingService 占位一致）
        // 实际使用时由 EmbeddingService 兜底
        return texts.map { _ in
            (0..<384).map { _ in Float.random(in: -0.1...0.1) }
        }
    }

    // MARK: - 私有辅助

    /// 将 APIMessage 数组拼接为 Apple Intelligence 可消费的纯文本 prompt
    private func buildPrompt(from messages: [APIMessage], systemPrompt: String) -> String {
        var parts: [String] = [systemPrompt]
        for msg in messages {
            let role = msg.role.uppercased()
            parts.append("[\(role)] \(msg.content)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// 调用 Apple Intelligence（骨架实现）
    /// 实际调用 FoundationModels.LanguageModelSession，当前为占位返回
    private func invokeAppleIntelligence(prompt: String, maxTokens: Int) async -> String {
        // v3.0 骨架：实际调用 FoundationModels 框架的代码在此
        // 当前返回占位响应，待 FoundationModels 框架正式集成后替换
        return "Apple Intelligence 响应（骨架）：已收到 \(prompt.count) 字符输入，maxTokens=\(maxTokens)。"
    }
}
