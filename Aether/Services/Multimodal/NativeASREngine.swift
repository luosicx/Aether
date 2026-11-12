import Foundation
import Speech
@preconcurrency import AVFoundation

/// v1.4: 基于 Apple Speech 框架的 `ASREngine` 原生实现。
///
/// v1.3 提供协议与占位实现，v1.4 使用 `SFSpeechRecognizer` 的
/// 文件识别能力（`SFSpeechURLRecognitionRequest`）实现真实语音识别。
/// 无需 Whisper.cpp 外部依赖，三端原生可用，作为 Whisper 集成前的过渡实现。
///
/// 设计参考 MASTER_PLAN §4.1.5 端侧语音：
/// > 默认 SFSpeechRecognizer（在线），离线降级 Whisper.cpp
/// v1.4 仅实现 SFSpeechRecognizer 路径，Whisper.cpp 待 v1.5+ 集成。
public final class NativeASREngine: ASREngine, @unchecked Sendable {
    public let name = "NativeASR (SFSpeechRecognizer)"
    /// SFSpeechRecognizer 默认需在线（仅 iOS/macOS 支持离线模型下载后可离线）
    public let requiresNetwork = true
    public let isLoaded = true

    public init() {}

    public func loadModel(at modelPath: URL) async throws {
        // SFSpeechRecognizer 无需加载模型文件，保持兼容（no-op）
    }

    /// 识别音频文件中的文字
    ///
    /// 流程：
    /// 1. 校验文件存在与格式（wav / caf / m4a / mp3）
    /// 2. 创建 SFSpeechRecognizer（按 language locale）
    /// 3. 用 `SFSpeechURLRecognitionRequest` 识别文件
    /// 4. 汇总 final 结果
    public func transcribe(audioPath: URL, language: String) async throws -> String {
        // 1. 文件校验
        guard FileManager.default.fileExists(atPath: audioPath.path) else {
            throw MultimodalError.emptyInput
        }
        let ext = audioPath.pathExtension.lowercased()
        let supported = ["wav", "caf", "m4a", "mp3", "mp4", "aac"]
        guard supported.contains(ext) else {
            throw MultimodalError.unsupportedAudioFormat
        }

        // 2. 创建识别器（CI 环境下 SFSpeechRecognizer 可能不可用）
        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw MultimodalError.asrRecognitionFailed(message: "不支持的语言：\(language)")
        }

        // CI 环境下识别器可能不可用，避免测试卡住
        if !recognizer.isAvailable {
            throw MultimodalError.asrRecognitionFailed(message: "语音识别器不可用（可能由于 CI 环境或未授权）")
        }

        // 3. 请求权限（首次使用）
        guard let status = await requestAuthorization(within: Self.authorizationDeadline) else {
            throw MultimodalError.asrRecognitionFailed(
                message: "语音识别授权回调超时（\(Int(Self.authorizationDeadline)) 秒未返回）")
        }
        guard status == .authorized else {
            throw MultimodalError.asrRecognitionFailed(message: "未授权语音识别")
        }

        // 4. 文件识别
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let once = ResumeOnceContinuation(continuation)
            let taskBox = RecognitionTaskBox()
            let request = SFSpeechURLRecognitionRequest(url: audioPath)
            taskBox.set(recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    once.resume(throwing: MultimodalError.asrRecognitionFailed(message: error.localizedDescription))
                    return
                }
                if let result = result, result.isFinal {
                    once.resume(returning: result.bestTranscription.formattedString)
                }
            })
            // 任务可能既不回调也不自行结束（SFSpeechURLRecognitionRequest 不保证
            // 一定送达 isFinal）：到点取消任务并以失败收尾，避免无界等待。
            let seconds = Self.recognitionDeadline
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                taskBox.cancel()
                once.resume(throwing: MultimodalError.asrRecognitionFailed(
                    message: "识别超时（\(Int(seconds)) 秒未返回最终结果）"))
            }
        }
    }

    /// 申请语音识别授权，回调在 `seconds` 内未触发时返回 nil。
    /// `SFSpeechRecognizer.requestAuthorization` 的回调在无语音服务的运行环境
    /// （如模拟器）里可能永不触发，无界 await 会把调用方一起挂死。
    private func requestAuthorization(within seconds: TimeInterval) async -> SFSpeechRecognizerAuthorizationStatus? {
        await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus?, Never>) in
            let once = ResumeOnceContinuation(continuation)
            SFSpeechRecognizer.requestAuthorization { status in
                once.resume(returning: status)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                once.resume(returning: nil)
            }
        }
    }

    /// 授权回调窗口。真机上授权对话框的回调通常亚秒级返回。
    private static let authorizationDeadline: TimeInterval = 5
    /// 文件识别窗口，与改造前 TTS 兜底同量级，足够完成正常识别。
    private static let recognitionDeadline: TimeInterval = 30

    /// recognitionTask 的返回值晚于其回调闭包创建，需要一个跨闭包共享的持有者，
    /// 让超时分支仍能 cancel 掉未结束的任务。
    private final class RecognitionTaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: SFSpeechRecognitionTask?

        func set(_ task: SFSpeechRecognitionTask?) {
            lock.lock()
            self.task = task
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let pending = task
            lock.unlock()
            pending?.cancel()
        }
    }
}
