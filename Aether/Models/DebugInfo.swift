import Foundation

// MARK: - Day 9: 调试信息数据结构
/// 封装一次完整请求流程的调试信息，由 ChatViewModel 在发送消息时填充
struct DebugInfo {
    /// 最近一次发送的完整 prompt JSON
    let promptJSON: String
    /// 最近一次 DeepSeek API 原始响应
    let apiResponse: String
    /// 最近一次 embedding 向量维度（无 embedding 时为 0）
    let embeddingDimension: Int
    /// 最近一次工具调用列表
    let toolCalls: [ToolCallDebug]
    // Day 13: 新增 provider / fallbackUsed 字段
    let provider: String?
    let fallbackUsed: Bool

    struct ToolCallDebug: Identifiable {
        let id = UUID()
        let toolName: String
        let arguments: String
        let result: String
    }
}
