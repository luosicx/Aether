import Foundation

/// v1.3: 语音克隆引擎协议。
///
/// 基于 OpenVoice v2 端侧蒸馏版本，接受 5 秒样本生成定制音色。
/// 用户首次录音后生成音色嵌入存 Keychain，后续 TTS 注入。
public protocol VoiceCloner: Sendable {
    /// 引擎是否已加载模型
    var isLoaded: Bool { get }

    /// 已克隆的音色列表（音色 ID → 元数据）
    var clonedVoices: [ClonedVoice] { get }

    /// 加载克隆模型（OpenVoice v2 蒸馏版）
    /// - Parameter modelPath: 模型目录路径
    /// - Throws: `MultimodalError.modelDownloadFailed`
    func loadModel(at modelPath: URL) async throws

    /// 克隆音色
    /// - Parameters:
    ///   - audioPath: 音频样本文件路径（≥5s）
    ///   - voiceName: 用户自定义音色名称
    /// - Returns: 克隆后的音色 ID（用于 TTS 引擎注入）
    /// - Throws: `MultimodalError.voiceCloneFailed` / `audioTooShort` / `unsupportedAudioFormat`
    func clone(audioPath: URL, voiceName: String) async throws -> ClonedVoice

    /// 删除指定音色
    /// - Parameter voiceId: 音色 ID
    func deleteVoice(voiceId: String) async

    /// 获取指定音色
    /// - Parameter voiceId: 音色 ID
    /// - Returns: 音色元数据，不存在返回 nil
    func voice(forId voiceId: String) -> ClonedVoice?
}

/// v1.3: 克隆音色元数据
public struct ClonedVoice: Sendable, Equatable, Identifiable {
    /// 唯一 ID（UUID）
    public let id: String
    /// 用户自定义名称
    public let name: String
    /// 创建时间
    public let createdAt: Date
    /// 样本音频路径（用于重新克隆）
    public let sampleAudioPath: URL
    /// 音色嵌入数据（Base64 编码，存 Keychain）
    public let embeddingBase64: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        sampleAudioPath: URL,
        embeddingBase64: String
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sampleAudioPath = sampleAudioPath
        self.embeddingBase64 = embeddingBase64
    }
}

/// v1.3: `VoiceCloner` 的占位实现。
///
/// 在 OpenVoice v2 集成前作为默认引擎，`clone` 返回占位音色。
/// 集成后将由 `OpenVoiceCloner` 接管真实克隆。
public final class PlaceholderVoiceCloner: VoiceCloner, @unchecked Sendable {
    public init() {}

    public private(set) var isLoaded = false
    public private(set) var clonedVoices: [ClonedVoice] = []

    public func loadModel(at modelPath: URL) async throws {
        isLoaded = true
    }

    public func clone(audioPath: URL, voiceName: String) async throws -> ClonedVoice {
        guard isLoaded else {
            throw MultimodalError.engineNotLoaded
        }
        // 占位实现：返回占位音色（embedding 为空字符串）
        // 真实 OpenVoice 集成后将提取音色嵌入
        let voice = ClonedVoice(
            name: voiceName,
            sampleAudioPath: audioPath,
            embeddingBase64: ""
        )
        clonedVoices.append(voice)
        return voice
    }

    public func deleteVoice(voiceId: String) async {
        clonedVoices.removeAll { $0.id == voiceId }
    }

    public func voice(forId voiceId: String) -> ClonedVoice? {
        clonedVoices.first { $0.id == voiceId }
    }
}
