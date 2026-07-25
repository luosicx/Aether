import Foundation
import CoreGraphics

/// v1.3: 端侧图像生成引擎协议。
///
/// 基于 Stable Diffusion Mobile / Apple Visual Intelligence。
/// v1.3 仅提供协议与占位实现，v1.5 集成真实 SD Mobile。
public protocol ImageGenerationEngine: Sendable {
    /// 引擎名称
    var name: String { get }

    /// 引擎是否已加载模型
    var isLoaded: Bool { get }

    /// 加载模型
    /// - Parameter modelPath: 模型目录路径
    /// - Throws: `MultimodalError.modelDownloadFailed`
    func loadModel(at modelPath: URL) async throws

    /// 卸载模型，释放内存
    func unloadModel() async

    /// 生成图像
    /// - Parameters:
    ///   - prompt: 文本提示
    ///   - negativePrompt: 负面提示（不希望出现的内容）
    ///   - width: 图像宽度（默认 512）
    ///   - height: 图像高度（默认 512）
    ///   - steps: 推理步数（默认 20）
    ///   - seed: 随机种子（nil 表示随机）
    /// - Returns: 生成的图像（CGImage 跨平台）
    /// - Throws: `MultimodalError.imageGenerationFailed` / `emptyInput` / `platformUnsupported`
    func generate(
        prompt: String,
        negativePrompt: String?,
        width: Int,
        height: Int,
        steps: Int,
        seed: UInt64?
    ) async throws -> CGImage
}

/// v1.3: `ImageGenerationEngine` 的占位实现。
///
/// 在 SD Mobile 集成前作为默认引擎，`generate` 返回 `platformUnsupported` 错误。
/// v1.5 集成后将由 `SDMobileEngine` 接管真实推理。
public final class PlaceholderImageGenerationEngine: ImageGenerationEngine, @unchecked Sendable {
    public init() {}

    public let name = "PlaceholderImageGen"
    public let isLoaded = false

    public func loadModel(at modelPath: URL) async throws {
        // 占位实现：实际不加载模型
    }

    public func unloadModel() async {
        // 占位实现：no-op
    }

    public func generate(
        prompt: String,
        negativePrompt: String?,
        width: Int,
        height: Int,
        steps: Int,
        seed: UInt64?
    ) async throws -> CGImage {
        // v1.3 占位实现：图像生成待 v1.5 SD Mobile 集成
        throw MultimodalError.platformUnsupported
    }
}
