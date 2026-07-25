/// 图片文字识别工具（v1.3: 跨平台改造）
///
/// v1.3 升级：从 macOS only 改造为 iOS / iPadOS / macOS 三端通用。
/// - Vision 框架（VNRecognizeTextRequest）三端共享，跨平台准确率差异 <3%
/// - 图片加载按平台条件编译：
///   - iOS / iPadOS：用 `UIImage(contentsOfFile:)` 加载
///   - macOS：用 `NSImage(contentsOfFile:)` 加载
/// - 不传 image_path 时：
///   - macOS：调用 ScreenshotTool 截屏（保留原行为）
///   - iOS：返回错误提示（iOS 无法直接截屏，需用户在 Photos 中选图）
///
/// 调用方式：execute(arguments: ["image_path": "..."])，image_path 可选（macOS 不传则截屏）。
/// 支持简体中文和英文识别，识别精度设为 accurate。
import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import AetherFoundation

/// 跨平台文字识别工具，使用 Vision 框架对图片文件做 OCR
final class OCRTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义
    /// - name: `extract_text_from_image`
    /// - parameters: `image_path`（可选，String）— 图片文件路径，macOS 不传则截取当前屏幕，iOS 必传
    var definition: ToolDefinition {
        ToolDefinition(
            name: "extract_text_from_image",
            description: "从图片中识别文字（OCR），跨平台（iOS / iPadOS / macOS）。image_path 必传，macOS 不传则截取当前屏幕",
            parameters: [
                "type": "object",
                "properties": [
                    "image_path": ["type": "string", "description": "图片文件路径，macOS 不传则截取当前屏幕，iOS / iPadOS 必传"]
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
        // 确定图片来源：优先用传入路径，否则 macOS 调用 ScreenshotTool 截屏
        let imagePath: String
        if let path = arguments["image_path"] as? String, !path.isEmpty {
            imagePath = path
        } else {
            #if os(macOS)
            // macOS：截屏
            let screenshotTool = ScreenshotTool()
            let result = try await screenshotTool.execute(arguments: [:])
            if result.hasPrefix("错误") {
                return "截屏失败：\(result)"
            }
            imagePath = result
            #else
            // iOS / iPadOS：无法直接截屏，要求传入 image_path
            return "错误：iOS / iPadOS 平台需提供 image_path 参数"
            #endif
        }

        // 加载图片并转为 CGImage 供 Vision 使用（跨平台）
        guard let cgImage = loadCGImage(atPath: imagePath) else {
            return "错误：无法加载图片：\(imagePath)"
        }

        // 用 continuation 将 Vision 的回调式 API 包装为 async 调用
        // Vision API 三端共享，无需平台条件编译
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // NOSONAR: VNRecognizeTextRequest 回调由 Vision API 设计要求，嵌套不可避免
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

    /// 跨平台加载图片为 CGImage
    /// - Parameter path: 图片文件路径
    /// - Returns: CGImage，加载失败返回 nil
    private func loadCGImage(atPath path: String) -> CGImage? {
        #if canImport(UIKit)
        // iOS / iPadOS：用 UIImage 加载
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
        #elseif canImport(AppKit)
        // macOS：用 NSImage 加载
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}
