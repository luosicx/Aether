import Foundation
import AetherFoundation

/// Task 24: Aether SDK 统一错误类型。
///
/// 覆盖鉴权、限流、上游错误、网络、工具、RAG、配置与端侧推理 8 类场景。
/// 所有 case 均 `Sendable`；`toolExecutionFailed` 携带 `LocalizedError` 字符串化错误以保持 Sendable 安全。
public enum AetherError: Error, Sendable, LocalizedError {
    /// 鉴权失败（HTTP 401 / token 无效 / 签名错误）
    case authFailed(reason: String)
    /// 触发限流（HTTP 429），携带建议重试秒数
    case rateLimited(retryAfter: TimeInterval)
    /// 上游 LLM Provider 错误（4xx/5xx），携带状态码与原始消息
    case providerError(code: Int, message: String)
    /// 网络不可达（离线 / DNS 失败 / 超时）
    case networkUnreachable
    /// 工具执行失败，携带工具名与底层错误描述
    case toolExecutionFailed(name: String, errorDescription: String)
    /// RAG 检索失败
    case ragRetrievalFailed(reason: String)
    /// 配置无效（apiKey 缺失 / baseURL 非法 / 模型名空等）
    case invalidConfig(reason: String)
    /// 端侧推理失败（包装 `OnDeviceError`）
    case onDeviceInferenceFailed(error: OnDeviceError)

    /// 用户友好的错误描述
    public var errorDescription: String? {
        switch self {
        case .authFailed(let reason):
            return String(format: NSLocalizedString("鉴权失败：%@", comment: ""), reason)
        case .rateLimited(let retryAfter):
            return String(format: NSLocalizedString("请求过于频繁，请 %d 秒后重试", comment: ""), Int(retryAfter))
        case .providerError(let code, let message):
            return String(format: NSLocalizedString("服务异常（%d）：%@", comment: ""), code, message)
        case .networkUnreachable:
            return NSLocalizedString("网络不可达，请检查网络后重试", comment: "")
        case .toolExecutionFailed(let name, let desc):
            return String(format: NSLocalizedString("工具 %@ 执行失败：%@", comment: ""), name, desc)
        case .ragRetrievalFailed(let reason):
            return String(format: NSLocalizedString("知识库检索失败：%@", comment: ""), reason)
        case .invalidConfig(let reason):
            return String(format: NSLocalizedString("配置无效：%@", comment: ""), reason)
        case .onDeviceInferenceFailed(let error):
            return error.errorDescription
        }
    }

    // MARK: - 从底层错误构造

    /// 从 `LLMError` 构造 `AetherError`
    public static func from(_ llmError: LLMError) -> AetherError {
        switch llmError {
        case .networkError(let msg):
            return .networkUnreachable
        case .apiKeyMissing, .apiKeyInvalid:
            return .authFailed(reason: llmError.userMessage)
        case .apiError(let code, let msg):
            if code == 429 {
                return .rateLimited(retryAfter: 5)
            }
            if code == 401 {
                return .authFailed(reason: msg)
            }
            return .providerError(code: code, message: msg)
        case .timeout:
            return .networkUnreachable
        case .unknown(let msg):
            return .providerError(code: -1, message: msg)
        case .rateLimited(let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .llmErrorOccurred(let msg):
            return .providerError(code: -1, message: msg)
        }
    }

    // MARK: - 可重试判断

    /// 是否属于可重试错误（网络错误或 5xx / 429）
    public var isRetryable: Bool {
        switch self {
        case .networkUnreachable:
            return true
        case .rateLimited:
            return true
        case .providerError(let code, _):
            return code == 503 || code == 502 || code == 504
        default:
            return false
        }
    }
}
