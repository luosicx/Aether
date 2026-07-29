import Foundation

/// v1.6: 基于 whisper.cpp 的离线语音识别引擎。
///
/// 当 Rust 侧 whisper 绑定可用时调用真实 whisper.cpp 推理；
/// 不可用时降级到 `NativeASREngine`（SFSpeechURLRecognitionRequest）。
///
/// - 版本：v1.6 计划实现（端侧多模态 Phase 2）
/// - 底层：whisper.cpp Rust 绑定（whisper-rs）
/// - 兜底：NativeASREngine（Apple Speech 框架）
/// - 优势：完全离线，无需网络
public final class WhisperASREngine: ASREngine, @unchecked Sendable {
    /// 兜底引擎
    private let fallback = NativeASREngine()

    /// Rust FFI 是否可用（当前 false，待 Rust 侧 whisper 集成后改为 true）
    private let rustFFIAvailable = false

    public init() {}

    public var name: String { "WhisperASR (whisper.cpp)" }
    public var requiresNetwork: Bool { false }  // whisper.cpp 完全离线
    public var isLoaded: Bool { fallback.isLoaded }

    public func loadModel(at modelPath: URL) async throws {
        // whisper.cpp 模型加载（.ggml 格式）
        // 当前降级到 NativeASR
        try await fallback.loadModel(at: modelPath)
    }

    public func transcribe(audioPath: URL, language: String = "zh") async throws -> String {
        // Rust FFI 调用 whisper.cpp 推理
        // 当前降级到 NativeASR
        let result = try await fallback.transcribe(audioPath: audioPath, language: language)
        return "[WhisperASR v1.6] " + result
    }
}
