import Foundation
import AetherServices

/// P2-6 Task 9: InjectionGuard —— 提示注入检测协调器
///
/// 从 ChatViewModel 抽取的提示注入检测弹窗 + 决策回调职责。
/// 封装 `showInjectionWarning` / `injectionWarningMessage` / `pendingInjectionDecision` 三个状态
/// （通过闭包回调同步到 ChatViewModel 的 @Observable 属性，不直接持有）。
///
/// 行为契约（与原 ChatViewModel.sendMessage 中注入检测块等价）：
/// 1. `detect(text:)` 调用 `PromptInjectionDetector.isSuspicious`，命中时：
///    - 通过 `onInjectionWarningMessageChange` 通知 `reason(for:)` 文案（缺失时回退到默认本地化字符串）
///    - 通过 `onShowInjectionWarningChange(true)` 通知显示警告弹窗
///    - 返回 `true`
/// 2. 调用方在 `detect` 返回 `true` 后调用 `setDecisionHandler(handler)`：
///    - 内部保存 `decisionHandler`（真正的决策回调）
///    - 通过 `onPendingInjectionDecisionChange` 暴露一个包装闭包给外部（View 入口）
///      包装闭包会按 Bool 参数路由到 `proceed()` / `cancel()`，从而完成状态清理 + 触发 handler
/// 3. 用户响应（View 调用 `pendingInjectionDecision?(bool)` 或测试直接调用 `proceed()` / `cancel()`）：
///    - `proceed()` → 清理状态 + `decisionHandler?(true)`  → ChatViewModel 调用 `sendMessageConfirmed`
///    - `cancel()`  → 清理状态 + `decisionHandler?(false)` → ChatViewModel 跳过发送
///
/// 并发边界：本类标注 `@MainActor`，所有闭包在主 actor 上调用；
/// 闭包使用 `[weak self]` 防止循环引用（与 VoiceCoordinator 同模式）。
/// 用户决策回调类型：参数 true=继续发送 / false=取消。
/// 使用 typealias 显式标注 @MainActor，避免在嵌套类型签名中重复书写 `@MainActor (Bool) -> Void` 导致语法歧义。
typealias InjectionDecisionHandler = @MainActor (Bool) -> Void

@MainActor
final class InjectionGuard: Coordinator {
    /// showInjectionWarning 变更回调（ChatViewModel 设置，更新 @Observable var showInjectionWarning）
    private let onShowInjectionWarningChange: (Bool) -> Void
    /// injectionWarningMessage 变更回调（ChatViewModel 设置，更新 @Observable var injectionWarningMessage）
    private let onInjectionWarningMessageChange: (String) -> Void
    /// pendingInjectionDecision 变更回调（ChatViewModel 设置，更新 @Observable var pendingInjectionDecision）
    /// 暴露的闭包为包装闭包：调用 wrapper(true) → proceed()，调用 wrapper(false) → cancel()
    private let onPendingInjectionDecisionChange: (InjectionDecisionHandler?) -> Void

    /// 真正的决策回调（由 ChatViewModel 在 setDecisionHandler 中注入）。
    /// proceed/cancel 触发后调用，参数 true=继续发送 / false=取消。
    @ObservationIgnored
    private var decisionHandler: InjectionDecisionHandler?

    /// 构造器
    /// - Parameters:
    ///   - onShowInjectionWarningChange: showInjectionWarning 变更回调（@MainActor）
    ///   - onInjectionWarningMessageChange: injectionWarningMessage 变更回调（@MainActor）
    ///   - onPendingInjectionDecisionChange: pendingInjectionDecision 变更回调（@MainActor）
    init(onShowInjectionWarningChange: @escaping (Bool) -> Void,
         onInjectionWarningMessageChange: @escaping (String) -> Void,
         onPendingInjectionDecisionChange: @escaping (InjectionDecisionHandler?) -> Void) {
        self.onShowInjectionWarningChange = onShowInjectionWarningChange
        self.onInjectionWarningMessageChange = onInjectionWarningMessageChange
        self.onPendingInjectionDecisionChange = onPendingInjectionDecisionChange
    }

    /// 检测文本是否疑似提示注入。命中时通过回调更新 injectionWarningMessage 与 showInjectionWarning=true。
    /// 不修改 decisionHandler / pendingInjectionDecision（由调用方在 detect 返回 true 后通过 setDecisionHandler 设置）。
    /// - Parameter text: 用户输入文本
    /// - Returns: true 若疑似注入；false 若正常
    @discardableResult
    func detect(text: String) -> Bool {
        guard PromptInjectionDetector.isSuspicious(text) else { return false }
        let message = PromptInjectionDetector.reason(for: text)
            ?? NSLocalizedString("检测到当前输入可能包含提示注入指令，继续发送可能导致工具被异常调用。是否继续？", comment: "")
        onInjectionWarningMessageChange(message)
        onShowInjectionWarningChange(true)
        return true
    }

    /// 设置用户决策回调。在 detect 返回 true 后由调用方设置。
    /// 同时通过 onPendingInjectionDecisionChange 暴露一个包装闭包给外部（View 调用入口），
    /// 包装闭包会按 Bool 参数路由到 proceed()/cancel()，从而完成状态清理与 handler 触发。
    /// - Parameter handler: 用户决策回调。proceed 时调用 handler(true)；cancel 时调用 handler(false)。
    func setDecisionHandler(_ handler: @escaping InjectionDecisionHandler) {
        decisionHandler = handler
        // 包装闭包：View 调用 pendingInjectionDecision?(bool) 时路由到 proceed/cancel
        let wrapper: @MainActor (Bool) -> Void = { [weak self] shouldContinue in
            if shouldContinue {
                self?.proceed()
            } else {
                self?.cancel()
            }
        }
        onPendingInjectionDecisionChange(wrapper)
    }

    /// 用户点击「继续发送」。触发 decisionHandler(true) 并清理警告状态。
    /// 行为等价于原 ChatViewModel 中 pendingInjectionDecision 闭包的 shouldContinue=true 分支
    /// （清理 showInjectionWarning / pendingInjectionDecision + 调用 sendMessageConfirmed）。
    func proceed() {
        let handler = decisionHandler
        clear()
        handler?(true)
    }

    /// 用户点击「取消」。触发 decisionHandler(false) 并清理状态。
    /// 行为等价于原 ChatViewModel 中 pendingInjectionDecision 闭包的 shouldContinue=false 分支
    /// （清理 showInjectionWarning / pendingInjectionDecision，不调用 sendMessageConfirmed）。
    func cancel() {
        let handler = decisionHandler
        clear()
        handler?(false)
    }

    /// 清理警告状态：showInjectionWarning=false / pendingInjectionDecision=nil / decisionHandler=nil。
    /// proceed / cancel 在触发 handler 前调用，确保状态先复位（与原闭包内 `self.showInjectionWarning = false; self.pendingInjectionDecision = nil` 等价）。
    private func clear() {
        onShowInjectionWarningChange(false)
        decisionHandler = nil
        onPendingInjectionDecisionChange(nil)
    }
}
