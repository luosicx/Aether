/// AppleScript 执行工具（macOS only）
///
/// 通过 NSAppleScript 在 macOS 上执行任意 AppleScript 脚本，返回脚本输出或错误信息。
/// 常用于自动化控制 Finder、Safari、System Events 等系统应用。
/// 调用方式：execute(arguments: ["script": "..."])，script 为必填参数。
#if os(macOS)
import Foundation

/// macOS AppleScript 执行工具
final class AppleScriptTool: ToolProtocol {
    var riskLevel: ToolRiskLevel { .dangerous }

    /// 功能开关：是否启用 AppleScript 工具。默认关闭，需用户在设置中手动开启。
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "com.aether.applescript.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "com.aether.applescript.enabled") }
    }

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
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard AppleScriptTool.isEnabled else {
            return "错误：AppleScript 工具未启用，请在设置中开启"
        }
        guard let script = arguments["script"] as? String, !script.isEmpty else {
            return "错误：请提供 AppleScript 脚本"
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
#endif
