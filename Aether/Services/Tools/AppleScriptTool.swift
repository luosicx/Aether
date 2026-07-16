/// AppleScript 执行工具（macOS only）
///
/// 通过 NSAppleScript 在 macOS 上执行任意 AppleScript 脚本，返回脚本输出或错误信息。
/// 常用于自动化控制 Finder、Safari、System Events 等系统应用。
/// 调用方式：execute(arguments: ["script": "..."])，script 为必填参数。
import Foundation
import AetherFoundation

/// macOS AppleScript 执行工具
final class AppleScriptTool: ToolProtocol, @unchecked Sendable {
    /// 静态危险 AppleScript 模式：命中即拒绝执行。
    /// 这些模式可执行任意 shell 命令、模拟输入、访问 Keychain 等，风险过高。
    private static let dangerousPatterns: [String] = [
        "do shell script",        // 执行任意 shell 命令
        "keystroke",              // 模拟键盘输入
        "key code",               // 模拟按键
        "security find-generic",  // 访问 Keychain 通用密码
        "security find-internet", // 访问 Keychain 网络密码
        "security add-generic",   // 写入 Keychain
        "do shell script \"curl", // 网络外传
        "do shell script \"wget",
        "do shell script \"nc",
        "do shell script \"python",
        "do shell script \"ruby",
        "do shell script \"perl",
        "do shell script \"osascript" // 嵌套执行绕过
    ]

    /// 工具定义
    /// - name: `run_applescript`
    /// - parameters: `script`（必填，String）— 要执行的 AppleScript 脚本
    var definition: ToolDefinition {
        ToolDefinition(
            name: "run_applescript",
            description: "在 macOS 上执行 AppleScript 脚本并返回结果",
            parameters: [
                "type": "object",
                "properties": [
                    "script": ["type": "string", "description": "要执行的 AppleScript 脚本"]
                ],
                "required": ["script"]
            ]
        )
    }

    /// 执行 AppleScript 脚本
    ///
    /// - Parameter arguments: 含 `script` 键的参数字典
    /// - Returns: 脚本执行输出，或错误信息字符串
    /// - Throws: 工具未启用或用户未确认时抛出错误
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let script = arguments["script"] as? String, !script.isEmpty else {
            return "错误：请提供 AppleScript 脚本"
        }
        // 静态危险 API 检测：拦截 do shell script、keystroke 等高危模式
        let lowercased = script.lowercased()
        for pattern in Self.dangerousPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return "错误：脚本包含危险操作（\(pattern)），已拒绝执行"
            }
        }
        // 通过 NSAppleScript 编译并执行脚本，错误信息写入 errorInfo
        let appleScript = NSAppleScript(source: script)
        var errorInfo: NSDictionary?
        let output = appleScript?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            return "AppleScript 执行失败：\(errorMessage)"
        }
        let result = output?.stringValue ?? ""
        return result.isEmpty ? "已执行（无输出）" : result
    }
}
