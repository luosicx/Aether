import Foundation
import AetherFoundation

/// P2-6 Task 8: PromptBuilder —— System Prompt 构建器
///
/// 从 ChatViewModel 抽取的 systemPrompt + 用户偏好 + AI 人设拼接职责 + token 截断职责。
/// 纯值类型（struct），无依赖，不标注 @MainActor（纯函数式逻辑）。
/// 行为等价于 ChatViewModel 原始 buildEffectiveSystemPrompt / limitTokens 实现。
struct PromptBuilder {
    /// 构建 effective systemPrompt：base + 【用户偏好】 + 【AI人设】
    ///
    /// 行为等价于 ChatViewModel 原始 buildEffectiveSystemPrompt 实现：
    /// 1. preferredTone 非空且非"默认"时注入「语气：X」
    /// 2. preferredTools 非空时注入「偏好工具：X、Y」
    /// 3. customFact 非空时注入「自定义事实：X」
    /// 4. aiPersona 非空时注入「名称：X」
    /// 5. aiPersonaDescription 非空时注入「性格描述：X」
    /// 6. 多个偏好以「；」分隔，多个段以「\n」分隔；空 base 不以换行开头
    ///
    /// - Parameters:
    ///   - base: 会话原始 systemPrompt
    ///   - preference: 用户偏好（含人设字段）
    /// - Returns: 拼接后的 effective systemPrompt；空 base + 空 preference 返回空字符串
    func buildEffectiveSystemPrompt(base: String, preference: UserPreference) -> String {
        var prefParts: [String] = []
        if !preference.preferredTone.isEmpty && preference.preferredTone != "默认" {
            prefParts.append(String(format: NSLocalizedString("语气：%@", comment: ""), preference.preferredTone))
        }
        if !preference.preferredTools.isEmpty {
            prefParts.append(String(format: NSLocalizedString("偏好工具：%@", comment: ""), preference.preferredTools.joined(separator: "、")))
        }
        if !preference.customFact.isEmpty {
            prefParts.append(String(format: NSLocalizedString("自定义事实：%@", comment: ""), preference.customFact))
        }
        let prefLine = prefParts.isEmpty ? "" : "【用户偏好】" + prefParts.joined(separator: "；")

        // Task 26: 注入 AI 人设信息
        var personaLines: [String] = []
        if !preference.aiPersona.isEmpty {
            personaLines.append(String(format: NSLocalizedString("名称：%@", comment: ""), preference.aiPersona))
        }
        if !preference.aiPersonaDescription.isEmpty {
            personaLines.append(String(format: NSLocalizedString("性格描述：%@", comment: ""), preference.aiPersonaDescription))
        }
        let personaLine = personaLines.isEmpty ? "" : "【AI人设】" + personaLines.joined(separator: "；")

        // 组合：base + 用户偏好 + AI人设
        var result = base
        if !prefLine.isEmpty {
            result = (result.isEmpty ? "" : result + "\n") + prefLine
        }
        if !personaLine.isEmpty {
            result = (result.isEmpty ? "" : result + "\n") + personaLine
        }
        return result
    }

    /// token 截断：从尾部累加，超过 max 时丢弃最早的消息（保留最近的）
    ///
    /// 行为等价于 ChatViewModel 原始 limitTokens 实现：
    /// 反向遍历消息，累加 token 数，超过 max 时立即 break，保证保留最近的若干条消息。
    ///
    /// - Parameters:
    ///   - messages: 待截断的消息列表（按时间顺序：早 → 晚）
    ///   - max: token 上限；0 表示立即截断返回空数组
    /// - Returns: 截断后的消息列表（保持原始顺序）
    func limitTokens(_ messages: [APIMessage], max: Int) -> [APIMessage] {
        var total = 0
        var result: [APIMessage] = []
        for msg in messages.reversed() {
            let tokens = msg.content.estimatedTokens
            if total + tokens > max { break }
            result.insert(msg, at: 0)
            total += tokens
        }
        return result
    }
}
