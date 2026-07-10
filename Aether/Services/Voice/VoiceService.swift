import Foundation
import Speech
@preconcurrency import AVFoundation

/// 语音服务，封装 SFSpeechRecognizer 语音识别和 AVSpeechSynthesizer 语音合成。@Observable 支持 UI 绑定。
@MainActor
@Observable
final class VoiceService: NSObject {
    /// 是否正在录音
    var isRecording = false
    /// 当前识别结果文本（实时更新）
    var recognizedText = ""

    /// 中文语音识别器
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    /// 识别请求
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    /// 识别任务
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 音频引擎
    private let audioEngine = AVAudioEngine()
    /// 语音合成器
    private let synthesizer: AVSpeechSynthesizer
    /// 朗读完成回调（自然结束或被 stop）
    var onSpeakFinished: (() -> Void)?
    /// 识别结果回调（partial / final 都会触发）
    var onRecognized: ((String) -> Void)?
    /// 是否正在试听音色（独立于主 speak 流程）
    var isPreviewing = false
    /// 标记当前 utterance 是否为试听，用于 didFinish 区分是否触发 onSpeakFinished
    private var isCurrentPreview = false
    /// 用户主动停止标记：stopSpeaking() 置 true，didCancel 据此区分用户切换与系统取消
    private var isUserInitiatedStop = false
    /// 错误消息（如语音不可用降级提示），nil 表示无错误
    var errorMessage: String?
    /// 音色解析缓存（实例级），避免每次朗读都查询系统语音目录阻塞主线程
    private var cachedVoice: AVSpeechSynthesisVoice?
    /// cachedVoice 对应的 voiceIdentifier（nil 表示尚未缓存）
    private var cachedVoiceIdentifier: String?
    /// 识别器可用性检查（测试可注入；默认使用真实 SFSpeechRecognizer）
    internal var recognizerAvailabilityCheck: () -> Bool = {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        return recognizer?.isAvailable ?? false
    }

    /// 初始化合成器和 delegate
    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    /// 请求语音识别权限，返回是否授权
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// 开始录音。流程：1) 检查识别器可用；2) 激活 AVAudioSession（必须在 installTap 之前，
    /// 未激活时 inputNode.outputFormat 返回 sampleRate=0/channelCount=0 无效格式，installTab 会崩
    /// IsFormatSampleRateAndChannelCountValid）；3) 创建识别请求；4) installTap 接收音频；5) 启动 audioEngine。
    func startRecording() throws {
        guard recognizerAvailabilityCheck() else {
            throw NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("语音识别器不可用", comment: "")])
        }
        guard let recognizer = speechRecognizer else {
            throw NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("语音识别器不可用", comment: "")])
        }
        // 1) 激活 AVAudioSession — 必须在取 outputFormat / installTap 之前完成，
        //    否则 inputNode.outputFormat(forBus:0) 会返回 sampleRate=0 / channelCount=0 的无效格式，
        //    导致 installTap 抛出 "IsFormatSampleRateAndChannelCountValid" 崩溃。
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        let inputNode = audioEngine.inputNode
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.recognizedText = text
                    self.onRecognized?(text)
                }
            }
        }
        // 2) 激活 session 后再取 format — 此时 sampleRate / channelCount 已有效
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// 停止录音，释放 audio session
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isRecording = false
        // 释放 audio session，让其它 App 可恢复音频
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// 朗读文本，中断当前朗读。可选传入 TTSConfig 指定音色、语速、音调、音量。
    /// - Parameters:
    ///   - text: 要朗读的文本
    ///   - config: TTS 配置；nil 时使用系统默认 zh-CN、rate=0.5
    func speak(_ text: String, config: TTSConfig? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        isPreviewing = false
        isCurrentPreview = false
        let utterance = AVSpeechUtterance(string: text)
        applyConfig(utterance: utterance, config: config)
        synthesizer.speak(utterance)
    }

    /// 试听音色（独立于主 speak 流程，不影响 onSpeakFinished）。
    /// 用于设置页预览当前配置下的朗读效果。
    /// - Parameters:
    ///   - text: 要朗读的示例文本
    ///   - config: TTS 配置
    func previewVoice(_ text: String, config: TTSConfig) {
        synthesizer.stopSpeaking(at: .immediate)
        isPreviewing = true
        isCurrentPreview = true
        let utterance = AVSpeechUtterance(string: text)
        applyConfig(utterance: utterance, config: config)
        synthesizer.speak(utterance)
    }

    /// 停止试听
    func stopPreview() {
        if isPreviewing {
            synthesizer.stopSpeaking(at: .immediate)
            isPreviewing = false
            isCurrentPreview = false
        }
    }

    /// 停止朗读
    func stopSpeaking() {
        isUserInitiatedStop = true
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 将 TTSConfig 应用到 AVSpeechUtterance。
    /// voiceIdentifier 非空时优先用该 identifier 加载音色，失败回退 zh-CN；
    /// rate / pitchMultiplier / volume 做 range clamp 保证安全。
    private func applyConfig(utterance: AVSpeechUtterance, config: TTSConfig?) {
        let cfg = config ?? .defaultValue
        // 解析音色（带实例级缓存，避免重复查询系统语音目录）
        utterance.voice = resolveVoice(for: cfg.voiceIdentifier)
        // 应用语速（0...1）
        utterance.rate = Float(max(0, min(1, cfg.rate)))
        // 应用音调（0.5...2.0）
        utterance.pitchMultiplier = Float(max(0.5, min(2.0, cfg.pitchMultiplier)))
        // 应用音量（0...1）
        utterance.volume = max(0, min(1, cfg.volume))
    }

    /// 根据 voiceIdentifier 解析音色，命中缓存时直接复用，避免每次朗读都调用
    /// AVSpeechSynthesisVoice(language:) / TTSVoiceCatalog.voice(for:) 阻塞主线程。
    /// - identifier 非空且 catalog 命中：用 catalog voice
    /// - identifier 为空或 catalog 未命中：回退 zh-CN（macOS 未安装时返回 nil 并设置 errorMessage）
    /// - identifier 为空时以空字符串作为缓存 key
    private func resolveVoice(for identifier: String) -> AVSpeechSynthesisVoice? {
        // 命中缓存（含 nil 缓存）：identifier 一致即复用，跳过系统语音目录查询
        if identifier == cachedVoiceIdentifier {
            return cachedVoice
        }
        // 解析新 voice（与原 applyConfig 逻辑一致）
        let resolved: AVSpeechSynthesisVoice?
        if !identifier.isEmpty,
           let voice = TTSVoiceCatalog.voice(for: identifier) {
            resolved = voice
        } else {
            // macOS 上未安装 zh-CN 语音时 AVSpeechSynthesisVoice(language:) 可能返回 nil
            resolved = AVSpeechSynthesisVoice(language: "zh-CN")
            if resolved == nil {
                errorMessage = NSLocalizedString("未找到中文语音，使用默认语音", comment: "")
            }
        }
        cachedVoice = resolved
        cachedVoiceIdentifier = identifier
        return resolved
    }

    /// 释放音频资源
    deinit {
        // Day 10: 释放音频资源，避免后台音频残留
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        synthesizer.delegate = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

}

// MARK: - AVSpeechSynthesizerDelegate

@MainActor
extension VoiceService: @preconcurrency AVSpeechSynthesizerDelegate {
    /// 自然结束才触发 onSpeakFinished。试听结束不触发回调。
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // 试听结束：仅清理 isPreviewing，不触发主流程回调
            if self.isCurrentPreview {
                self.isPreviewing = false
                self.isCurrentPreview = false
                return
            }
            // 主朗读自然结束才触发回调
            self.onSpeakFinished?()
        }
    }

    /// 区分用户主动停止与系统取消：
    /// - 用户主动停止（stopSpeaking 触发）：不触发 onSpeakFinished，toggleSpeak 已同步清理 speakingMessageId
    /// - 系统取消（音频被抢占/voice 不可用）：兜底触发 onSpeakFinished 清理 speakingMessageId，避免按钮卡红
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let wasPreview = self.isCurrentPreview
            // 取消试听：清理试听状态
            if wasPreview {
                self.isPreviewing = false
                self.isCurrentPreview = false
            }
            // 系统取消（非用户主动停止且非试听）：兜底触发 onSpeakFinished 清理 speakingMessageId
            if !self.isUserInitiatedStop && !wasPreview {
                self.onSpeakFinished?()
            }
            // 回调结束后重置标志，避免影响下一次
            self.isUserInitiatedStop = false
        }
    }
}
