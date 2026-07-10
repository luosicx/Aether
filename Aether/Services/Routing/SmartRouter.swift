import Foundation

/// 智能路由器：根据消息特征（长度 / 关键词 / 工具 / 图片）自动选择 LLM 模型
/// 策略：工具或图片 → deepseek-chat；长文本或推理关键词 → deepseek-reasoner；其他 → deepseek-chat
enum SmartRouter {
    /// 推理关键词触发列表
    private static let reasonerKeywords: [String] = [
        "为什么", "解释", "分析", "计算", "推导", "证明", "对比", "设计", "重构",
        "why", "explain", "analyze", "reason", "prove"
    ]

    /// 根据消息特征选择模型
    /// - Parameters:
    ///   - input: 用户输入文本
    ///   - toolsEnabled: 是否启用工具调用
    ///   - hasImage: 是否含图片
    /// - Returns: 模型名（"deepseek-chat" 或 "deepseek-reasoner"）
    static func route(input: String, toolsEnabled: Bool, hasImage: Bool) -> String {
        // 工具调用或图片：强制 deepseek-chat（reasoner 对 function calling 不稳定，Vision 用 chat）
        if toolsEnabled || hasImage {
            return APIConfig.defaultModel  // "deepseek-chat"
        }
        // 长文本（>= 50 字符）：用 reasoner 深度推理
        if input.count >= 50 {
            return "deepseek-reasoner"
        }
        // 关键词触发：用 reasoner
        let lowercased = input.lowercased()
        for keyword in reasonerKeywords where lowercased.contains(keyword) {
            return "deepseek-reasoner"
        }
        // 默认：deepseek-chat 快速响应
        return APIConfig.defaultModel
    }
}
