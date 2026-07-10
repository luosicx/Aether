/// 屏幕截图工具（macOS only）
///
/// 通过 CoreGraphics 的 CGDisplayCreateImage 截取指定显示器屏幕，保存为 PNG 文件并返回文件路径。
/// 调用方式：execute(arguments: ["display_id": 0])，display_id 可选，不传则截取主显示器。
/// 截图保存到系统临时目录，文件名以时间戳命名。
#if os(macOS)
import Foundation
import AppKit
import CoreGraphics

/// macOS 截屏工具
final class ScreenshotTool: ToolProtocol {
    /// 工具定义
    /// - name: `take_screenshot`
    /// - parameters: `display_id`（可选，Integer）— 显示器 ID，不传则截取主显示器
    var definition: ToolDefinition {
        ToolDefinition(
            name: "take_screenshot",
            description: "截取 macOS 屏幕，保存为 PNG 文件，返回文件路径",
            parameters: [
                "type": "object",
                "properties": [
                    "display_id": ["type": "integer", "description": "显示器 ID，不传则截取主显示器"]
                ],
                "required": []
            ]
        )
    }

    /// 截取屏幕并保存为 PNG 文件
    ///
    /// - Parameter arguments: 可含 `display_id` 键的参数字典
    /// - Returns: 成功返回 PNG 文件路径，失败返回错误信息字符串
    /// - Throws: 不抛异常，错误以字符串形式返回
    func execute(arguments: [String: Any]) async throws -> String {
        // 确定目标显示器 ID，未指定时使用主显示器
        let displayID: CGDirectDisplayID
        if let id = arguments["display_id"] as? Int {
            displayID = CGDirectDisplayID(id)
        } else {
            displayID = CGMainDisplayID()
        }
        // 通过 CoreGraphics 截取指定显示器的画面
        guard let image = CGDisplayCreateImage(displayID) else {
            return "错误：无法截取屏幕"
        }
        // 将 CGImage 转为 NSBitmapImageRep 以便编码为 PNG
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return "错误：无法生成 PNG 数据"
        }
        // 保存到临时目录，文件名带时间戳避免覆盖
        let fileName = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(fileName)
        do {
            try pngData.write(to: URL(fileURLWithPath: filePath))
        } catch {
            return "错误：保存截图失败：\(error.localizedDescription)"
        }
        return filePath
    }
}
#endif
