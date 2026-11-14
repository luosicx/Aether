import Foundation
import os
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 工具运行时授权结果
enum ToolAuthorizationResult: Sendable, Equatable {
    /// 已授权；`sessionOnly` 为 true 表示仅本次启动有效
    case authorized(sessionOnly: Bool)
    /// 用户拒绝
    case denied
}

/// 用户对确认弹窗的选择结果。授权状态的写入由 ToolAuthorization 负责，
/// 呈现器只收集选择，便于测试注入即时应答而不必自己复制授权逻辑。
enum ToolAuthorizationChoice: Equatable {
    /// 取消 / 关闭弹窗
    case denied
    /// 「允许一次」，或非敏感工具的「确认」
    case once
    /// 「始终允许」（仅敏感工具提供该按钮）
    case always
}

/// 授权确认弹窗的呈现器。只在主线程调用，故不要求 Sendable。
/// 产品侧用 `SystemAlertPresenter` 弹真实 UI；测试侧可注入即时应答的实现，
/// 避免「无人点击 → continuation 永不 resume」把调用方整条挂死。
protocol AuthorizationAlertPresenting {
    func present(toolName: String, title: String, message: String, isSensitive: Bool,
                 completion: @escaping (ToolAuthorizationChoice) -> Void)
}

/// 敏感/高危工具的运行时授权组件。
/// 在调用可能泄露隐私或影响系统的工具前，强制弹出用户确认。
///
/// P1-4: 原实现使用 `private(set) var sessionAuthorizations / alwaysAuthorized` 暴露可变状态，
/// 类标记 `@unchecked Sendable` 但跨 actor 读写无同步保护，存在数据竞争。
/// 现改用 `OSAllocatedUnfairLock` 包裹两个 Set<String>，既保留单例 + @unchecked Sendable 模式，
/// 又满足 Swift 6 严格并发要求。
final class ToolAuthorization: @unchecked Sendable {
    static let shared = ToolAuthorization()

    /// 本次启动内已授权（允许一次）的工具名集合。用锁保护跨 actor 读写。
    private let sessionAuthorizationsLock = OSAllocatedUnfairLock(initialState: Set<String>())
    /// 用户选择「始终允许」的工具名集合。同上，用锁保护。
    private let alwaysAuthorizedLock = OSAllocatedUnfairLock(initialState: Set<String>())

    /// 暴露给外部的只读快照（用于 DebugInfo / 设置页展示）
    var sessionAuthorizations: Set<String> {
        sessionAuthorizationsLock.withLock { $0 }
    }
    var alwaysAuthorized: Set<String> {
        alwaysAuthorizedLock.withLock { $0 }
    }

    /// 禁止「始终允许」的工具集合：这些工具风险过高，每次调用都必须用户确认。
    /// 包括任意 AppleScript 执行、终端命令执行和快捷指令执行。
    private let neverAlwaysAllow: Set<String> = [
        "run_applescript",
        "run_terminal_command",
        "run_shortcut"
    ]

    private let alwaysAuthorizedKeyPrefix = "aether.tool.auth.always."

    /// 弹窗呈现器（测试可注入即时应答的实现）
    internal var presenter: AuthorizationAlertPresenting = SystemAlertPresenter()

    private init() {
        restoreAlwaysAuthorized()
    }

    /// 查询某工具的当前授权状态
    func authorizationStatus(for toolName: String) -> ToolAuthorizationResult {
        // 优先查询 alwaysAuthorized（持久化授权），再查询 sessionAuthorizations
        if alwaysAuthorizedLock.withLock({ $0.contains(toolName) }) {
            return .authorized(sessionOnly: false)
        }
        if sessionAuthorizationsLock.withLock({ $0.contains(toolName) }) {
            return .authorized(sessionOnly: true)
        }
        return .denied
    }

    // MARK: - Completion API

    /// 弹出高危操作确认弹窗（如执行 terminal、applescript）。
    /// - Parameters:
    ///   - toolName: 工具名
    ///   - details: 展示给用户的详情说明
    ///   - completion: 用户选择后的回调
    func presentConfirmation(toolName: String, details: String?, completion: @escaping (ToolAuthorizationResult) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(.denied)
                return
            }
            let status = self.authorizationStatus(for: toolName)
            if case .authorized = status {
                completion(status)
                return
            }
            let message = details ?? "该操作可能影响系统状态，请确认是否继续。"
            self.presenter.present(
                toolName: toolName,
                title: "确认执行「\(toolName)」",
                message: message,
                isSensitive: false
            ) { [weak self] choice in
                guard let self else {
                    completion(.denied)
                    return
                }
                self.apply(choice: choice, toolName: toolName, completion: completion)
            }
        }
    }

    /// 弹出敏感数据访问确认弹窗（如读取剪贴板、通讯录、定位、截图、OCR）。
    /// - Parameters:
    ///   - toolName: 工具名
    ///   - purpose: 访问目的说明
    ///   - completion: 用户选择后的回调
    func presentSensitiveAccessConfirmation(toolName: String, purpose: String?, completion: @escaping (ToolAuthorizationResult) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(.denied)
                return
            }
            let status = self.authorizationStatus(for: toolName)
            if case .authorized = status {
                completion(status)
                return
            }
            let message = purpose ?? "该工具将访问您的敏感数据。"
            self.presenter.present(
                toolName: toolName,
                title: "允许访问「\(toolName)」？",
                message: message,
                isSensitive: true
            ) { [weak self] choice in
                guard let self else {
                    completion(.denied)
                    return
                }
                self.apply(choice: choice, toolName: toolName, completion: completion)
            }
        }
    }

    /// 把用户的选择不落成授权状态再回传结果。`neverAlwaysAllow` 的拦截在 `grantAlways` 里。
    private func apply(choice: ToolAuthorizationChoice, toolName: String,
                       completion: (ToolAuthorizationResult) -> Void) {
        switch choice {
        case .denied:
            completion(.denied)
        case .once:
            grantSessionAuthorization(toolName: toolName)
            completion(.authorized(sessionOnly: true))
        case .always:
            grantAlways(toolName)
            completion(.authorized(sessionOnly: false))
        }
    }

    // MARK: - Async API

    /// `presentConfirmation` 的 async 包装，便于在 async 调用链中使用
    func presentConfirmation(toolName: String, details: String?) async -> ToolAuthorizationResult {
        await withCheckedContinuation { cont in
            presentConfirmation(toolName: toolName, details: details) { result in
                cont.resume(returning: result)
            }
        }
    }

    /// `presentSensitiveAccessConfirmation` 的 async 包装
    func presentSensitiveAccessConfirmation(toolName: String, purpose: String?) async -> ToolAuthorizationResult {
        await withCheckedContinuation { cont in
            presentSensitiveAccessConfirmation(toolName: toolName, purpose: purpose) { result in
                cont.resume(returning: result)
            }
        }
    }

    // MARK: - 程序化授权 API（测试与设置页使用）

    /// 授予指定工具本次启动内有效授权
    func grantSessionAuthorization(toolName: String) {
        sessionAuthorizationsLock.withLock { $0.insert(toolName) }
    }

    /// 授予指定工具持久化授权，并写入 UserDefaults
    func grantAlwaysAuthorization(toolName: String) {
        grantAlways(toolName)
    }

    /// 撤销指定工具的所有授权（本次启动 + 持久化），并清理 UserDefaults
    func revokeAuthorization(toolName: String) {
        sessionAuthorizationsLock.withLock { $0.remove(toolName) }
        alwaysAuthorizedLock.withLock { $0.remove(toolName) }
        UserDefaults.standard.removeObject(forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
    }
}

private extension ToolAuthorization {
    func restoreAlwaysAuthorized() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(alwaysAuthorizedKeyPrefix) {
            if UserDefaults.standard.bool(forKey: key) {
                let toolName = String(key.dropFirst(alwaysAuthorizedKeyPrefix.count))
                // 高危工具不允许持久化授权，清除残留的旧数据
                guard !neverAlwaysAllow.contains(toolName) else {
                    UserDefaults.standard.removeObject(forKey: key)
                    continue
                }
                alwaysAuthorizedLock.withLock { $0.insert(toolName) }
            }
        }
    }

    func grantAlways(_ toolName: String) {
        // 高危工具禁止持久化授权，每次调用都必须用户确认
        guard !neverAlwaysAllow.contains(toolName) else { return }
        alwaysAuthorizedLock.withLock { $0.insert(toolName) }
        UserDefaults.standard.set(true, forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
    }

}

/// 真实系统的授权确认弹窗：iOS 用 UIAlertController，macOS 用 NSAlert。
/// 只负责收集用户的选择，授权状态由 `ToolAuthorization.apply(choice:toolName:completion:)` 写入。
final class SystemAlertPresenter: AuthorizationAlertPresenting {
    #if os(iOS)
    /// 最近激活的 scene。iPhone Duo 分屏/多窗口下可能同时存在多个 foregroundActive scene，
    /// 弹窗优先落在用户最近交互的 scene，避免授权弹窗出现在错误窗口。仅主线程读写。
    private weak var lastActiveScene: UIWindowScene?

    init() {
        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.lastActiveScene = notification.object as? UIWindowScene
        }
    }
    #endif

    func present(toolName: String, title: String, message: String, isSensitive: Bool,
                 completion: @escaping (ToolAuthorizationChoice) -> Void) {
        #if os(iOS)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completion(.denied)
        })
        if isSensitive {
            alert.addAction(UIAlertAction(title: "允许一次", style: .default) { _ in
                completion(.once)
            })
            alert.addAction(UIAlertAction(title: "始终允许", style: .default) { _ in
                completion(.always)
            })
        } else {
            alert.addAction(UIAlertAction(title: "确认", style: .default) { _ in
                completion(.once)
            })
        }
        guard let root = topViewController() else {
            completion(.denied)
            return
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(alert, animated: true)
        #else
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        if isSensitive {
            alert.addButton(withTitle: "允许一次")
            alert.addButton(withTitle: "始终允许")
        } else {
            alert.addButton(withTitle: "确认")
        }
        alert.buttons.first?.keyEquivalent = "\u{1b}"
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.denied)
            case .alertSecondButtonReturn:
                completion(.once)
            case .alertThirdButtonReturn where isSensitive:
                completion(.always)
            default:
                completion(.denied)
            }
        }
        if let window = NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
        #endif
    }

    #if os(iOS)
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0 === lastActiveScene && $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundActive })
        let window = scene?.windows.first(where: { $0.isKeyWindow })
        return window?.rootViewController
    }
    #endif
}
