import Foundation

/// Day 13: LLM 供应商抽象。承载各供应商的端点、默认模型、Keychain account 等元数据。
/// 用于多供应商统一管理与切换。enum + Sendable 适配 Swift 6 minimal 并发检查。
enum ModelProvider: String, CaseIterable, Sendable {
    case deepseek
    case qwen
    /// Day 16: 端侧推理（基于 MLX 在设备本地运行，不走 HTTP，断网时可用）
    case onDevice

    /// 用户可见的显示名（用于设置页 Picker）
    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .qwen: return NSLocalizedString("通义千问 Qwen", comment: "")
        case .onDevice: return NSLocalizedString("端侧推理", comment: "")
        }
    }

    /// API 基础 URL
    /// - DeepSeek: 官方 API 端点
    /// - Qwen: 阿里云百炼 DashScope OpenAI 兼容模式端点
    /// - onDevice: 端侧推理不走 HTTP，baseURL 为空
    var baseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .onDevice: return ""
        }
    }

    /// chat completions 接口路径（两家都用 OpenAI 兼容格式，路径一致）
    var chatEndpoint: String { "/chat/completions" }

    /// embeddings 接口路径（两家都用 OpenAI 兼容格式，路径一致）
    var embeddingEndpoint: String { "/embeddings" }

    /// 默认对话模型名
    /// - DeepSeek: deepseek-chat
    /// - Qwen: qwen-plus（速度与质量平衡）
    /// - onDevice: llama-3.2-1b-instruct（端侧本地模型）
    var defaultChatModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .qwen: return "qwen-plus"
        case .onDevice: return "llama-3.2-1b-instruct"
        }
    }

    /// 默认推理模型名
    /// - DeepSeek: deepseek-reasoner
    /// - Qwen: qwq-32b（Qwen 推理系列模型）
    /// - onDevice: 端侧不区分对话/推理模型，复用 chat 模型
    var defaultReasonerModel: String {
        switch self {
        case .deepseek: return "deepseek-reasoner"
        case .qwen: return "qwq-32b"
        case .onDevice: return "llama-3.2-1b-instruct"
        }
    }

    /// 默认嵌入模型名
    /// - DeepSeek: deepseek-embedding（注意：DeepSeek 实际未公开提供 embedding 模型，此处保留向后兼容）
    /// - Qwen: text-embedding-v3
    /// - onDevice: ondevice-hash-embedding（占位 hash 向量，端侧不调用远程 embedding）
    var defaultEmbeddingModel: String {
        switch self {
        case .deepseek: return "deepseek-embedding"
        case .qwen: return "text-embedding-v3"
        case .onDevice: return "ondevice-hash-embedding"
        }
    }

    /// Keychain account 标识，按 provider 隔离 API Key 存储
    /// - onDevice: 端侧推理无需 API Key，占位 account
    var keychainAccount: String {
        switch self {
        case .deepseek: return "apikey-deepseek"
        case .qwen: return "apikey-qwen"
        case .onDevice: return "apikey-ondevice"
        }
    }

    /// 备用供应商（用于自动降级）：
    /// - deepseek ↔ qwen 互为备用
    /// - onDevice: 备用为 deepseek（端侧失败时降级到云端）
    var fallback: ModelProvider {
        switch self {
        case .deepseek: return .qwen
        case .qwen: return .deepseek
        case .onDevice: return .deepseek
        }
    }
}
