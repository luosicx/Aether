/// 应用管理工具（macOS only）
///
/// 通过 NSWorkspace 管理 macOS 应用，支持启动、退出、激活应用，以及获取前台应用和列出运行中的应用。
/// 调用方式：execute(arguments: ["action": "...", "app": "..."])，action 为必填参数。
/// 主要 action：launch/quit/activate/frontmost/list_running，app 参数在 launch/quit/activate 时需要。
#if os(macOS)
import Foundation
import AppKit

/// macOS 应用管理工具
final class AppManagementTool: ToolProtocol {
    /// 工具定义
    /// - name: `manage_app`
    /// - parameters: `action`（必填，String）— 操作类型；
    ///   `app`（可选，String）— 应用名称或 Bundle ID，launch/quit/activate 时需要
    var definition: ToolDefinition {
        ToolDefinition(
            name: "manage_app",
            description: "管理 macOS 应用：启动/退出/激活/获取前台应用/列出运行中的应用",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作类型：launch/quit/activate/frontmost/list_running"],
                    "app": ["type": "string", "description": "应用名称（launch/quit/activate 时需要）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// 执行应用管理操作
    ///
    /// - Parameter arguments: 含 `action` 及可选 `app` 的参数字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "launch":
            return launchApp(arguments)
        case "quit":
            return quitApp(arguments)
        case "activate":
            return activateApp(arguments)
        case "frontmost":
            return frontmostApp()
        case "list_running":
            return listRunningApps()
        default:
            return "错误：不支持的操作，支持 launch/quit/activate/frontmost/list_running"
        }
    }

    /// 启动应用：先按 Bundle ID 查找，找不到再按应用名在 /Applications 下查找
    private func launchApp(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String else {
            return "错误：请提供 app 参数"
        }
        let ws = NSWorkspace.shared
        // 优先按 Bundle ID 查找应用 URL
        if let appURL = ws.urlForApplication(withBundleIdentifier: appName) {
            ws.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return "已启动 \(appName)"
        }
        // 尝试用应用名查找
        let path = "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: path) {
            ws.open(URL(fileURLWithPath: path))
            return "已启动 \(appName)"
        }
        return "未找到应用：\(appName)"
    }

    /// 退出运行中的应用：遍历 runningApplications 匹配名称后调用 terminate
    private func quitApp(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String else {
            return "错误：请提供 app 参数"
        }
        let ws = NSWorkspace.shared
        for app in ws.runningApplications {
            if app.localizedName == appName {
                app.terminate()
                return "已退出 \(appName)"
            }
        }
        return "未找到运行中的应用：\(appName)"
    }

    /// 激活运行中的应用窗口到前台
    private func activateApp(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String else {
            return "错误：请提供 app 参数"
        }
        let ws = NSWorkspace.shared
        for app in ws.runningApplications {
            if app.localizedName == appName {
                app.activate(options: [.activateAllWindows])
                return "已激活 \(appName)"
            }
        }
        return "未找到运行中的应用：\(appName)"
    }

    /// 获取当前前台应用名称
    private func frontmostApp() -> String {
        let ws = NSWorkspace.shared
        if let app = ws.frontmostApplication {
            return app.localizedName ?? "未知"
        }
        return "无法获取前台应用"
    }

    /// 列出所有正在运行的应用名称
    private func listRunningApps() -> String {
        let ws = NSWorkspace.shared
        let names = ws.runningApplications.compactMap { $0.localizedName }
        return names.isEmpty ? "没有运行中的应用" : names.joined(separator: "\n")
    }
}
#endif
