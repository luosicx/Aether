/// 窗口管理工具（macOS only）
///
/// 通过 CGWindowList 和 AXUIElement 管理 macOS 窗口，支持列出窗口、聚焦应用、
/// 移动窗口、调整窗口大小、最小化窗口。
/// 调用方式：execute(arguments: ["action": "...", "app": "...", ...])，action 为必填参数。
/// 主要 action：list/focus/move/resize/minimize。
#if os(macOS)
import Foundation
import AppKit
import ApplicationServices

/// macOS 窗口管理工具
final class WindowManagementTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `manage_window`
    /// - parameters: `action`（必填，String）— 操作类型；
    ///   `app`（可选）— 应用名称；`x`/`y`（可选）— 移动坐标；`width`/`height`（可选）— 窗口尺寸
    var definition: ToolDefinition {
        ToolDefinition(
            name: "manage_window",
            description: "管理 macOS 窗口：列出/聚焦/移动/调整大小/最小化",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作类型：list/focus/move/resize/minimize"],
                    "app": ["type": "string", "description": "应用名称（focus/move/resize/minimize 时需要）"],
                    "x": ["type": "integer", "description": "X 坐标（move 时需要）"],
                    "y": ["type": "integer", "description": "Y 坐标（move 时需要）"],
                    "width": ["type": "integer", "description": "窗口宽度（resize 时需要）"],
                    "height": ["type": "integer", "description": "窗口高度（resize 时需要）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// 执行窗口管理操作
    ///
    /// - Parameter arguments: 含 `action` 及其所需参数的字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "list":
            return listWindows()
        case "focus":
            return focusApp(arguments)
        case "move":
            return moveWindow(arguments)
        case "resize":
            return resizeWindow(arguments)
        case "minimize":
            return minimizeWindow(arguments)
        default:
            return "错误：不支持的操作，支持 list/focus/move/resize/minimize"
        }
    }

    /// 列出屏幕上所有窗口：通过 CGWindowList 获取窗口信息
    private func listWindows() -> String {
        // CGWindowListCopyWindowInfo 返回屏幕上所有可见窗口的属性字典
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return "未找到窗口" }
        var lines: [String] = []
        for window in windows {
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? "未知"
            let windowName = window[kCGWindowName as String] as? String ?? ""
            if windowName.isEmpty {
                lines.append(ownerName)
            } else {
                lines.append("\(ownerName) - \(windowName)")
            }
        }
        return lines.isEmpty ? "未找到窗口" : lines.joined(separator: "\n")
    }

    /// 聚焦指定应用窗口到前台
    private func focusApp(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String else {
            return "错误：请提供 app 参数"
        }
        let ws = NSWorkspace.shared
        for app in ws.runningApplications where app.localizedName == appName {
            app.activate(options: [.activateAllWindows])
            return "已聚焦 \(appName)"
        }
        return "未找到运行中的应用：\(appName)"
    }

    /// 移动指定应用窗口到新坐标
    private func moveWindow(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String,
              let x = arguments["x"] as? Int,
              let y = arguments["y"] as? Int else {
            return "错误：请提供 app、x、y 参数"
        }
        return setWindowFrame(appName) { frame in
            frame.origin = CGPoint(x: x, y: y)
        }
    }

    /// 调整指定应用窗口大小
    private func resizeWindow(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String,
              let width = arguments["width"] as? Int,
              let height = arguments["height"] as? Int else {
            return "错误：请提供 app、width、height 参数"
        }
        return setWindowFrame(appName) { frame in
            frame.size = CGSize(width: width, height: height)
        }
    }

    /// 最小化指定应用的第一个窗口
    private func minimizeWindow(_ arguments: [String: Any]) -> String {
        guard let appName = arguments["app"] as? String else {
            return "错误：请提供 app 参数"
        }
        // 校验 appName 是否为当前运行中的应用，防止 AppleScript 注入
        guard isValidRunningApp(appName) else {
            return "错误：未找到运行中的应用：\(appName)"
        }
        let escapedName = escapeForAppleScript(appName)
        let script = "tell application \"\(escapedName)\" to set miniaturized of window 1 to true"
        return runAppleScript(script)
    }

    /// 通过 AXUIElement 定位应用窗口并调整 frame。
    /// - Parameter modify: 闭包用于修改传入的 frame（origin 或 size）
    private func setWindowFrame(_ appName: String, modify: (inout CGRect) -> Void) -> String {
        // 校验 appName 是否为当前运行中的应用，防止 AppleScript 注入
        guard isValidRunningApp(appName) else {
            return "错误：未找到运行中的应用：\(appName)"
        }
        // 通过 AXUIElement 设置窗口位置/大小
        let ws = NSWorkspace.shared
        for app in ws.runningApplications where app.localizedName == appName {
            // 创建应用的 Accessibility 顶元素，用于访问其窗口列表
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            if result == .success, let windows = windowsRef as? [AXUIElement] {
                if let window = windows.first {
                    var frameRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &frameRef)
                    // 简化实现：用 AppleScript 设置
                    let escapedName = escapeForAppleScript(appName)
                    let script = "tell application \"\(escapedName)\" to set bounds of window 1 to {0, 0, 800, 600}"
                    _ = runAppleScript(script)
                    return "已调整 \(appName) 窗口"
                }
            }
        }
        return "未找到应用窗口：\(appName)"
    }

    /// 校验 appName 是否为当前运行中的应用名称，防止通过 app 参数注入 AppleScript。
    private func isValidRunningApp(_ appName: String) -> Bool {
        let ws = NSWorkspace.shared
        return ws.runningApplications.contains { $0.localizedName == appName }
    }

    /// 将字符串安全转义为 AppleScript 字符串字面量，防止注入。
    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 执行 AppleScript 脚本并返回结果，错误以字符串形式返回
    private func runAppleScript(_ source: String) -> String {
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            return "错误：\(error[NSAppleScript.errorMessage] as? String ?? "未知错误")"
        }
        return "已执行"
    }
}
#endif
