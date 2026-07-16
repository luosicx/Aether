/// 打开 URL 工具（跨平台：iOS + macOS）
///
/// 用系统默认方式打开 URL，可用于打开网页（浏览器）、深链接（App 跳转）、系统设置等。
/// 调用方式：execute(arguments: ["url": "..."])，url 为必填参数。
/// iOS 通过 UIApplication.shared.open 打开，macOS 通过 NSWorkspace.shared.open 打开。
import Foundation
import AetherFoundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 打开 URL 工具：用系统默认方式打开 URL（浏览器、深链接、系统设置）
final class OpenURLTool: ToolProtocol, @unchecked Sendable {
    /// 允许的 URL scheme 白名单。
    /// 防止 file://（打开本地文件可能触发代码执行）、javascript:（执行 JS）、
    /// shortcuts://（绕过 run_shortcut 工具层授权）、prefs:（系统设置深层面板）等危险 scheme。
    private static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms"]

    /// 工具定义
    /// - name: `open_url`
    /// - parameters: `url`（必填，String）— 要打开的 URL，需包含 scheme
    var definition: ToolDefinition {
        ToolDefinition(
            name: "open_url",
            description: "用系统默认方式打开 URL（浏览器、深链接、系统设置）",
            parameters: [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "要打开的 URL"]
                ],
                "required": ["url"]
            ]
        )
    }

    /// 打开指定 URL
    ///
    /// - Parameter arguments: 含 `url` 键的参数字典
    /// - Returns: 成功返回 "已打开"，失败返回错误信息字符串
    /// - Throws: 不抛异常，错误以字符串形式返回
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let urlString = arguments["url"] as? String, !urlString.isEmpty else {
            return "错误：请提供 URL"
        }
        // 校验 URL 合法性，scheme 必须在白名单内
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme) else {
            return "错误：URL 无效或 scheme 不被允许，仅支持 http/https/mailto/tel/sms"
        }
        #if os(iOS)
        await UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
        return "已打开 \(urlString)"
    }
}
