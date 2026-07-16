import Foundation
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

/// 敏感/高危工具的运行时授权组件。
/// 在调用可能泄露隐私或影响系统的工具前，强制弹出用户确认。
final class ToolAuthorization: @unchecked Sendable {
    static let shared = ToolAuthorization()

    /// 本次启动内已授权（允许一次）的工具名集合
    private(set) var sessionAuthorizations: Set<String> = []
    /// 用户选择「始终允许」的工具名集合
    private(set) var alwaysAuthorized: Set<String> = []

    /// 禁止「始终允许」的工具集合：这些工具风险过高，每次调用都必须用户确认。
    /// 包括任意 AppleScript 执行、终端命令执行和快捷指令执行。
    private let neverAlwaysAllow: Set<String> = [
        "run_applescript",
        "run_terminal_command",
        "run_shortcut"
    ]

    private let alwaysAuthorizedKeyPrefix = "aether.tool.auth.always."

    private init() {
        restoreAlwaysAuthorized()
    }

    /// 查询某工具的当前授权状态
    func authorizationStatus(for toolName: String) -> ToolAuthorizationResult {
        if alwaysAuthorized.contains(toolName) {
            return .authorized(sessionOnly: false)
        }
        if sessionAuthorizations.contains(toolName) {
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
            self.showAlert(
                toolName: toolName,
                title: "确认执行「\(toolName)」",
                message: message,
                isSensitive: false,
                completion: completion
            )
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
            self.showAlert(
                toolName: toolName,
                title: "允许访问「\(toolName)」？",
                message: message,
                isSensitive: true,
                completion: completion
            )
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
        sessionAuthorizations.insert(toolName)
    }

    /// 授予指定工具持久化授权，并写入 UserDefaults
    func grantAlwaysAuthorization(toolName: String) {
        grantAlways(toolName)
    }

    /// 撤销指定工具的所有授权（本次启动 + 持久化），并清理 UserDefaults
    func revokeAuthorization(toolName: String) {
        sessionAuthorizations.remove(toolName)
        alwaysAuthorized.remove(toolName)
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
                alwaysAuthorized.insert(toolName)
            }
        }
    }

    func grantAlways(_ toolName: String) {
        // 高危工具禁止持久化授权，每次调用都必须用户确认
        guard !neverAlwaysAllow.contains(toolName) else { return }
        alwaysAuthorized.insert(toolName)
        UserDefaults.standard.set(true, forKey: "\(alwaysAuthorizedKeyPrefix)\(toolName)")
    }

    func showAlert(toolName: String, title: String, message: String, isSensitive: Bool, completion: @escaping (ToolAuthorizationResult) -> Void) {
        #if os(iOS)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completion(.denied)
        })
        if isSensitive {
            alert.addAction(UIAlertAction(title: "允许一次", style: .default) { [weak self] _ in
                self?.sessionAuthorizations.insert(toolName)
                completion(.authorized(sessionOnly: true))
            })
            alert.addAction(UIAlertAction(title: "始终允许", style: .default) { [weak self] _ in
                self?.grantAlways(toolName)
                completion(.authorized(sessionOnly: false))
            })
        } else {
            alert.addAction(UIAlertAction(title: "确认", style: .default) { [weak self] _ in
                self?.sessionAuthorizations.insert(toolName)
                completion(.authorized(sessionOnly: true))
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
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.handleAlertResponse(response, toolName: toolName, isSensitive: isSensitive, completion: completion)
        }
        if let window = NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
        #endif
    }

    #if !os(iOS)
    func handleAlertResponse(_ response: NSApplication.ModalResponse, toolName: String, isSensitive: Bool, completion: @escaping (ToolAuthorizationResult) -> Void) {
        switch response {
        case .alertFirstButtonReturn:
            completion(.denied)
        case .alertSecondButtonReturn:
            sessionAuthorizations.insert(toolName)
            completion(.authorized(sessionOnly: true))
        case .alertThirdButtonReturn where isSensitive:
            grantAlways(toolName)
            completion(.authorized(sessionOnly: false))
        default:
            completion(.denied)
        }
    }
    #endif

    #if os(iOS)
    func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow })
        return window?.rootViewController
    }
    #endif
}
