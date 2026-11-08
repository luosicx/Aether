import Foundation
import CoreGraphics
#if canImport(CoreML)
import CoreML
#endif

/// v1.6: 基于 Stable Diffusion Mobile 的端侧图像生成引擎。
///
/// 当 apple/swift-coreml Stable Diffusion 包可用时调用真实生成；
/// 不可用时抛出 `platformUnsupported` 错误。
///
/// - 版本：v1.6 计划实现（端侧多模态 Phase 2）
/// - 底层：Stable Diffusion Mobile / CoreML 量化
/// - 状态：apple/swift-coreml SPM 集成后激活
public final class SDMobileEngine: ImageGenerationEngine, @unchecked Sendable {
    #if canImport(CoreML)
    private let coreMLModel: Any? = nil  // CoreML SD 模型占位
    #endif

    public init() {}

    public var name: String { "SDMobile (Stable Diffusion CoreML)" }
    public var isLoaded: Bool { false }

    public func loadModel(at modelPath: URL) async throws {
        // CoreML SD 模型加载
        // 当前桩实现
    }

    public func unloadModel() async {
        // 释放 CoreML 模型
    }

    public func generate(
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 20,
        seed: UInt64? = nil
    ) async throws -> CGImage {
        // CoreML SD 推理
        // 当前未集成 CoreML SD 包，抛出 platformUnsupported
        throw MultimodalError.platformUnsupported
    }
}
