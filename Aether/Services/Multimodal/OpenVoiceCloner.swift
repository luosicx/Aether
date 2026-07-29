import Foundation
#if canImport(Security)
import Security
#endif

/// v1.6: 基于 OpenVoice v2 的语音克隆引擎。
///
/// 当 OpenVoice ONNX/CoreML 模型可用时调用真实克隆；
/// 不可用时返回占位音色（固定 embedding 向量）。
///
/// - 版本：v1.6 计划实现（端侧多模态 Phase 2）
/// - 底层：OpenVoice v2 蒸馏模型（ONNX/CoreML）
/// - 存储：音色嵌入向量存 Keychain
/// - 状态：端侧蒸馏模型待转换，当前走桩实现
public final class OpenVoiceCloner: VoiceCloner, @unchecked Sendable {
    public init() {}

    public var name: String { "OpenVoiceCloner (OpenVoice v2)" }
    public var requiresNetwork: Bool { false }
    public var isLoaded: Bool { false }

    public private(set) var clonedVoices: [ClonedVoice] = []

    public func loadModel(at modelPath: URL) async throws {
        // OpenVoice v2 模型加载
        // 当前桩实现：不实际加载
    }

    public func clone(audioPath: URL, voiceName: String) async throws -> ClonedVoice {
        guard FileManager.default.fileExists(atPath: audioPath.path) else {
            throw MultimodalError.emptyInput
        }
        // 生成固定 embedding 占位（实际应通过 OpenVoice v2 提取音色嵌入）
        let embedding = generatePlaceholderEmbedding()
        let voice = ClonedVoice(
            id: UUID().uuidString,
            name: voiceName,
            createdAt: Date(),
            sampleAudioPath: audioPath,
            embeddingBase64: embedding
        )
        clonedVoices.append(voice)
        // 存储 embedding 到 Keychain
        saveToKeychain(voice)
        return voice
    }

    public func deleteVoice(voiceId: String) async {
        clonedVoices.removeAll { $0.id == voiceId }
        deleteFromKeychain(voiceId: voiceId)
    }

    public func voice(forId id: String) -> ClonedVoice? {
        clonedVoices.first { $0.id == id }
    }

    // MARK: - Private

    private func generatePlaceholderEmbedding() -> String {
        // 生成 256 维固定 embedding 占位（实际应通过 OpenVoice v2 提取）
        let vector = (0..<256).map { _ in Double.random(in: -1...1) }
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        return data.base64EncodedString()
    }

    private func saveToKeychain(_ voice: ClonedVoice) {
        #if canImport(Security)
        let data = voice.embeddingBase64.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "aether_voice_\(voice.id)",
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
        #endif
    }

    private func deleteFromKeychain(voiceId: String) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "aether_voice_\(voiceId)"
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}
