/// 剪贴板读写工具（跨平台：iOS + macOS）
///
/// 提供系统剪贴板的读取与写入能力。包含两个工具：
/// - ReadClipboardTool：读取剪贴板文本内容
/// - WriteClipboardTool：将文本写入剪贴板
/// iOS 通过 UIPasteboard 实现，macOS 通过 NSPasteboard 实现。
/// 调用方式：read_clipboard 无参数；write_clipboard 需传 text 参数。
import Foundation
import AetherFoundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 读取系统剪贴板文本内容的工具
final class ReadClipboardTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `read_clipboard`
    /// - parameters: 无入参
    var definition: ToolDefinition {
        ToolDefinition(
            name: "read_clipboard",
            description: "读取系统剪贴板文本内容",
            parameters: ["type": "object", "properties": [:], "required": []]
        )
    }

    /// 读取剪贴板文本
    ///
    /// - Parameter arguments: 无参数
    /// - Returns: 剪贴板文本内容，为空时返回 "剪贴板为空"
    /// - Throws: 不抛异常
    @MainActor
    func execute(arguments _: [String: Any]) async throws -> String {
        #if os(iOS)
        let content = UIPasteboard.general.string ?? ""
        #else
        let content = NSPasteboard.general.string(forType: .string) ?? ""
        #endif
        if content.isEmpty {
            return "剪贴板为空"
        }
        return content
    }
}

/// 将文本写入系统剪贴板的工具
final class WriteClipboardTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `write_clipboard`
    /// - parameters: `text`（必填，String）— 要写入剪贴板的文本
    var definition: ToolDefinition {
        ToolDefinition(
            name: "write_clipboard",
            description: "将文本写入系统剪贴板",
            parameters: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "要写入剪贴板的文本"]
                ],
                "required": ["text"]
            ]
        )
    }

    /// 将文本写入剪贴板
    ///
    /// - Parameter arguments: 含 `text` 键的参数字典
    /// - Returns: 成功返回 "已复制到剪贴板"，失败返回错误信息
    /// - Throws: 不抛异常，错误以字符串形式返回
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let text = arguments["text"] as? String, !text.isEmpty else {
            return "错误：请提供要写入的文本"
        }
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        // macOS 写入前需先清空剪贴板，再设置文本内容
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        return "已复制到剪贴板"
    }
}
