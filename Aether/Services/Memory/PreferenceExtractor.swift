import Foundation
import AetherFoundation

/// Task 6: 从对话历史中提取出的单条用户偏好。
/// category 取值："tone" / "tool" / "fact" / "persona"。
struct PreferenceExtraction: Codable, Hashable {
    /// 偏好类别："tone"（语气）/ "tool"（工具）/ "fact"（事实）/ "persona"（人设）
    var category: String
    /// 偏好值（如"正式"、工具名、"我是素食者" 等）
    var value: String
    /// 置信度 0.0 - 1.0
    var confidence: Double
}

/// Task 6: 用户偏好自动提取器。调用 LLM 分析对话历史，提取用户的语气偏好、常用工具、个人事实与人设偏好。
///
/// 设计要点：
/// - 通过 `LLMProvider` 抽象注入，便于测试时替换为 mock
/// - 构造 prompt 时要求 LLM 返回 JSON 数组（每项含 category/value/confidence）
/// - 解析阶段对 LLM 返回做容错处理（剔除 ```json fence、定位最外层方括号、缺失字段使用默认值）
final class PreferenceExtractor {
    /// LLM 供应商
    private let llmProvider: LLMProvider

    /// 解析失败时抛出的错误
    enum PreferenceExtractionError: Error, LocalizedError {
        /// LLM 返回内容为空
        case emptyResponse
        /// 无法从响应中提取 JSON 数组
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "LLM 返回内容为空，无法解析偏好"
            case .invalidJSON(let detail):
                return "LLM 返回内容无法解析为偏好数组：\(detail)"
            }
        }
    }

    /// 创建 PreferenceExtractor 实例
    /// - Parameter llmProvider: LLM 供应商
    init(llmProvider: LLMProvider) {
        self.llmProvider = llmProvider
    }

    /// 从对话历史中提取用户偏好
    /// - Parameter messages: 对话消息列表（通常为最近 N 条）
    /// - Returns: 提取出的偏好列表
    /// - Throws: `PreferenceExtractionError`：LLM 返回空、JSON 解析失败
    func extract(from messages: [ChatMessage]) async throws -> [PreferenceExtraction] {
        // 1. 构造 prompt
        let prompt = buildExtractionPrompt(messages: messages)

        // 2. 调用 LLM 流式获取响应，累积为完整字符串
        let apiMessages: [APIMessage] = [
            APIMessage(role: "system",
                       content: "你是一个用户偏好分析助手。分析对话历史，提取用户的语气偏好、常用工具、个人事实与人设偏好，以 JSON 数组形式返回。",
                       images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: prompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]
        let config = ChatConfig(
            model: ChatConfig.default.model,
            systemPrompt: "你是一个用户偏好分析助手。",
            maxTokens: 1024,
            temperature: 0.3
        )
        let apiKey = KeychainManager.shared.getAPIKey() ?? ""
        let stream = llmProvider.chat(messages: apiMessages, config: config, apiKey: apiKey)
        var responseText = ""
        for await chunk in stream {
            responseText += chunk
        }

        // 3. 校验非空
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PreferenceExtractionError.emptyResponse
        }

        // 4. 解析为偏好列表
        return try parsePreferences(from: responseText)
    }

    // MARK: - 内部方法（internal 便于测试）

    /// 生成偏好提取 prompt。指示 LLM 分析对话历史并返回 JSON 数组。
    /// - Parameter messages: 对话消息列表
    /// - Returns: 完整 prompt 字符串
    func buildExtractionPrompt(messages: [ChatMessage]) -> String {
        // 拼接对话历史（仅保留 user / assistant 文本内容）
        var historyLines: [String] = []
        for msg in messages {
            guard msg.role == "user" || msg.role == "assistant" else { continue }
            let roleLabel = msg.role == "user" ? "用户" : "助手"
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            historyLines.append("\(roleLabel)：\(content)")
        }
        let history = historyLines.joined(separator: "\n")

        return """
        请分析以下对话历史，提取用户的偏好信息，并以 JSON 数组形式返回（不要包含任何额外文本或 markdown 代码块标记）。

        对话历史：
        \(history)

        每条偏好的 JSON 结构如下：
        {
          \"category\": \"偏好类别，取值：tone / tool / fact / persona\",
          \"value\": \"偏好值\",
          \"confidence\": \"置信度，0.0 - 1.0 之间的数字\"
        }

        类别说明：
        - tone：用户的语气偏好（如"正式"、"轻松"、"幽默"）
        - tool：用户经常使用或偏好的工具名（如"calculate"、"web_search"）
        - fact：用户的个人事实（如"我是素食者"、"我在北京工作"）
        - persona：用户期望的 AI 人设（如"温柔的姐姐"、"严谨的学者"）

        要求：
        1. 仅提取对话中明确体现的偏好，不要臆测
        2. 若对话历史中无明显偏好，返回空数组 []
        3. confidence 反映提取置信度：1.0 为用户明确表达，0.5 为可推断
        4. 只返回 JSON 数组，不要包含任何 markdown 代码块标记（如 ```json）或额外说明文字
        """
    }

    /// 解析 LLM 返回的偏好 JSON
    /// - Parameter response: LLM 完整响应文本
    /// - Returns: 解析后的偏好列表
    /// - Throws: `PreferenceExtractionError.invalidJSON`：无法提取或解码 JSON
    func parsePreferences(from response: String) throws -> [PreferenceExtraction] {
        // 1. 剔除可能存在的 markdown 代码块标记（```json ... ```），定位最外层方括号
        let jsonString = extractJSONArray(from: response)

        guard !jsonString.isEmpty else {
            throw PreferenceExtractionError.invalidJSON("响应中未找到 JSON 数组")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw PreferenceExtractionError.invalidJSON("无法将响应转为 Data")
        }

        // 2. 解码为 [PreferenceExtraction]
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([PreferenceExtraction].self, from: data)
        } catch {
            throw PreferenceExtractionError.invalidJSON("解码失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 私有辅助

    /// 从响应文本中提取 JSON 数组字符串，剥离 markdown 代码块标记与多余文本。
    /// - Parameter response: LLM 响应文本
    /// - Returns: 提取出的 JSON 数组字符串；未找到时返回空字符串
    private func extractJSONArray(from response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // 剥离 ```json ... ``` 或 ``` ... ``` 代码块标记
        if text.hasPrefix("```") {
            // 移除首行（```json 或 ```）
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            } else {
                // 整段就是 ``` 开头但无换行：剥离前 3 个字符
                text = String(text.dropFirst(3))
            }
            // 移除结尾的 ```
            if text.hasSuffix("```") {
                text = String(text.dropLast(3))
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 定位最外层的 [ 与 ]，截取之间的内容（含括号本身）
        guard let firstBracket = text.firstIndex(of: "["),
              let lastBracket = text.lastIndex(of: "]") else {
            return ""
        }
        return String(text[firstBracket...lastBracket])
    }
}
