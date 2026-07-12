import Foundation

/// 用户对工具执行确认弹窗的选择。
enum ToolConfirmationDecision: String, Sendable {
    /// 仅允许本次执行。
    case allowOnce
    /// 拒绝本次执行。
    case deny
    /// 允许本次执行，并在设置中永久启用该工具（后续不再弹窗）。
    case alwaysAllow
}

/// 工具执行确认服务协议。
///
/// 实现方负责向用户展示确认弹窗并返回用户决定。协议设计为可注入，
/// 因此 Tool 不直接写 UI，测试也可以注入 Mock 实现。
@MainActor
protocol ToolConfirmationService: AnyObject {
    /// 请求用户确认是否执行工具。
    ///
    /// - Parameters:
    ///   - toolName: 工具名（如 `run_terminal_command`）。
    ///   - summary: 展示给用户的操作摘要（已脱敏）。
    /// - Returns: 用户决定。
    func requestConfirmation(toolName: String, summary: String) async -> ToolConfirmationDecision
}

// MARK: - 默认实现（异步直接返回，用于测试或无 UI 场景）

/// 直接返回预设决定的确认服务，用于单元测试或无需弹窗的自动化场景。
@MainActor
final class ImmediateToolConfirmationService: ToolConfirmationService {
    private let decision: ToolConfirmationDecision

    init(decision: ToolConfirmationDecision) {
        self.decision = decision
    }

    func requestConfirmation(toolName: String, summary: String) async -> ToolConfirmationDecision {
        decision
    }
}
