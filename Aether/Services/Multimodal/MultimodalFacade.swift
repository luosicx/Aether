import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// v1.3: 多模态融合 Facade。
///
/// 统一对外暴露 VLM / ASR / TTS / VoiceCloner / ImageGen 五个引擎的接口，
/// 内部委托给具体引擎实现，便于 LLM Tool 调用与上层业务集成。
///
/// 设计参考 MASTER_PLAN §6.1.5：
/// > `MultimodalFacade` 4 个接口全部实现并注册到 `ToolRegistry`，
/// > LLM 可调用 4 个新工具
///
/// 使用方式：
/// ```swift
/// let facade = MultimodalFacade.shared
/// let description = try await facade.describeImage(at: url, prompt: "描述这张图片")
/// let transcript = try await facade.transcribeAudio(at: url, language: "zh")
/// ```
public actor MultimodalFacade {
    /// 单例
    public static let shared = MultimodalFacade()

    /// 视觉理解引擎（默认占位）
    private var visionEngine: VisionInferenceEngine
    /// ASR 引擎（默认占位）
    private var asrEngine: ASREngine
    /// TTS 引擎（默认占位）
    private var ttsEngine: TTSEngine
    /// 语音克隆引擎（默认占位）
    private var voiceCloner: VoiceCloner
    /// 图像生成引擎（默认占位）
    private var imageGenEngine: ImageGenerationEngine
    /// 内存预算器
    private let budget: MemoryBudget

    public init() {
        // v1.4: 默认使用 Apple 原生引擎（Vision / Speech / AVFoundation）
        // MLX-VLM / Whisper.cpp / MLX-Voice 集成后通过 setXxxEngine 切换
        self.visionEngine = NativeVisionEngine()
        self.asrEngine = NativeASREngine()
        self.ttsEngine = NativeTTSEngine()
        self.voiceCloner = PlaceholderVoiceCloner()
        self.imageGenEngine = PlaceholderImageGenerationEngine()
        self.budget = .shared
    }

    /// 测试可注入的初始化器（默认参数允许回退到占位实现）
    public init(
        visionEngine: VisionInferenceEngine = NativeVisionEngine(),
        asrEngine: ASREngine = NativeASREngine(),
        ttsEngine: TTSEngine = NativeTTSEngine(),
        voiceCloner: VoiceCloner = PlaceholderVoiceCloner(),
        imageGenEngine: ImageGenerationEngine = PlaceholderImageGenerationEngine(),
        budget: MemoryBudget = .shared
    ) {
        self.visionEngine = visionEngine
        self.asrEngine = asrEngine
        self.ttsEngine = ttsEngine
        self.voiceCloner = voiceCloner
        self.imageGenEngine = imageGenEngine
        self.budget = budget
    }

    // MARK: - 引擎切换（依赖注入）

    public func setVisionEngine(_ engine: VisionInferenceEngine) {
        visionEngine = engine
    }

    public func setASREngine(_ engine: ASREngine) {
        asrEngine = engine
    }

    public func setTTSEngine(_ engine: TTSEngine) {
        ttsEngine = engine
    }

    public func setVoiceCloner(_ cloner: VoiceCloner) {
        voiceCloner = cloner
    }

    public func setImageGenEngine(_ engine: ImageGenerationEngine) {
        imageGenEngine = engine
    }

    // MARK: - 引擎状态查询

    public var visionEngineName: String { String(describing: type(of: visionEngine)) }
    public var asrEngineName: String { asrEngine.name }
    public var ttsEngineName: String { ttsEngine.name }
    public var voiceClonerName: String { String(describing: type(of: voiceCloner)) }
    public var imageGenEngineName: String { imageGenEngine.name }

    // MARK: - VLM 图像理解

    /// 描述图像
    /// - Parameters:
    ///   - imagePath: 图像文件路径
    ///   - prompt: 文本提示
    /// - Returns: VLM 生成的描述
    public func describeImage(at imagePath: URL, prompt: String) async throws -> String {
        guard !prompt.isEmpty else {
            throw MultimodalError.emptyInput
        }
        guard let cgImage = loadImageAsCGImage(at: imagePath) else {
            throw MultimodalError.unsupportedImageFormat
        }
        return try await visionEngine.describe(image: cgImage, prompt: prompt)
    }

    // MARK: - ASR 语音识别

    /// 转写音频文件
    /// - Parameters:
    ///   - audioPath: 音频文件路径
    ///   - language: 语言代码（如 "zh" / "en"）
    /// - Returns: 识别到的文字
    public func transcribeAudio(at audioPath: URL, language: String = "zh") async throws -> String {
        guard FileManager.default.fileExists(atPath: audioPath.path) else {
            throw MultimodalError.emptyInput
        }
        return try await asrEngine.transcribe(audioPath: audioPath, language: language)
    }

    // MARK: - TTS 语音合成

    /// 合成语音
    /// - Parameters:
    ///   - text: 待合成文本
    ///   - voiceId: 音色 ID（nil 表示默认音色）
    /// - Returns: 合成的音频数据
    public func synthesizeSpeech(text: String, voiceId: String? = nil) async throws -> Data {
        guard !text.isEmpty else {
            throw MultimodalError.emptyInput
        }
        return try await ttsEngine.synthesize(text: text, voiceId: voiceId)
    }

    // MARK: - 语音克隆

    /// 克隆音色
    /// - Parameters:
    ///   - audioPath: 样本音频路径（≥5s）
    ///   - voiceName: 用户自定义音色名称
    /// - Returns: 克隆后的音色
    public func cloneVoice(audioPath: URL, voiceName: String) async throws -> ClonedVoice {
        try await voiceCloner.clone(audioPath: audioPath, voiceName: voiceName)
    }

    /// 已克隆的音色列表
    public func clonedVoices() async -> [ClonedVoice] {
        voiceCloner.clonedVoices
    }

    /// 删除指定音色
    public func deleteVoice(voiceId: String) async {
        await voiceCloner.deleteVoice(voiceId: voiceId)
    }

    // MARK: - 图像生成

    /// 生成图像
    /// - Parameters:
    ///   - prompt: 文本提示
    ///   - negativePrompt: 负面提示
    ///   - width: 宽度（默认 512）
    ///   - height: 高度（默认 512）
    ///   - steps: 推理步数（默认 20）
    ///   - seed: 随机种子
    /// - Returns: 生成的图像
    public func generateImage(
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 20,
        seed: UInt64? = nil
    ) async throws -> CGImage {
        guard !prompt.isEmpty else {
            throw MultimodalError.emptyInput
        }
        return try await imageGenEngine.generate(
            prompt: prompt,
            negativePrompt: negativePrompt,
            width: width,
            height: height,
            steps: steps,
            seed: seed
        )
    }

    // MARK: - 内存预算

    public func budgetSnapshot() async -> BudgetSnapshot {
        await budget.snapshot()
    }

    // MARK: - 内部辅助

    /// 加载图片文件为 CGImage（跨平台）
    private func loadImageAsCGImage(at url: URL) -> CGImage? {
        #if canImport(UIKit)
        guard let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}
