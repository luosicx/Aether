import Foundation

/// 工具执行确认服务协议。
/// 在敏感/危险工具实际执行前调用，返回是否继续执行。
protocol ToolConfirmationService: AnyObject {
    /// 请求用户确认是否执行指定工具。
    /// - Parameters:
    ///   - tool: 待执行的工具。
    ///   - arguments: 传入工具的参数（JSON 反序列化后的字典）。
    /// - Returns: 用户确认则返回 true，取消返回 false。
    func confirm(tool: ToolProtocol, arguments: [String: Any]) async -> Bool
}

/// 默认确认服务占位实现：直接放行，便于测试与后续 UI 替换。
final class DefaultToolConfirmationService: ToolConfirmationService {
    func confirm(tool: ToolProtocol, arguments: [String: Any]) async -> Bool {
        #if DEBUG
        print("[ToolConfirmation] \(tool.definition.name) requires confirmation (risk: \(tool.riskLevel.rawValue)). Auto-approved in default service.")
        #endif
        return true
    }
}
