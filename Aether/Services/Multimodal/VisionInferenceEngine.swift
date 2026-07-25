import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// v1.3: 视觉理解引擎协议。
///
/// 抽象端侧 VLM（Visual Language Model）推理能力。
/// 默认实现 `PlaceholderVisionEngine` 返回未加载提示；
/// MLX-VLM 集成后由 `MLXVisionEngine` 接管真实推理。
///
/// 设计参考 `MLXInferenceEngine` 的条件编译模式：
/// - mlx-swift-vlm 可用时：调用真实 VLM 模型
/// - 不可用时：返回 `MultimodalError.engineNotLoaded`
public protocol VisionInferenceEngine: Sendable {
    /// 引擎是否已加载模型
    var isLoaded: Bool { get }

    /// 当前加载的模型名称（用于 UI 展示与日志诊断）
    var loadedModelName: String? { get }

    /// 加载 VLM 模型
    /// - Parameters:
    ///   - modelPath: 模型目录路径（含 config.json / tokenizer.json / model.safetensors）
    ///   - modelName: 模型名称（用于 UI 展示）
    /// - Throws: `MultimodalError.modelDownloadFailed` / `OnDeviceError`
    func loadModel(at modelPath: URL, modelName: String) async throws

    /// 卸载模型，释放内存
    func unloadModel() async

    /// 图像理解：根据图像与文本提示生成描述
    /// - Parameters:
    ///   - image: 输入图像（CGImage 跨平台）
    ///   - prompt: 文本提示（如 "描述这张图片" / "图中有几个物体？"）
    /// - Returns: VLM 生成的文本响应
    /// - Throws: `MultimodalError.engineNotLoaded` / `vlmInferenceFailed`
    func describe(image: CGImage, prompt: String) async throws -> String
}

/// v1.3: `VisionInferenceEngine` 的占位实现。
///
/// 在 MLX-VLM 集成前作为默认引擎，所有方法返回 `engineNotLoaded` 错误。
/// 集成 MLX-VLM 后，将 `MLXVisionEngine` 注册到 `MultimodalFacade` 即可替换。
public final class PlaceholderVisionEngine: VisionInferenceEngine, @unchecked Sendable {
    public init() {}

    public private(set) var isLoaded = false
    public private(set) var loadedModelName: String?

    public func loadModel(at modelPath: URL, modelName: String) async throws {
        // 占位实现：标记为已加载但实际不调用 MLX
        // 真实 MLX-VLM 集成后将调用 ModelContainer.load
        isLoaded = true
        loadedModelName = modelName
    }

    public func unloadModel() async {
        isLoaded = false
        loadedModelName = nil
    }

    public func describe(image: CGImage, prompt: String) async throws -> String {
        guard isLoaded else {
            throw MultimodalError.engineNotLoaded
        }
        // 占位实现：返回提示信息，不调用真实 VLM
        return "[VLM 占位] 已接收图像（尺寸 \(image.width)×\(image.height)）与提示：\(prompt)。MLX-VLM 集成后将返回真实描述。"
    }
}
