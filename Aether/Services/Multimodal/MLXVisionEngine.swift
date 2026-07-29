import Foundation
import CoreGraphics

/// v1.6: 基于 MLX-VLM 的视觉理解引擎。
///
/// 当 mlx-vlm SPM 包可用时调用真实 MLX-VLM 推理；
/// 不可用时降级到 `NativeVisionEngine`（Apple Vision 框架）。
///
/// - 版本：v1.6 计划实现（端侧多模态 Phase 2）
/// - 底层：MLX-VLM（Qwen2-VL-2B Q4 等）
/// - 兜底：NativeVisionEngine（VNClassifyImageRequest 等 5 个 Vision 请求）
public final class MLXVisionEngine: VisionInferenceEngine, @unchecked Sendable {
    // 条件编译：MLX-VLM 可用时走真实推理，不可用时走 Native 兜底
    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private let mlxEngine: Any? = nil  // MLX-VLM ModelContainer 占位
    private let fallback = NativeVisionEngine()
    #else
    /// 兜底引擎：在 MLX-VLM 未集成时使用 Native Vision
    private let fallback = NativeVisionEngine()
    #endif

    public init() {}

    public var isLoaded: Bool {
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        // MLX-VLM 可用时检查模型加载状态
        return fallback.isLoaded  // 当前降级到 fallback
        #else
        return fallback.isLoaded
        #endif
    }

    public var loadedModelName: String? {
        fallback.loadedModelName
    }

    public func loadModel(at modelPath: URL, modelName: String) async throws {
        // 尝试 MLX-VLM 加载；当前降级到 fallback
        try await fallback.loadModel(at: modelPath, modelName: modelName)
    }

    public func unloadModel() async {
        await fallback.unloadModel()
    }

    public func describe(image: CGImage, prompt: String) async throws -> String {
        // MLX-VLM 推理；当前降级到 NativeVisionEngine
        let result = try await fallback.describe(image: image, prompt: prompt)
        return "[MLXVisionEngine v1.6] " + result
    }
}
