import Foundation

/// 上下文窗口管理器，负责压缩历史消息以适配 LLM 的 token 上限。
///
/// 设计要点：
/// - compress：总 token 未超限时直接返回原列表；超限时将旧消息摘要化为一条 system 消息，保留重要消息与近期消息。
/// - summarize：调用 LLMProvider 对旧消息生成摘要，收集流式输出拼接为完整文本。
/// - isImportant：tool call 相关消息（role=tool / 含 toolCallData / 含 toolCallId）或含关键词（记住/重要/注意）的消息为重要。
/// - estimateTokens：复用 String.estimatedTokens 估算。
///
/// 压缩策略：
/// 1. 若总 token 数 ≤ maxTokens，直接返回原列表（不调用 LLM）。
/// 2. 从尾部倒序保留近期消息，直到达到预算的 70%（留 30% 给摘要）。
/// 3. 保留区之前的旧消息中，重要消息原样保留，非重要消息合并生成摘要。
/// 4. 返回 [摘要system消息] + [重要旧消息] + [近期消息]。
final class ContextWindowManager {
    /// LLMProvider，用于生成摘要
    private let llmProvider: LLMProvider
    /// 上下文 token 上限（构造时配置，compress 时也可单独传入 maxTokens 覆盖）
    private let maxContextTokens: Int
    /// 重要关键词列表（content 包含任一即判定为重要）
    private let importantKeywords = ["记住", "重要", "注意"]

    /// 创建 ContextWindowManager 实例
    /// - Parameters:
    ///   - llmProvider: LLMProvider，用于生成消息摘要
    ///   - maxContextTokens: 上下文 token 上限，默认 4000
    init(llmProvider: LLMProvider, maxContextTokens: Int = 4000) {
        self.llmProvider = llmProvider
        self.maxContextTokens = maxContextTokens
    }

    /// 压缩消息列表：保留重要消息与近期消息，将旧的非重要消息摘要化。
    /// - Parameters:
    ///   - messages: 待压缩的消息列表
    ///   - maxTokens: token 上限
    /// - Returns: 压缩后的消息列表（含摘要 system 消息 + 保留的重要旧消息 + 近期消息）
    func compress(messages: [ChatMessage], maxTokens: Int) async throws -> [ChatMessage] {
        // 空列表直接返回
        guard !messages.isEmpty else { return [] }

        // 若总 token 数未超限，直接返回原列表（不调用 LLM）
        let totalTokens = messages.reduce(0) { $0 + estimateTokens($1.content) }
        if totalTokens <= maxTokens {
            return messages
        }

        // 预留预算：maxTokens 的 70% 用于保留近期消息，30% 预留给摘要
        let reserveBudget = Int(Double(maxTokens) * 0.7)

        // 从尾部倒序保留近期消息，直到达到预留预算
        var keepStartIndex = messages.count  // 默认全部保留（若全部未超预算）
        var usedTokens = 0
        for (idx, msg) in messages.enumerated().reversed() {
            let tokens = estimateTokens(msg.content)
            if usedTokens + tokens > reserveBudget {
                keepStartIndex = idx + 1
                break
            }
            usedTokens += tokens
        }

        // 若全部消息都在保留区内（理论上不会发生，因 totalTokens > maxTokens），直接返回
        if keepStartIndex >= messages.count {
            return messages
        }
        // 保留区为空时（单条消息就超预算），keepStartIndex 可能 > 0，仍需处理压缩区
        if keepStartIndex == 0 {
            // 保留区为空，全部消息进入压缩区
            keepStartIndex = messages.count
        }

        // 压缩区：messages[..<keepStartIndex]
        let toCompress = Array(messages.prefix(keepStartIndex))
        // 保留区：messages[keepStartIndex...]
        let recent = Array(messages[keepStartIndex...])

        // 在压缩区中，重要消息原样保留，非重要消息才被摘要
        var importantInCompress: [ChatMessage] = []
        var toSummarize: [ChatMessage] = []
        for msg in toCompress {
            if isImportant(msg) {
                importantInCompress.append(msg)
            } else {
                toSummarize.append(msg)
            }
        }

        // 构造结果：[摘要system消息] + [重要旧消息] + [近期消息]
        var result: [ChatMessage] = []
        if !toSummarize.isEmpty {
            let summary = try await summarize(messages: toSummarize)
            if !summary.isEmpty {
                result.append(ChatMessage(role: "system", content: "【历史对话摘要】\(summary)"))
            }
        }
        result.append(contentsOf: importantInCompress)
        result.append(contentsOf: recent)
        return result
    }

    // MARK: - 测试性调整：以下方法暴露为 internal 便于单测验证压缩逻辑（生产侧行为不变）

    /// 生成消息摘要。调用 LLMProvider 对旧消息生成摘要，收集流式输出拼接为完整文本。
    /// - Parameter messages: 待摘要的消息列表
    /// - Returns: 摘要文本；空列表返回空字符串（不调用 LLM）
    func summarize(messages: [ChatMessage]) async throws -> String {
        guard !messages.isEmpty else { return "" }
        // 拼接消息为对话文本
        let dialogText = messages.map { msg in
            "[\(msg.role)] \(msg.content)"
        }.joined(separator: "\n")
        // 构造摘要请求
        let prompt = "请用一段话总结以下对话的关键信息：\n\(dialogText)"
        let apiMessages = [
            APIMessage(role: "system", content: "你是一个对话摘要助手，请简洁地总结对话内容。", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: prompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]
        let config = ChatConfig(model: "", systemPrompt: "", maxTokens: 512, temperature: 0.3)
        // 收集流式输出拼接为完整摘要
        var summary = ""
        for await chunk in llmProvider.chat(messages: apiMessages, config: config, apiKey: "") {
            summary += chunk
        }
        return summary
    }

    /// 判断消息重要性。tool call 相关消息或含关键词（记住/重要/注意）的消息为重要。
    /// - Parameter message: 待判断的消息
    /// - Returns: 是否为重要消息
    func isImportant(_ message: ChatMessage) -> Bool {
        // tool call 相关消息为重要
        if message.role == "tool" || message.toolCallData != nil || message.toolCallId != nil {
            return true
        }
        // 含重要关键词的消息为重要
        for keyword in importantKeywords {
            if message.content.contains(keyword) {
                return true
            }
        }
        return false
    }

    /// 估算 token 数量。复用 String.estimatedTokens（英文按空格分词 ×1.3，非 ASCII 每字 ×1.5）。
    /// - Parameter text: 待估算的文本
    /// - Returns: 估算的 token 数
    func estimateTokens(_ text: String) -> Int {
        text.estimatedTokens
    }
}
