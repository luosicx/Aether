import Foundation
import AetherFoundation

/// Task 24: Aether SDK 统一错误类型。
///
/// 覆盖鉴权、限流、上游错误、网络、工具、RAG、配置与端侧推理 8 类场景。
/// 所有 case 均 `Sendable`；`toolExecutionFailed` 携带 `LocalizedError` 字符串化错误以保持 Sendable 安全。
/// 遵循 `Equatable`：单测中可用 `XCTAssertEqual(error as? AetherError, .networkUnreachable)` 断言具体 case。
///
/// P2-3 上下文丢失修复：新增 `ragRetrievalFailedWithCause(reason:underlying:)` 变体，
/// 在保留 `ragRetrievalFailed(reason:)` 向后兼容的同时，允许调用方携带原始底层 Error 用于诊断。
/// 由于 `Error` 不一定 `Equatable`，自定义 `==` 实现仅比较 `reason`，忽略 `underlying`。
public enum AetherError: Error, Sendable, LocalizedError, Equatable {
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
    /// RAG 检索失败（向后兼容变体，不保留原始 Error 上下文）
    case ragRetrievalFailed(reason: String)
    /// RAG 检索失败，携带原因与底层错误。
    /// - Parameters:
    ///   - reason: 用户可见的错误信息（通常为 `error.localizedDescription`）
    ///   - underlying: 原始底层错误，保留用于诊断（不参与 Equatable 判等）
    case ragRetrievalFailedWithCause(reason: String, underlying: Error)
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
        case .ragRetrievalFailedWithCause(let reason, _):
            return String(format: NSLocalizedString("知识库检索失败：%@", comment: ""), reason)
        case .invalidConfig(let reason):
            return String(format: NSLocalizedString("配置无效：%@", comment: ""), reason)
        case .onDeviceInferenceFailed(let error):
            return error.errorDescription
        }
    }

    /// 自定义 Equatable 实现。
    /// `ragRetrievalFailedWithCause` 仅比较 `reason`，忽略 `underlying` Error
    /// （Error 不一定 Equatable，无法参与判等）。
    public static func == (lhs: AetherError, rhs: AetherError) -> Bool {
        switch (lhs, rhs) {
        case (.authFailed(let l), .authFailed(let r)):
            return l == r
        case (.rateLimited(let l), .rateLimited(let r)):
            return l == r
        case (.providerError(let lc, let lm), .providerError(let rc, let rm)):
            return lc == rc && lm == rm
        case (.networkUnreachable, .networkUnreachable):
            return true
        case (.toolExecutionFailed(let ln, let ld), .toolExecutionFailed(let rn, let rd)):
            return ln == rn && ld == rd
        case (.ragRetrievalFailed(let l), .ragRetrievalFailed(let r)):
            return l == r
        case (.ragRetrievalFailedWithCause(let l, _), .ragRetrievalFailedWithCause(let r, _)):
            return l == r
        case (.invalidConfig(let l), .invalidConfig(let r)):
            return l == r
        case (.onDeviceInferenceFailed(let l), .onDeviceInferenceFailed(let r)):
            return l == r
        default:
            return false
        }
    }

    // MARK: - 从底层错误构造

    /// 从 `LLMError` 构造 `AetherError`
    public static func from(_ llmError: LLMError) -> AetherError {
        switch llmError {
        case .networkError:
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
