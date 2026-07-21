import Foundation
import AetherServices

/// P2-6 Task 1: VoiceCoordinator —— 语音协调器
///
/// 从 ChatViewModel 抽取的 STT 启停 + TTS 朗读切换 + 朗读完成回调职责。
/// 通过构造器注入 `VoiceService`，通过闭包回调更新 ChatViewModel 的 @Observable 属性
/// （isRecording / speakingMessageId / inputText / errorMessage），不直接持有 @Observable 属性。
///
/// 并发边界：本类标注 `@MainActor`，所有闭包在主 actor 上调用；
/// `voiceService.onSpeakFinished` / `voiceService.onRecognized` 在 init 中注册到本类内部，
/// 闭包使用 [weak self] 防止循环引用。
@MainActor
final class VoiceCoordinator: Coordinator {
    /// 语音服务（STT + TTS），由 ChatViewModel 注入，与 SettingsView 共享同一实例
    private let voiceService: VoiceService
    /// TTS 配置提供者（ChatViewModel 持有 ttsConfig @Observable 属性，通过闭包动态读取）
    private let ttsConfigProvider: () -> TTSConfig
    /// isRecording 状态查询闭包（读取 ChatViewModel 的 @Observable var isRecording 当前值）
    /// 用于判断当前是否处于录音状态，决定 toggleVoiceInput 走停止分支还是启动分支
    private let isRecordingProvider: () -> Bool
    /// isRecording 变更回调（ChatViewModel 设置，更新 @Observable var isRecording）
    private let onIsRecordingChange: (Bool) -> Void
    /// speakingMessageId 变更回调（ChatViewModel 设置，更新 @Observable var speakingMessageId）
    private let onSpeakingMessageIdChange: (UUID?) -> Void
    /// inputText 变更回调（ChatViewModel 设置，更新 @Observable var inputText）
    private let onInputTextChange: (String) -> Void
    /// errorMessage 变更回调（ChatViewModel 设置，更新 @Observable var errorMessage）
    private let onErrorMessageChange: (String?) -> Void
    /// 当前正在朗读的消息 ID（内部状态，用于判断切换/停止）
    private var speakingMessageId: UUID?

    /// 构造器
    /// - Parameters:
    ///   - voiceService: 语音服务实例（与 SettingsView 共享）
    ///   - ttsConfigProvider: TTS 配置提供者，每次 toggleSpeak 时动态读取最新配置
    ///   - isRecordingProvider: isRecording 当前值查询闭包（@MainActor）
    ///   - onIsRecordingChange: isRecording 变更回调（@MainActor）
    ///   - onSpeakingMessageIdChange: speakingMessageId 变更回调（@MainActor）
    ///   - onInputTextChange: inputText 变更回调（@MainActor）
    ///   - onErrorMessageChange: errorMessage 变更回调（@MainActor）
    init(voiceService: VoiceService,
         ttsConfigProvider: @escaping () -> TTSConfig,
         isRecordingProvider: @escaping () -> Bool,
         onIsRecordingChange: @escaping (Bool) -> Void,
         onSpeakingMessageIdChange: @escaping (UUID?) -> Void,
         onInputTextChange: @escaping (String) -> Void,
         onErrorMessageChange: @escaping (String?) -> Void) {
        self.voiceService = voiceService
        self.ttsConfigProvider = ttsConfigProvider
        self.isRecordingProvider = isRecordingProvider
        self.onIsRecordingChange = onIsRecordingChange
        self.onSpeakingMessageIdChange = onSpeakingMessageIdChange
        self.onInputTextChange = onInputTextChange
        self.onErrorMessageChange = onErrorMessageChange

        // Day 5: 朗读完成时清空 speakingMessageId，避免按钮状态卡住
        voiceService.onSpeakFinished = { [weak self] in
            guard let self = self else { return }
            self.speakingMessageId = nil
            self.onSpeakingMessageIdChange(nil)
        }
        // STT 识别结果实时写入 inputText
        voiceService.onRecognized = { [weak self] text in
            self?.onInputTextChange(text)
        }
    }

    /// 切换语音输入。首次调用会请求权限，授权后开始/停止录音；识别结果实时写入 inputText。
    /// 行为等价于 ChatViewModel 原始 toggleVoiceInput 实现。
    func toggleVoiceInput() {
        if isRecordingProvider() {
            voiceService.stopRecording()
            onIsRecordingChange(false)
            return
        }
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.voiceService.requestPermission()
            guard granted else {
                self.onErrorMessageChange(NSLocalizedString("需要语音识别权限", comment: ""))
                return
            }
            // 开始录音前清空输入框与上一次识别结果
            self.onInputTextChange("")
            self.voiceService.recognizedText = ""
            do {
                try self.voiceService.startRecording()
                self.onIsRecordingChange(self.voiceService.isRecording)
            } catch {
                // 录音启动失败（如音频会话激活失败 / 识别器不可用）：避免按钮卡住
                self.onIsRecordingChange(false)
                self.onErrorMessageChange(String(format: NSLocalizedString("录音启动失败: %@", comment: ""), error.localizedDescription))
            }
        }
    }

    /// 切换语音朗读。点击同一条消息则停止；点击另一条则切换。
    /// 行为等价于 ChatViewModel 原始 toggleSpeak 实现。
    /// - Parameters:
    ///   - messageId: 待朗读的消息 ID
    ///   - content: 待朗读的文本内容
    func toggleSpeak(messageId: UUID, content: String) {
        if speakingMessageId == messageId {
            voiceService.stopSpeaking()
            speakingMessageId = nil
            onSpeakingMessageIdChange(nil)
            return
        }
        // 切换到新消息朗读（stopSpeaking 会触发 didCancel → onSpeakFinished，但这里同步设置避免状态抖动）
        voiceService.stopSpeaking()
        speakingMessageId = messageId
        onSpeakingMessageIdChange(messageId)
        voiceService.speak(content, config: ttsConfigProvider())
    }
}
