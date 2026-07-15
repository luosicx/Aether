import Foundation
import AetherFoundation

/// Task 9: 目标分解器。调用 LLM 将用户原始目标分解为可执行的子任务列表。
///
/// 设计要点：
/// - 通过 `LLMProvider` 抽象注入，便于测试时替换为 mock
/// - 构造 prompt 时要求 LLM 返回 JSON 数组（每项含 title/description/dependencies/toolName/order）
/// - 解析阶段对 LLM 返回做容错处理（缺失字段使用默认值、剔除 ```json fence）
final class GoalDecomposer {
    /// LLM 供应商
    private let llmProvider: LLMProvider

    /// 解析失败时抛出的错误
    enum DecomposeError: Error, LocalizedError {
        /// LLM 返回内容为空
        case emptyResponse
        /// 无法从响应中提取 JSON 数组
        case invalidJSON(String)
        /// 解析后的子任务列表为空
        case noSubTasks

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "LLM 返回内容为空，无法解析子任务"
            case .invalidJSON(let detail):
                return "LLM 返回内容无法解析为 JSON 数组：\(detail)"
            case .noSubTasks:
                return "目标分解后未得到任何子任务"
            }
        }
    }

    /// 创建 GoalDecomposer 实例
    /// - Parameter llmProvider: LLM 供应商
    init(llmProvider: LLMProvider) {
        self.llmProvider = llmProvider
    }

    /// 将目标分解为子任务列表
    /// - Parameter goal: 用户原始目标文本
    /// - Returns: 排序后的子任务列表（按 order 升序）
    /// - Throws: `DecomposeError`：LLM 返回空、JSON 解析失败、解析后子任务列表为空
    func decompose(goal: String) async throws -> [SubTask] {
        // 1. 构造 prompt
        let prompt = buildDecompositionPrompt(goal: goal)

        // 2. 调用 LLM 流式获取响应，累积为完整字符串
        let messages: [APIMessage] = [
            APIMessage(role: "system",
                       content: "你是一个目标分解助手。将用户目标拆分为 3-7 个可执行的子任务，以 JSON 数组形式返回。",
                       images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: prompt, images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]
        let config = ChatConfig(
            model: ChatConfig.default.model,
            systemPrompt: "你是一个目标分解助手。",
            maxTokens: 1024,
            temperature: 0.3
        )
        let stream = llmProvider.chat(messages: messages, config: config, apiKey: "")
        var responseText = ""
        for await chunk in stream {
            responseText += chunk
        }

        // 3. 校验非空
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecomposeError.emptyResponse
        }

        // 4. 解析为子任务列表
        var subTasks = try parseSubTasks(from: responseText)

        // 5. 容错：若所有 order 均为 0（LLM 未填），按数组顺序重新赋值
        if subTasks.allSatisfy({ $0.order == 0 }) {
            for index in subTasks.indices {
                subTasks[index].order = index
            }
        }

        // 6. 按 order 升序排序，保证执行顺序稳定
        subTasks.sort { $0.order < $1.order }

        guard !subTasks.isEmpty else {
            throw DecomposeError.noSubTasks
        }

        return subTasks
    }

    // MARK: - 内部方法（internal 便于测试）

    /// 生成目标分解 prompt。指示 LLM 返回 JSON 数组，并约定字段格式。
    /// - Parameter goal: 用户原始目标
    /// - Returns: 完整 prompt 字符串
    func buildDecompositionPrompt(goal: String) -> String {
        """
        请将以下目标分解为可执行的子任务，并以 JSON 数组形式返回（不要包含任何额外文本或 markdown 代码块标记）。

        目标：\(goal)

        每个子任务的 JSON 结构如下：
        {
          \"title\": \"子任务简短标题\",
          \"description\": \"子任务详细描述\",
          \"dependencies\": [\"依赖的子任务在数组中的索引，从 0 开始\"],
          \"toolName\": \"可选，使用的工具名；无工具填 null\",
          \"order\": \"执行顺序，整数，从 0 开始递增\"
        }

        要求：
        1. 子任务数量在 3-7 个之间
        2. dependencies 数组中的数字对应其他子任务在数组中的索引，表示这些子任务必须先完成
        3. order 字段从 0 开始递增
        4. 只返回 JSON 数组，不要包含任何 markdown 代码块标记（如 ```json）或额外说明文字
        """
    }

    /// 解析 LLM 返回的子任务 JSON
    /// - Parameter response: LLM 完整响应文本
    /// - Returns: 解析后的子任务列表
    /// - Throws: `DecomposeError.invalidJSON`：无法提取或解码 JSON
    func parseSubTasks(from response: String) throws -> [SubTask] {
        // 1. 剔除可能存在的 markdown 代码块标记（```json ... ```）
        let jsonString = extractJSONArray(from: response)

        guard !jsonString.isEmpty else {
            throw DecomposeError.invalidJSON("响应中未找到 JSON 数组")
        }

        // 2. 解析为临时结构（dependencies 先按 Int 解析，因为 prompt 要求 LLM 返回索引）
        guard let data = jsonString.data(using: .utf8) else {
            throw DecomposeError.invalidJSON("无法将响应转为 Data")
        }

        let decoder = JSONDecoder()
        do {
            // 先尝试直接解码为 [SubTask]：若 LLM 已将 dependencies 写为 UUID 数组则直接成功
            let subTasks = try decoder.decode([SubTask].self, from: data)
            return subTasks
        } catch {
            // 直接解码失败：尝试用索引映射模式（LLM 通常返回 dependencies 为 [Int] 索引数组）
            return try parseWithIndexDependencies(data: data)
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

    /// 使用索引依赖模式解析子任务：LLM 返回的 dependencies 为 [Int]（子任务在数组中的索引），
    /// 此方法将索引转换为对应子任务的 UUID。
    /// - Parameter data: JSON 数据
    /// - Returns: 解析后的子任务列表，dependencies 已转为 UUID
    /// - Throws: `DecomposeError.invalidJSON`：解码失败
    private func parseWithIndexDependencies(data: Data) throws -> [SubTask] {
        struct RawSubTask: Decodable {
            let title: String
            let description: String?
            let status: SubTaskStatus?
            let dependencies: [Int]?
            let toolName: String?
            let result: String?
            let order: Int?
        }

        let decoder = JSONDecoder()
        let rawTasks: [RawSubTask]
        do {
            rawTasks = try decoder.decode([RawSubTask].self, from: data)
        } catch {
            throw DecomposeError.invalidJSON("无法解码为子任务数组：\(error.localizedDescription)")
        }

        // 第一遍：先创建 SubTask（不带 dependencies，dependencies 留空）
        var subTasks: [SubTask] = rawTasks.enumerated().map { index, raw in
            var task = SubTask(
                title: raw.title,
                description: raw.description ?? "",
                dependencies: [],
                toolName: raw.toolName,
                order: raw.order ?? index
            )
            task.status = raw.status ?? .pending
            if let result = raw.result {
                task.result = result
            }
            return task
        }

        // 第二遍：将 [Int] 索引依赖映射为 UUID 依赖
        for (index, raw) in rawTasks.enumerated() where index < subTasks.count {
            guard let depIndices = raw.dependencies else { continue }
            var depIDs: [UUID] = []
            for depIndex in depIndices {
                // depIndex 必须在合法范围内，且不能引用自身
                guard depIndex >= 0, depIndex < subTasks.count, depIndex != index else { continue }
                depIDs.append(subTasks[depIndex].id)
            }
            subTasks[index].dependencies = depIDs
        }

        return subTasks
    }
}
