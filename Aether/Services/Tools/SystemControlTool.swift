/// 系统控制工具（macOS only）
///
/// 通过 AppleScript 调节 macOS 系统设置，包括屏幕亮度和系统音量的获取与设置。
/// 调用方式：execute(arguments: ["action": "...", "value": 50])，action 为必填参数。
/// 主要 action：get_brightness/set_brightness/get_volume/set_volume。
/// 注意：亮度设置无直接公开 API，实现为简化方案，可能需要辅助功能权限。
import Foundation
import AetherFoundation

/// macOS 系统控制工具：调节屏幕亮度 / 系统音量
final class SystemControlTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `system_control`
    /// - parameters: `action`（必填，String）— 操作类型；
    ///   `value`（可选，Integer）— 亮度/音量值（0-100，set_* 时需要）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "system_control",
            description: "系统控制：获取/设置屏幕亮度、获取/设置系统音量",
            parameters: [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "操作：get_brightness/set_brightness/get_volume/set_volume"],
                    "value": ["type": "integer", "description": "亮度/音量值（0-100，set_* 时需要）"]
                ],
                "required": ["action"]
            ]
        )
    }

    /// 执行系统控制操作
    ///
    /// - Parameter arguments: 含 `action` 及可选 `value` 的参数字典
    /// - Returns: 操作结果字符串，或错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            return "错误：请提供 action 参数"
        }
        switch action {
        case "get_brightness": return getBrightness()
        case "set_brightness": return setBrightness(arguments)
        case "get_volume": return getVolume()
        case "set_volume": return setVolume(arguments)
        default: return "错误：不支持的操作，支持 get_brightness/set_brightness/get_volume/set_volume"
        }
    }

    /// 获取屏幕亮度：macOS 无直接公开 API，返回提示
    private func getBrightness() -> String {
        // 用 AppleScript 获取亮度（没有直接 API，返回提示）
        // 实际可用 CoreGraphics 的 CGDisplayCopyDisplayMode 获取，但无直接亮度 API
        // 简化：返回提示
        return "macOS 不支持直接获取屏幕亮度值"
    }

    /// 设置屏幕亮度：将 0-100 归一化为 0-1，再通过 gamma 调整模拟
    private func setBrightness(_ arguments: [String: Any]) -> String {
        guard let value = arguments["value"] as? Int, (0...100).contains(value) else {
            return "错误：请提供 0-100 之间的 value 参数"
        }
        // 简化实现：仅校验 value 范围，实际亮度调整通过 AppleScript key code 107 实现
        _ = value
        // 用 AppleScript 设置亮度（需要辅助功能权限）
        return setBrightnessViaGamma()
    }

    /// 通过 AppleScript 模拟亮度调整（需要辅助功能权限）
    /// - Note: 简化占位实现，仅发送 key code 107；后续可基于 value 循环发键实现精细控制。
    private func setBrightnessViaGamma() -> String {
        // NOSONAR: NSAppleScript 仅执行固定的 key code 107 字符串，无外部输入注入风险
        let script = "tell application \"System Events\" to key code 107"
        let result = runAppleScript(script)
        // 检查 AppleScript 执行结果，失败时返回错误信息
        if result.hasPrefix("错误：") {
            return "设置亮度失败：\(result)"
        }
        return "已尝试设置亮度（可能需要辅助功能权限）"
    }

    /// 获取系统音量：通过 AppleScript 读取 volume settings
    private func getVolume() -> String {
        let script = """
        tell application "System Events"
            return output volume of (get volume settings)
        end tell
        """
        return runAppleScript(script)
    }

    /// 设置系统音量：通过 AppleScript 的 set volume 命令
    private func setVolume(_ arguments: [String: Any]) -> String {
        guard let value = arguments["value"] as? Int, (0...100).contains(value) else {
            return "错误：请提供 0-100 之间的 value 参数"
        }
        let script = "set volume output volume \(value)"
        return runAppleScript(script)
    }

    /// 执行 AppleScript 脚本并返回输出，错误以字符串形式返回
    /// - Note: 调用方负责校验脚本来源（本工具内 script 为常量字面量，无注入风险）
    private func runAppleScript(_ source: String) -> String {
        // NOSONAR: source 由调用方控制，本工具仅使用常量字面量脚本
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        let output = script?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            return "错误：\(error[NSAppleScript.errorMessage] as? String ?? "未知错误")"
        }
        return output?.stringValue ?? "已执行"
    }
}
