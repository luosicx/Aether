import Foundation

/// v1.6: 基于 MLX-Voice 的端侧语音合成引擎。
///
/// 当 MLX-Voice Swift 包可用时调用真实推理；
/// 不可用时降级到 `NativeTTSEngine`（AVSpeechSynthesizer）。
///
/// - 版本：v1.6 计划实现（端侧多模态 Phase 2）
/// - 底层：MLX-Voice（Kokoro / Matcha-TTS）
/// - 兜底：NativeTTSEngine（AVSpeechSynthesizer.write）
/// - 状态：MLX-Voice Swift 包尚未正式发布，当前走兜底逻辑
public final class MLXVoiceTTSEngine: TTSEngine, @unchecked Sendable {
    #if canImport(MLXVoice)
    private let mlxVoice: Any? = nil  // MLX-Voice 模型占位
    #endif
    private let fallback = NativeTTSEngine()

    public init() {}

    public var name: String { "MLXVoiceTTS (Kokoro/Matcha-TTS)" }
    public var isLoaded: Bool { fallback.isLoaded }

    public func loadModel(at modelPath: URL) async throws {
        try await fallback.loadModel(at: modelPath)
    }

    public func synthesize(text: String, voiceId: String? = nil) async throws -> Data {
        // MLX-Voice 推理；当前降级到 NativeTTS
        return try await fallback.synthesize(text: text, voiceId: voiceId)
    }
}
