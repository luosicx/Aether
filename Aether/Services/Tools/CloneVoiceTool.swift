import Foundation
import AetherFoundation

/// v1.3: 语音克隆工具。
///
/// 调用 `MultimodalFacade.cloneVoice` 进行端侧语音克隆。
/// 基于 OpenVoice v2 蒸馏版本，接受 5 秒样本生成定制音色。
///
/// 调用方式：execute(arguments: ["audio_path": "...", "voice_name": "我的音色"])
final class CloneVoiceTool: ToolProtocol, @unchecked Sendable {
    var definition: ToolDefinition {
        ToolDefinition(
            name: "clone_voice",
            description: "从音频样本克隆用户音色（≥5s），后续 TTS 可使用该音色合成语音",
            parameters: [
                "type": "object",
                "properties": [
                    "audio_path": ["type": "string", "description": "音频样本路径（≥5s，WAV / CAF / m4a）"],
                    "voice_name": ["type": "string", "description": "用户自定义音色名称"]
                ],
                "required": ["audio_path", "voice_name"]
            ]
        )
    }

    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let audioPath = arguments["audio_path"] as? String, !audioPath.isEmpty else {
            return "错误：请提供 audio_path 参数"
        }
        guard let voiceName = arguments["voice_name"] as? String, !voiceName.isEmpty else {
            return "错误：请提供 voice_name 参数"
        }

        let facade = MultimodalFacade.shared
        do {
            let voice = try await facade.cloneVoice(audioPath: URL(fileURLWithPath: audioPath), voiceName: voiceName)
            return "音色克隆成功：\(voice.name)（ID: \(voice.id)）"
        } catch let error as MultimodalError {
            return "语音克隆失败：\(error.errorDescription ?? "未知错误")"
        } catch {
            return "语音克隆失败：\(error.localizedDescription)"
        }
    }
}
