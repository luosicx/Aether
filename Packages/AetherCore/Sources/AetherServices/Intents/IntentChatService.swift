import Foundation
import AetherFoundation

/// Day 18: AppIntent 专用对话服务，使 Shortcuts/Siri 能在无 ViewModel 上下文时发起对话。
/// nonisolated 设计允许跨 actor 调用（AppIntent perform 在后台执行）。
public final class IntentChatService {
    /// 单例，AppIntent 直接调用
    public static let shared = IntentChatService()

    /// 注入的 LLMProvider（测试用；nil 时回退到 ModelProviderFactory.make(.deepseek)）
    private let injectedLLMProvider: LLMProvider?
    /// 注入的 API Key 读取闭包（测试用；nil 时回退到 KeychainManager.shared.getAPIKey()）
    private let injectedAPIKeyProvider: (() -> String?)?

    /// 单例私有初始化：使用默认依赖（KeychainManager + ModelProviderFactory）
    private init() {
        self.injectedLLMProvider = nil
        self.injectedAPIKeyProvider = nil
    }

    /// 测试注入入口：可注入自定义 LLMProvider 与 API Key 读取闭包，
    /// 避免单例硬编码依赖导致的不可测问题。生产代码继续使用 shared。
    public init(llmProvider: LLMProvider, apiKeyProvider: @escaping () -> String?) {
        self.injectedLLMProvider = llmProvider
        self.injectedAPIKeyProvider = apiKeyProvider
    }

    /// 发送问题并等待完整回复（累积流式 chunk）。
    /// - Parameter query: 用户问题文本
    /// - Returns: LLM 完整回复文本
    /// - Throws: API Key 缺失或 LLM 请求失败时抛错
    public func ask(query: String) async throws -> String {
        // 1. 读取 API Key（注入优先；注入为 nil 时不回退 Keychain，保证测试隔离）
        let rawKey: String?
        if let provider = injectedAPIKeyProvider {
            rawKey = provider()
        } else {
            // TODO: KeychainManager 尚未迁移到 AetherServices，待后续 Task 处理
            // rawKey = KeychainManager.shared.getAPIKey()
            rawKey = nil
        }
        guard let apiKey = rawKey, !apiKey.isEmpty else {
            throw LLMError.apiKeyMissing
        }

        // 2. 构造 LLMProvider（注入优先，回退到 ModelProviderFactory.make(.deepseek)）
        let llmProvider = injectedLLMProvider ?? ModelProviderFactory.make(.deepseek)

        // 3. 构造 messages: [APIMessage]（含 system prompt + user query）
        let config = ChatConfig.default
        var messages: [APIMessage] = []
        // 注入 system 消息设定助手行为
        messages.append(APIMessage(
            role: "system",
            content: config.systemPrompt,
            images: nil,
            toolCallId: nil,
            toolName: nil,
            toolCalls: nil
        ))
        // 注入用户问题
        messages.append(APIMessage(
            role: "user",
            content: query,
            images: nil,
            toolCallId: nil,
            toolName: nil,
            toolCalls: nil
        ))

        // 4. 调用 llmProvider.chat(messages:config:apiKey:) 获取 AsyncStream<String>
        let stream = llmProvider.chat(messages: messages, config: config, apiKey: apiKey)

        // 5. 累积流式 chunk 到完整文本
        var fullReply = ""
        for try await chunk in stream {
            fullReply += chunk
        }

        // 6. 返回完整文本
        return fullReply
    }
}
