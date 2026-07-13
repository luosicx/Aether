import Foundation

/// DeepSeek API 端点与模型名常量集中定义。
struct APIConfig {
    /// DeepSeek API 的基础 URL。
    static let deepseekBaseURL = "https://api.deepseek.com"
    /// chat completions 接口路径。
    static let chatEndpoint = "/chat/completions"
    /// embeddings 接口路径。
    static let embeddingEndpoint = "/embeddings"
    /// 默认对话模型名。
    static let defaultModel = "deepseek-chat"
    /// 默认嵌入模型名。
    static let embeddingModel = "deepseek-embedding"

    /// 遥测日志上传端点占位符。
    /// 安全要求：生产环境必须替换为带认证的端点（STS 临时凭证或预签名 URL），
    /// 禁止直接向可公开写入的 OSS URL 上传。
    static let telemetryUploadEndpoint = "https://aether-logs.oss-cn-hangzhou.aliyuncs.com/logs"
}

/// 单次 chat 请求的配置参数。
struct ChatConfig: Sendable {
    /// 使用的模型名。
    var model: String
    /// 系统提示词，用于设定助手行为。
    var systemPrompt: String
    /// 单次响应最大 token 数。
    var maxTokens: Int
    /// 采样温度，越高越随机。
    var temperature: Double

    /// 默认配置：沿用 `APIConfig.defaultModel`、2048 tokens、0.7 temperature。
    static let `default` = ChatConfig(
        model: APIConfig.defaultModel,
        systemPrompt: "你是一个有帮助的AI助手。",
        maxTokens: 2048,
        temperature: 0.7
    )
}
