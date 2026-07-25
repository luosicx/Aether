import Foundation

/// v1.3: 语音识别引擎协议（ASR, Automatic Speech Recognition）。
///
/// 抽象端侧 ASR 能力，支持两种后端：
/// - `SFSpeechRecognizer`（Apple 系统默认，在线）
/// - `Whisper.cpp`（开源，离线，待 MLX-Vision 集成）
///
/// `VoiceService` 持有 `ASREngine` 协议引用，默认委托 SFSpeechRecognizer，
/// 离线场景切换到 Whisper 后端。
public protocol ASREngine: Sendable {
    /// 引擎名称（用于 UI 展示与日志诊断）
    var name: String { get }

    /// 引擎是否需要在线网络
    var requiresNetwork: Bool { get }

    /// 引擎是否已加载模型（Whisper 后端需先 loadModel）
    var isLoaded: Bool { get }

    /// 加载 ASR 模型（仅 Whisper 后端需要，SFSpeechRecognizer 直接返回成功）
    /// - Parameter modelPath: 模型文件路径
    /// - Throws: `MultimodalError.modelDownloadFailed`
    func loadModel(at modelPath: URL) async throws

    /// 识别音频文件中的文字
    /// - Parameters:
    ///   - audioPath: 音频文件路径（WAV / CAF / m4a）
    ///   - language: 语言代码（如 "zh" / "en"）
    /// - Returns: 识别到的文字
    /// - Throws: `MultimodalError.asrRecognitionFailed` / `emptyInput` / `unsupportedAudioFormat`
    func transcribe(audioPath: URL, language: String) async throws -> String
}

/// v1.3: `ASREngine` 的占位实现。
///
/// 在 Whisper.cpp 集成前作为默认引擎，`transcribe` 返回提示信息。
/// 集成后将由 `WhisperASREngine` 接管真实推理。
public final class PlaceholderASREngine: ASREngine, @unchecked Sendable {
    public init() {}

    public let name = "PlaceholderASR"
    public let requiresNetwork = false
    public private(set) var isLoaded = false

    public func loadModel(at modelPath: URL) async throws {
        isLoaded = true
    }

    public func transcribe(audioPath: URL, language: String) async throws -> String {
        guard isLoaded else {
            throw MultimodalError.engineNotLoaded
        }
        // 占位实现：返回提示信息
        return "[ASR 占位] 已接收音频文件 \(audioPath.lastPathComponent)（语言 \(language)）。Whisper.cpp 集成后将返回真实转写。"
    }
}
