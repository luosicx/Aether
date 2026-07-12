/// 打开 URL 工具（跨平台：iOS + macOS）
///
/// 用系统默认方式打开 URL，默认仅允许打开 http/https 网页链接。
/// 调用方式：execute(arguments: ["url": "..."])，url 为必填参数。
/// iOS 通过 UIApplication.shared.open 打开，macOS 通过 NSWorkspace.shared.open 打开。
///
/// 安全行为：
/// - 默认只允许 `http` 与 `https` scheme，防止通过 `file://`、`javascript:`、
///   自定义协议等唤起恶意应用或读取本地文件。
/// - 白名单可通过初始化参数 `allowedSchemes` 配置，scheme 比较不区分大小写。
/// - 缺少 scheme 的 URL 会被拒绝，不会自动补全，避免钓鱼或语义混淆。
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 打开 URL 工具：用系统默认方式打开 URL，默认仅允许 http/https
final class OpenURLTool: ToolProtocol {
    /// 允许的 URL scheme 白名单，默认仅允许 http/https
    private let allowedSchemes: Set<String>

    /// 创建 OpenURLTool
    /// - Parameter allowedSchemes: 允许的 URL scheme 集合，不区分大小写，默认为 ["http", "https"]
    init(allowedSchemes: Set<String> = ["http", "https"]) {
        self.allowedSchemes = allowedSchemes.map { $0.lowercased() }
    }

    /// 工具定义
    /// - name: `open_url`
    /// - parameters: `url`（必填，String）— 要打开的 URL，仅允许 http/https scheme
    var definition: ToolDefinition {
        ToolDefinition(
            name: "open_url",
            description: "用系统默认方式打开 URL，仅允许 http/https 协议",
            parameters: [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "要打开的 URL，仅允许 http/https 协议"]
                ],
                "required": ["url"]
            ]
        )
    }

    /// 打开指定 URL
    ///
    /// - Parameter arguments: 含 `url` 键的参数字典
    /// - Returns: 成功返回 "已打开 <url>"，失败返回错误信息字符串
    /// - Throws: 不抛异常，错误以字符串形式返回
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let urlString = arguments["url"] as? String, !urlString.isEmpty else {
            return "错误：请提供 URL"
        }
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            return "错误：URL 无效或缺少协议（仅支持 \(allowedSchemes.sorted().joined(separator: ", "))）"
        }
        guard allowedSchemes.contains(scheme) else {
            return "错误：协议 '\(scheme)' 不在白名单内（允许：\(allowedSchemes.sorted().joined(separator: ", "))），拒绝打开"
        }
        #if os(iOS)
        await UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
        return "已打开 \(urlString)"
    }
}
