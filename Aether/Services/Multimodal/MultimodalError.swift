import Foundation

/// v1.3: 端侧多模态错误类型。
///
/// 覆盖 VLM / ASR / TTS / VoiceCloner / SD 五个子引擎的失败场景。
/// 与 `OnDeviceError` 互补：`OnDeviceError` 关注模型加载阶段，
/// `MultimodalError` 关注推理 / 合成 / 克隆阶段。
public enum MultimodalError: LocalizedError, Sendable, Equatable {
    /// 引擎未加载模型（VLM/Whisper/SD 等需要先 loadModel）
    case engineNotLoaded
    /// 输入为空（空图像 / 空音频 / 空文本）
    case emptyInput
    /// 不支持的图像格式（仅支持 JPEG/PNG/HEIC）
    case unsupportedImageFormat
    /// 不支持的音频格式（仅支持 WAV/CAF/m4a）
    case unsupportedAudioFormat
    /// 不支持的音频采样率
    case unsupportedSampleRate(actual: Double)
    /// 音频时长不足（克隆至少 5s）
    case audioTooShort(actualSeconds: Double, requiredSeconds: Double)
    /// 内存预算超限（请求的内存超过 `MemoryBudget` 剩余额度）
    case memoryBudgetExceeded(requestedMB: Int, availableMB: Int)
    /// 设备能力不足（如 iPhone 不支持 7B VLM，需降级到 2B）
    case deviceCapabilityInsufficient(required: String, actual: String)
    /// VLM 推理失败（含底层错误信息）
    case vlmInferenceFailed(message: String)
    /// ASR 识别失败
    case asrRecognitionFailed(message: String)
    /// TTS 合成失败
    case ttsSynthesisFailed(message: String)
    /// 语音克隆失败（音色提取 / 模型加载等）
    case voiceCloneFailed(message: String)
    /// 图像生成失败（SD 推理失败）
    case imageGenerationFailed(message: String)
    /// OCR 识别失败（Vision 框架错误）
    case ocrFailed(message: String)
    /// 模型下载失败（委托 OnDeviceModelDownloader 时）
    case modelDownloadFailed(message: String)
    /// 平台不支持（如 SD Mobile 仅 macOS）
    case platformUnsupported

    /// 用户友好的错误描述
    public var errorDescription: String? {
        switch self {
        case .engineNotLoaded:
            return NSLocalizedString("多模态引擎未加载模型，请先下载并加载对应模型", comment: "")
        case .emptyInput:
            return NSLocalizedString("输入为空，请提供有效的图像 / 音频 / 文本", comment: "")
        case .unsupportedImageFormat:
            return NSLocalizedString("不支持的图像格式，仅支持 JPEG / PNG / HEIC", comment: "")
        case .unsupportedAudioFormat:
            return NSLocalizedString("不支持的音频格式，仅支持 WAV / CAF / m4a", comment: "")
        case .unsupportedSampleRate(let actual):
            return String(format: NSLocalizedString("不支持的音频采样率（实际 %@Hz），需 16000Hz", comment: ""), String(actual))
        case .audioTooShort(let actual, let required):
            return String(format: NSLocalizedString("音频时长不足（实际 %.1fs，需 ≥%.1fs）", comment: ""), actual, required)
        case .memoryBudgetExceeded(let requested, let available):
            return String(format: NSLocalizedString("内存预算超限（请求 %dMB，剩余 %dMB）", comment: ""), requested, available)
        case .deviceCapabilityInsufficient(let required, let actual):
            return String(format: NSLocalizedString("设备能力不足（需 %@，实际 %@）", comment: ""), required, actual)
        case .vlmInferenceFailed(let message):
            return String(format: NSLocalizedString("图像理解失败：%@", comment: ""), message)
        case .asrRecognitionFailed(let message):
            return String(format: NSLocalizedString("语音识别失败：%@", comment: ""), message)
        case .ttsSynthesisFailed(let message):
            return String(format: NSLocalizedString("语音合成失败：%@", comment: ""), message)
        case .voiceCloneFailed(let message):
            return String(format: NSLocalizedString("语音克隆失败：%@", comment: ""), message)
        case .imageGenerationFailed(let message):
            return String(format: NSLocalizedString("图像生成失败：%@", comment: ""), message)
        case .ocrFailed(let message):
            return String(format: NSLocalizedString("文字识别失败：%@", comment: ""), message)
        case .modelDownloadFailed(let message):
            return String(format: NSLocalizedString("模型下载失败：%@", comment: ""), message)
        case .platformUnsupported:
            return NSLocalizedString("当前平台不支持此功能", comment: "")
        }
    }

    /// 诊断描述（含底层信息），用于日志输出
    public var diagnosticDescription: String {
        switch self {
        case .engineNotLoaded:
            return "MultimodalError.engineNotLoaded"
        case .emptyInput:
            return "MultimodalError.emptyInput"
        case .unsupportedImageFormat:
            return "MultimodalError.unsupportedImageFormat"
        case .unsupportedAudioFormat:
            return "MultimodalError.unsupportedAudioFormat"
        case .unsupportedSampleRate(let actual):
            return "MultimodalError.unsupportedSampleRate(actual=\(actual))"
        case .audioTooShort(let actual, let required):
            return "MultimodalError.audioTooShort(actual=\(actual), required=\(required))"
        case .memoryBudgetExceeded(let requested, let available):
            return "MultimodalError.memoryBudgetExceeded(requested=\(requested)MB, available=\(available)MB)"
        case .deviceCapabilityInsufficient(let required, let actual):
            return "MultimodalError.deviceCapabilityInsufficient(required=\(required), actual=\(actual))"
        case .vlmInferenceFailed(let message):
            return "MultimodalError.vlmInferenceFailed(\(message))"
        case .asrRecognitionFailed(let message):
            return "MultimodalError.asrRecognitionFailed(\(message))"
        case .ttsSynthesisFailed(let message):
            return "MultimodalError.ttsSynthesisFailed(\(message))"
        case .voiceCloneFailed(let message):
            return "MultimodalError.voiceCloneFailed(\(message))"
        case .imageGenerationFailed(let message):
            return "MultimodalError.imageGenerationFailed(\(message))"
        case .ocrFailed(let message):
            return "MultimodalError.ocrFailed(\(message))"
        case .modelDownloadFailed(let message):
            return "MultimodalError.modelDownloadFailed(\(message))"
        case .platformUnsupported:
            return "MultimodalError.platformUnsupported"
        }
    }
}
