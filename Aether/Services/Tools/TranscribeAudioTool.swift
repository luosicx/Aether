import Foundation
import AetherFoundation

/// v1.3: 语音转写工具。
///
/// 调用 `MultimodalFacade.transcribeAudio` 进行端侧 ASR 识别。
/// 默认使用 SFSpeechRecognizer（在线），离线场景可切换 Whisper.cpp 后端。
///
/// 调用方式：execute(arguments: ["audio_path": "...", "language": "zh"])
final class TranscribeAudioTool: ToolProtocol, @unchecked Sendable {
    var definition: ToolDefinition {
        ToolDefinition(
            name: "transcribe_audio",
            description: "将音频文件转写为文字（ASR 语音识别），支持中文与英文，跨平台",
            parameters: [
                "type": "object",
                "properties": [
                    "audio_path": ["type": "string", "description": "音频文件路径（WAV / CAF / m4a）"],
                    "language": ["type": "string", "description": "语言代码，如 zh / en，默认 zh"]
                ],
                "required": ["audio_path"]
            ]
        )
    }

    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let audioPath = arguments["audio_path"] as? String, !audioPath.isEmpty else {
            return "错误：请提供 audio_path 参数"
        }
        let language = arguments["language"] as? String ?? "zh"

        let facade = MultimodalFacade.shared
        do {
            let transcript = try await facade.transcribeAudio(at: URL(fileURLWithPath: audioPath), language: language)
            return transcript
        } catch let error as MultimodalError {
            return "语音识别失败：\(error.errorDescription ?? "未知错误")"
        } catch {
            return "语音识别失败：\(error.localizedDescription)"
        }
    }
}
