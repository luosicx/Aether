import Foundation

/// v1.3: 语音合成引擎协议（TTS, Text-to-Speech）。
///
/// 抽象端侧 TTS 能力，支持两种后端：
/// - `AVSpeechSynthesizer`（Apple 系统默认）
/// - `MLX-Voice`（Apple 开源 Kokoro/Matcha-TTS，自然度更高）
///
/// `VoiceService` 持有 `TTSEngine` 协议引用，默认委托 AVSpeechSynthesizer，
/// 用户启用 MLX-Voice 后切换后端。
public protocol TTSEngine: Sendable {
    /// 引擎名称
    var name: String { get }

    /// 引擎是否已加载模型（MLX-Voice 后端需先 loadModel）
    var isLoaded: Bool { get }

    /// 加载 TTS 模型（仅 MLX-Voice 后端需要）
    /// - Parameter modelPath: 模型目录路径
    /// - Throws: `MultimodalError.modelDownloadFailed`
    func loadModel(at modelPath: URL) async throws

    /// 合成语音
    /// - Parameters:
    ///   - text: 待合成文本
    ///   - voiceId: 音色 ID（默认音色传 nil；克隆音色传 VoiceCloner 生成的 ID）
    /// - Returns: 合成的音频数据（PCM/WAV）
    /// - Throws: `MultimodalError.ttsSynthesisFailed` / `emptyInput`
    func synthesize(text: String, voiceId: String?) async throws -> Data
}

/// v1.3: `TTSEngine` 的占位实现。
///
/// 在 MLX-Voice 集成前作为默认引擎，`synthesize` 返回空 Data。
/// 集成后将由 `MLXVoiceTTSEngine` 接管真实合成。
public final class PlaceholderTTSEngine: TTSEngine, @unchecked Sendable {
    public init() {}

    public let name = "PlaceholderTTS"
    public private(set) var isLoaded = false

    public func loadModel(at modelPath: URL) async throws {
        isLoaded = true
    }

    public func synthesize(text: String, voiceId: String?) async throws -> Data {
        guard isLoaded else {
            throw MultimodalError.engineNotLoaded
        }
        guard !text.isEmpty else {
            throw MultimodalError.emptyInput
        }
        // 占位实现：返回空 Data
        // 真实 MLX-Voice 集成后返回 PCM 音频数据
        return Data()
    }
}
