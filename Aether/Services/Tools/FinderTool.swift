/// Finder 文件管理器操作工具（macOS only）
///
/// 提供 Finder 相关的自动化操作，包括获取当前选中项、在 Finder 中显示文件、打开目录。
/// 调用方式：execute(arguments: ["action": "get_selection"|"reveal"|"open", "path": "..."])，
/// action 为必填参数，path 在 reveal/open 时需要。
/// 获取选中项通过 NSAppleScript 调用 Finder 脚本实现，reveal/open 通过 NSWorkspace 实现。
import Foundation
import AppKit
import AetherFoundation

/// macOS Finder 操作工具
final class FinderTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `finder_action`
    /// - parameters: `action`（必填，String）— 操作类型 get_selection/reveal/open；
    ///   `path`（可选，String）— 文件路径，reveal/open 时需要
    var definition: ToolDefinition {
        ToolDefinition(
            name: "finder_action",
            description: "Finder 操作：获取选中项/在 Finder 中显示/打开目录",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作：get_selection/reveal/open"],
                    "path": ["type": "string", "description": "文件路径（reveal/open 时需要）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// 执行 Finder 操作
    ///
    /// - Parameter arguments: 含 `action` 和可选 `path` 的参数字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "get_selection":
            return getSelection()
        case "reveal":
            return revealInFinder(arguments)
        case "open":
            return openInFinder(arguments)
        default:
            return "错误：不支持的操作，支持 get_selection/reveal/open"
        }
    }

    /// 通过 AppleScript 获取 Finder 当前选中的文件路径列表
    private func getSelection() -> String {
        let script = """
        tell application "Finder"
            set selectionList to selection
            set pathList to {}
            repeat with anItem in selectionList
                set end of pathList to (anItem as alias) as text
            end repeat
            return pathList as text
        end tell
        """
        return runAppleScript(script)
    }

    /// 在 Finder 中高亮显示指定文件
    private func revealInFinder(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：请提供 path 参数"
        }
        // activateFileViewerSelecting 会激活 Finder 并选中指定文件
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return "已在 Finder 中显示：\(path)"
    }

    /// 用系统默认方式打开文件或目录
    private func openInFinder(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：请提供 path 参数"
        }
        NSWorkspace.shared.openFile(path)
        return "已在 Finder 中打开：\(path)"
    }

    /// 执行 AppleScript 脚本并返回输出，错误以字符串形式返回
    /// - Note: 本工具内 source 为常量字面量，无外部输入注入风险
    private func runAppleScript(_ source: String) -> String {
        let script = NSAppleScript(source: source) // NOSONAR: source 为常量字面量，无注入风险
        var errorInfo: NSDictionary?
        let output = script?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            return "错误：\(error[NSAppleScript.errorMessage] as? String ?? "未知错误")"
        }
        return output?.stringValue ?? "已执行（无输出）"
    }
}
