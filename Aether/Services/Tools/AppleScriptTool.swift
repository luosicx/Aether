/// AppleScript 安全动作工具（macOS only）
///
/// 历史上该工具接受任意 `script` 字符串并通过 NSAppleScript 执行，等同完整系统接管：
/// 可读写任意文件、执行 shell、控制 Terminal/Mail/Messages、模拟输入、外传数据。
/// 静态黑名单与 `tell application` 白名单均无法可靠阻止变量拼接、`tell application id` 等绕过。
///
/// 现改为**固定模板 + 参数化动作**：不再接受任意脚本，只有下列只读/低风险动作，
/// 且用户提供的参数不会拼接进 AppleScript（打开 URL / 在 Finder 显示走 NSWorkspace）。
/// - `get_finder_selection`：读取 Finder 当前选中项
/// - `get_frontmost_application`：读取前台应用名
/// - `get_safari_current_url`：读取 Safari 当前标签页 URL
/// - `get_system_version`：读取 macOS 版本
/// - `reveal_in_finder`：在 Finder 中显示指定绝对路径（需 `path`）
/// - `open_url`：用默认浏览器打开 http/https URL（需 `url`）
import Foundation
import AppKit
import AetherFoundation

/// macOS AppleScript 安全动作工具
final class AppleScriptTool: ToolProtocol, @unchecked Sendable {
    /// 允许的参数化动作。任何不在集合内的 action 一律拒绝。
    private enum SafeAction: String {
        case getFinderSelection = "get_finder_selection"
        case getFrontmostApplication = "get_frontmost_application"
        case getSafariCurrentURL = "get_safari_current_url"
        case getSystemVersion = "get_system_version"
        case revealInFinder = "reveal_in_finder"
        case openURL = "open_url"
    }

    /// 工具定义
    /// - name: `run_applescript`
    /// - parameters: `action`（必填）；`path`（reveal_in_finder 需要）；`url`（open_url 需要）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_applescript",
            description: "执行预定义的安全 AppleScript 动作（不支持任意脚本）：获取 Finder 选中项/前台应用/Safari 当前 URL/系统版本，或在 Finder 中显示路径、打开 URL",
            parameters: [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "description": "动作：get_finder_selection/get_frontmost_application/get_safari_current_url/get_system_version/reveal_in_finder/open_url"
                    ],
                    "path": ["type": "string", "description": "文件绝对路径（reveal_in_finder 需要）"],
                    "url": ["type": "string", "description": "http/https URL（open_url 需要）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// 执行参数化安全动作
    ///
    /// - Parameter arguments: 含 `action` 及动作所需参数的字典
    /// - Returns: 动作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        // 旧接口的任意脚本一律拒绝，避免调用方误以为仍可执行任意 AppleScript
        if arguments["script"] != nil {
            return "错误：不再支持任意 AppleScript 脚本，请使用 action 参数选择预定义动作"
        }
        guard let rawAction = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        guard let action = SafeAction(rawValue: rawAction) else {
            return "错误：不支持的动作，支持 get_finder_selection/get_frontmost_application/get_safari_current_url/get_system_version/reveal_in_finder/open_url"
        }

        switch action {
        case .getFinderSelection:
            return runAppleScript("""
            tell application "Finder"
                set selectionList to selection
                set pathList to {}
                repeat with anItem in selectionList
                    set end of pathList to POSIX path of (anItem as alias)
                end repeat
                return pathList as text
            end tell
            """)
        case .getFrontmostApplication:
            return runAppleScript("""
            tell application "System Events"
                return name of first application process whose frontmost is true
            end tell
            """)
        case .getSafariCurrentURL:
            return runAppleScript("""
            tell application "Safari"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """)
        case .getSystemVersion:
            return runAppleScript("return system version of (system info)")
        case .revealInFinder:
            return revealInFinder(arguments)
        case .openURL:
            return openURL(arguments)
        }
    }

    // MARK: - 动作实现

    /// 在 Finder 中高亮显示指定绝对路径
    private func revealInFinder(_ arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String, isValidAbsolutePath(path) else {
            return "错误：请提供合法的绝对路径（path 参数）"
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return "错误：路径不存在：\(path)"
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return "已在 Finder 中显示：\(path)"
    }

    /// 用默认浏览器打开 http/https URL
    private func openURL(_ arguments: [String: Any]) -> String {
        guard let rawURL = arguments["url"] as? String, let url = validatedHTTPURL(rawURL) else {
            return "错误：仅支持合法的 http/https URL"
        }
        guard NSWorkspace.shared.open(url) else {
            return "错误：无法打开 URL"
        }
        return "已打开：\(url.absoluteString)"
    }

    // MARK: - 校验与执行辅助

    /// 校验绝对路径：拒绝空串、NUL、换行与相对路径
    private func isValidAbsolutePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.contains("\0"),
              !path.contains("\n"),
              !path.contains("\r") else {
            return false
        }
        return (path as NSString).isAbsolutePath
    }

    /// 校验 http/https URL：拒绝空白、引号、尖括号、反引号与控制字符，要求 host 非空
    private func validatedHTTPURL(_ raw: String) -> URL? {
        let forbidden = CharacterSet(charactersIn: "\"<>\\`\n\r\t ").union(.controlCharacters)
        guard !raw.isEmpty, raw.unicodeScalars.allSatisfy({ !forbidden.contains($0) }),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// 执行固定模板 AppleScript 并返回结果或错误信息
    private func runAppleScript(_ source: String) -> String {
        guard let appleScript = NSAppleScript(source: source) else {
            return "AppleScript 执行失败：无法编译脚本"
        }
        var errorInfo: NSDictionary?
        let output = appleScript.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            return "AppleScript 执行失败：\(errorMessage)"
        }
        let result = output.stringValue ?? ""
        return result.isEmpty ? "已执行（无输出）" : result
    }
}
