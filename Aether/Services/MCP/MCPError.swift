import Foundation

// MARK: - MCP 错误类型

/// MCP 客户端错误，覆盖连接失败、超时、协议错误等场景。
///
/// P2-3 上下文丢失修复：新增 `connectionFailedWithCause` / `transportErrorWithCause` 变体，
/// 在保留 `connectionFailed(String)` / `transportError(String)` 向后兼容的同时，
/// 允许调用方携带原始底层 Error 用于诊断。
enum MCPError: Error, LocalizedError {
    /// 连接失败（如子进程启动失败、SSE 连接失败）
    case connectionFailed(String)
    /// 连接失败，携带错误信息与底层错误。
    /// - Parameters:
    ///   - message: 用户可见的错误信息（通常为 `error.localizedDescription`）
    ///   - underlying: 原始底层错误，保留用于诊断
    case connectionFailedWithCause(message: String, underlying: Error)
    /// 请求超时（未在超时时间内收到响应）
    case timeout
    /// JSON-RPC 协议错误（如方法不存在、参数无效）
    case protocolError(String)
    /// 传输层错误（如写入失败、网络异常）
    case transportError(String)
    /// 传输层错误，携带错误信息与底层错误。
    /// - Parameters:
    ///   - message: 用户可见的错误信息（通常为 `error.localizedDescription`）
    ///   - underlying: 原始底层错误，保留用于诊断
    case transportErrorWithCause(message: String, underlying: Error)
    /// 未连接（尝试在未连接状态下发送请求）
    case notConnected
    /// 响应格式无效（如 JSON 解析失败、缺少必要字段）
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "MCP 连接失败: \(msg)"
        case .connectionFailedWithCause(let msg, _):
            return "MCP 连接失败: \(msg)"
        case .timeout:
            return "MCP 请求超时"
        case .protocolError(let msg):
            return "MCP 协议错误: \(msg)"
        case .transportError(let msg):
            return "MCP 传输错误: \(msg)"
        case .transportErrorWithCause(let msg, _):
            return "MCP 传输错误: \(msg)"
        case .notConnected:
            return "MCP 客户端未连接"
        case .invalidResponse(let msg):
            return "MCP 响应无效: \(msg)"
        }
    }

    /// 诊断描述（含 underlying 信息），用于日志输出，不直接展示给用户。
    /// 调用方在 Logger.error 时应使用此属性而非 errorDescription，以保留底层错误。
    var diagnosticDescription: String {
        switch self {
        case .connectionFailed(let msg):
            return "MCPError.connectionFailed(\(msg))"
        case .connectionFailedWithCause(let msg, let underlying):
            return "MCPError.connectionFailedWithCause(\(msg), underlying: \(type(of: underlying)): \(underlying.localizedDescription))"
        case .timeout:
            return "MCPError.timeout"
        case .protocolError(let msg):
            return "MCPError.protocolError(\(msg))"
        case .transportError(let msg):
            return "MCPError.transportError(\(msg))"
        case .transportErrorWithCause(let msg, let underlying):
            return "MCPError.transportErrorWithCause(\(msg), underlying: \(type(of: underlying)): \(underlying.localizedDescription))"
        case .notConnected:
            return "MCPError.notConnected"
        case .invalidResponse(let msg):
            return "MCPError.invalidResponse(\(msg))"
        }
    }
}
