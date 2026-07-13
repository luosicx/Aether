import Foundation

/// Day 16: 端侧离线 LLM Provider。实现 LLMProvider 协议，将请求转发给 MLXInferenceEngine。
/// - chat：将 messages 按 Llama-3 chat template 拼接为 prompt，调用 MLX 流式生成
/// - chat(tools:)：端侧模型不支持工具调用，发 .llmErrorOccurred 通知并结束流
/// - embed：返回基于 hash 的 384 维占位向量（端侧不调用远程 embedding）
/// nonisolated 设计允许跨 actor 调用，与 DeepSeekClient/QwenClient 一致。
nonisolated final class OfflineLLMProvider: LLMProvider, @unchecked Sendable {

    /// 纯文本 chat 流：拼接 Llama-3 prompt → 调用 MLXInferenceEngine.generate 流式生成。
    /// 若模型未加载且 OnDeviceConfig 中有 modelPath，会先自动加载模型。
    func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                let storedPath = Self.loadStoredModelPath()
                // 自动加载：模型未加载且有路径时，先加载（失败则交由 generate 输出占位提示）
                var effectivePath = storedPath
                if !(await MLXInferenceEngine.shared.isLoaded), let path = storedPath {
                    do {
                        try await MLXInferenceEngine.shared.loadModel(path: path)
                    } catch {
                        // 加载失败：清空路径避免 generate 重复尝试，交由 generate 输出提示
                        effectivePath = nil
                    }
                }
                // 按 Llama-3 chat template 拼接完整 prompt
                let prompt = Self.buildLlama3Prompt(messages: messages, systemPrompt: config.systemPrompt)
                // 调用 MLX 引擎流式生成（maxTokens/temperature 用 config 传入值）
                let stream = await MLXInferenceEngine.shared.generate(
                    prompt: prompt,
                    maxTokens: config.maxTokens,
                    temperature: config.temperature,
                    modelPath: effectivePath
                )
                for await token in stream {
                    if Task.isCancelled { break }
                    continuation.yield(token)
                }
                continuation.finish()
            }
            // 流被外部终止时取消内部 Task，释放 MLX 推理资源
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 带工具调用 chat 流：端侧模型不支持工具调用。
    /// tools 非空时发 .llmErrorOccurred 通知（LLMError 无 unsupported case，复用 llmErrorOccurred）；
    /// tools 为空时退化为纯文本 chat，包装为 ParsedChunk。
    func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
        AsyncStream { continuation in
            if !tools.isEmpty {
                // 端侧模型不支持工具调用，发错误通知让 ChatViewModel 自动降级到云端
                let err = LLMError.llmErrorOccurred(NSLocalizedString("端侧模型不支持工具调用，已自动切换到云端", comment: ""))
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .llmErrorOccurred,
                        object: nil,
                        userInfo: ["error": err]
                    )
                }
                continuation.finish()
                return
            }
            // tools 为空：退化为纯文本 chat，包装为 ParsedChunk
            let task = Task {
                let storedPath = Self.loadStoredModelPath()
                // 自动加载：模型未加载且有路径时，先加载
                var effectivePath = storedPath
                if !(await MLXInferenceEngine.shared.isLoaded), let path = storedPath {
                    do {
                        try await MLXInferenceEngine.shared.loadModel(path: path)
                    } catch {
                        effectivePath = nil
                    }
                }
                let prompt = Self.buildLlama3Prompt(messages: messages, systemPrompt: config.systemPrompt)
                let stream = await MLXInferenceEngine.shared.generate(
                    prompt: prompt,
                    maxTokens: config.maxTokens,
                    temperature: config.temperature,
                    modelPath: effectivePath
                )
                for await token in stream {
                    if Task.isCancelled { break }
                    continuation.yield(ParsedChunk(content: token, toolCalls: nil))
                }
                continuation.finish()
            }
            // 流被外部终止时取消内部 Task，释放 MLX 推理资源
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 批量文本嵌入：返回基于 hash 的 384 维占位向量。
    /// 端侧不调用远程 embedding API，用确定性 hash 为每条文本生成固定向量，
    /// 归一化后可作为语义缓存的键（精度有限，仅用于离线兜底）。
    func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
        // 空入参短路返回空数组
        guard !texts.isEmpty else { return [] }
        return texts.map { text in
            // 384 维占位向量，与远程 embedding 维度对齐
            var vec = [Float](repeating: 0, count: 384)
            // 用字符 unicode 值与位置索引填充各维度（确定性，相同文本生成相同向量）
            for (i, scalar) in text.unicodeScalars.enumerated() {
                let idx = (Int(scalar.value) + i) % 384
                vec[idx] += Float(scalar.value % 17) / 17.0
            }
            // L2 归一化，便于余弦相似度计算
            let norm = (vec.reduce(Float(0)) { $0 + $1 * $1 }).squareRoot()
            if norm > 0 {
                vec = vec.map { $0 / norm }
            }
            return vec
        }
    }

    /// 从 UserDefaults 读取持久化的模型路径（OnDeviceConfig.modelPath）。
    /// OfflineLLMProvider 无 settingsVM 注入，直接读 UserDefaults 获取配置。
    /// - Returns: 持久化存储的模型路径，无配置或解码失败时返回 nil
    private static func loadStoredModelPath() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: OnDeviceConfig.userDefaultsKey) else {
            return nil
        }
        let config = (try? JSONDecoder().decode(OnDeviceConfig.self, from: data)) ?? .default
        return config.modelPath
    }

    /// 按 Llama-3 chat template 拼接完整 prompt。
    /// 格式：`<|begin_of_text|><|start_header_id|>{role}<|end_header_id|>\n\n{content}<|eot_id|>`
    /// 最后追加空的 assistant header，引导模型生成回复。
    /// - Parameters:
    ///   - messages: API 消息列表（含 system / user / assistant / tool）
    ///   - systemPrompt: 系统提示词（若消息中已含 system 则不重复拼接）
    /// - Returns: 拼接后的完整 prompt 字符串
    private static func buildLlama3Prompt(messages: [APIMessage], systemPrompt: String) -> String {
        var prompt = "<|begin_of_text|>"
        // 若消息中未含 system 但有 systemPrompt，则前置 system 段
        let hasSystemMessage = messages.contains { $0.role == "system" }
        if !hasSystemMessage, !systemPrompt.isEmpty {
            prompt += "<|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
        }
        // 逐条消息按角色拼接
        for msg in messages {
            prompt += "<|start_header_id|>\(msg.role)<|end_header_id|>\n\n\(msg.content)<|eot_id|>"
        }
        // 追加空的 assistant header，引导模型从 assistant 角色开始生成
        prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return prompt
    }
}
