/// Safari 浏览器自动化控制工具（macOS only）
///
/// 通过 NSAppleScript 控制 Safari 浏览器，支持列出标签页、获取当前 URL、导航到指定 URL、
/// 在当前标签页执行 JavaScript、新建标签页、关闭指定标签页等操作。
/// 调用方式：execute(arguments: ["action": "...", ...])，action 为必填参数。
/// 主要 action：list_tabs/get_url/navigate/run_js/new_tab/close_tab。
import Foundation
import AetherFoundation

/// macOS Safari 浏览器自动化工具，通过 AppleScript 控制 Safari
final class SafariControlTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `control_safari`
    /// - parameters: `action`（必填，String）— 操作类型；
    ///   `url`（可选）— 导航/新建标签页的 URL；`script`（可选）— JS 代码；
    ///   `index`（可选，Integer）— 标签页索引（close_tab 时需要）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "control_safari",
            description: "控制 Safari 浏览器：列出标签页/获取 URL/导航/执行 JS/新建标签页/关闭标签页",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作：list_tabs/get_url/navigate/run_js/new_tab/close_tab"],
                    "url": ["type": "string", "description": "URL（navigate/new_tab 时需要）"],
                    "script": ["type": "string", "description": "JavaScript 代码（run_js 时需要）"],
                    "index": ["type": "integer", "description": "标签页索引（close_tab 时需要）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// run_js 允许执行的目标域白名单。空集合表示默认不允许任何域。
    private let allowedDomains: Set<String> = []

    /// 将字符串安全转义为 AppleScript 字符串字面量，防止注入。
    /// 转义反斜杠、双引号以及换行/回车/制表符等控制字符，
    /// 防止攻击者闭合字符串并注入任意 AppleScript 代码或多行脚本。
    /// 标记为 internal static 以便单元测试直接验证转义行为。
    static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// 校验 URL scheme 是否在允许的白名单内（仅 http/https），防止 file:// 等危险 scheme。
    private func validateURLScheme(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    /// 执行 Safari 控制操作
    ///
    /// - Parameter arguments: 含 `action` 及其所需参数的字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "list_tabs": return listTabs()
        case "get_url": return getURL()
        case "navigate": return navigate(arguments)
        case "run_js": return runJS(arguments)
        case "new_tab": return newTab(arguments)
        case "close_tab": return closeTab(arguments)
        default: return "错误：不支持的操作，支持 list_tabs/get_url/navigate/run_js/new_tab/close_tab"
        }
    }

    /// 遍历所有窗口的标签页，拼接名称与 URL
    private func listTabs() -> String {
        let script = """
        tell application "Safari"
            set tabInfo to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabInfo to tabInfo & (name of t) & " | " & (URL of t) & "\\n"
                end repeat
            end repeat
            return tabInfo
        end tell
        """
        return runAppleScript(script)
    }

    /// 获取前台窗口当前标签页的 URL
    private func getURL() -> String {
        let script = """
        tell application "Safari"
            return URL of current tab of front window
        end tell
        """
        return runAppleScript(script)
    }

    /// 将前台窗口当前标签页导航到指定 URL
    private func navigate(_ arguments: [String: Any]) -> String {
        guard let url = arguments["url"] as? String else {
            return "错误：请提供 url 参数"
        }
        guard validateURLScheme(url) else {
            return "错误：仅允许 http/https URL"
        }
        let escapedURL = Self.appleScriptEscaped(url)
        let script = """
        tell application "Safari"
            set URL of current tab of front window to "\(escapedURL)"
        end tell
        """
        return runAppleScript(script)
    }

    /// 在当前标签页执行 JavaScript 代码
    private func runJS(_ arguments: [String: Any]) -> String {
        guard let jsCode = arguments["script"] as? String else {
            return "错误：请提供 script 参数"
        }
        guard let host = currentPageHost(), allowedDomains.contains(host) else {
            return "错误：当前页面所在域不在 run_js 白名单中"
        }
        let escapedJS = Self.appleScriptEscaped(jsCode)
        let script = """
        tell application "Safari"
            do JavaScript "\(escapedJS)" in current tab of front window
        end tell
        """
        return runAppleScript(script)
    }

    /// 获取当前标签页 URL 的主机名
    private func currentPageHost() -> String? {
        let urlString = getURL()
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("错误") else { return nil }
        guard let url = URL(string: trimmed), let host = url.host else { return nil }
        return host
    }

    /// 新建标签页（或文档），url 为空时新建空白文档
    private func newTab(_ arguments: [String: Any]) -> String {
        let url = arguments["url"] as? String ?? ""
        let script: String
        if url.isEmpty {
            script = """
            tell application "Safari"
                make new document
            end tell
            """
        } else {
            guard validateURLScheme(url) else {
                return "错误：仅允许 http/https URL"
            }
            let escapedURL = Self.appleScriptEscaped(url)
            script = """
            tell application "Safari"
                make new document with properties {URL:"\(escapedURL)"}
            end tell
            """
        }
        return runAppleScript(script)
    }

    /// 关闭前台窗口指定索引的标签页（AppleScript 索引从 1 开始，故 +1）
    private func closeTab(_ arguments: [String: Any]) -> String {
        guard let index = arguments["index"] as? Int else {
            return "错误：请提供 index 参数"
        }
        // AppleScript 标签页索引从 1 开始，外部传入从 0 开始，需 +1 转换
        let script = """
        tell application "Safari"
            close tab \(index + 1) of front window
        end tell
        """
        return runAppleScript(script)
    }

    /// 执行 AppleScript 脚本并返回输出，错误以字符串形式返回
    /// - Note: 本工具内 source 为常量字面量（不含外部输入），无注入风险
    private func runAppleScript(_ source: String) -> String {
        let script = NSAppleScript(source: source) // NOSONAR: source 为常量字面量，无注入风险
        var errorInfo: NSDictionary?
        let output = script?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            return "错误：\(error[NSAppleScript.errorMessage] as? String ?? "未知错误")"
        }
        return output?.stringValue ?? "已执行"
    }
}
