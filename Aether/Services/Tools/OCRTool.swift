/// 图片文字识别工具（macOS only）
///
/// 使用 Vision 框架的 VNRecognizeTextRequest 对截图或图片文件做 OCR，提取其中的文字。
/// 调用方式：execute(arguments: ["image_path": "..."])，image_path 可选，不传则先截屏再识别。
/// 支持简体中文和英文识别，识别精度设为 accurate。
#if os(macOS)
import Foundation
import AppKit
import Vision

/// macOS 文字识别工具，使用 Vision 框架对截图或图片文件做 OCR
final class OCRTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `extract_text_from_image`
    /// - parameters: `image_path`（可选，String）— 图片文件路径，不传则截取当前屏幕
    var definition: ToolDefinition {
        ToolDefinition(
            name: "extract_text_from_image",
            description: "从图片或截图中识别文字（OCR），不传 image_path 则先截屏再识别",
            parameters: [
                "type": "object",
                "properties": [
                    "image_path": ["type": "string", "description": "图片文件路径，不传则截取当前屏幕"]
                ],
                "required": []
            ]
        )
    }

    /// 执行 OCR 文字识别
    ///
    /// - Parameter arguments: 可含 `image_path` 键的参数字典
    /// - Returns: 识别到的文字字符串，多行用换行符分隔；无文字时返回提示
    /// - Throws: Vision 识别过程中的错误会抛出
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        // 确定图片来源：优先用传入路径，否则调用 ScreenshotTool 截屏
        let imagePath: String
        if let path = arguments["image_path"] as? String, !path.isEmpty {
            imagePath = path
        } else {
            // 截屏
            let screenshotTool = ScreenshotTool()
            let result = try await screenshotTool.execute(arguments: [:])
            if result.hasPrefix("错误") {
                return "截屏失败：\(result)"
            }
            imagePath = result
        }
        // 加载图片并转为 CGImage 供 Vision 使用
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return "错误：无法加载图片：\(imagePath)"
        }
        // 用 continuation 将 Vision 的回调式 API 包装为 async 调用
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                // 取每个观测结果中置信度最高的候选文本
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                if texts.isEmpty {
                    continuation.resume(returning: "未识别到文字")
                } else {
                    continuation.resume(returning: texts.joined(separator: "\n"))
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en"]
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
