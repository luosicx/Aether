#if os(macOS)
import CoreAudio
#endif
import Foundation
#if canImport(os)
import os
#endif
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
    /// 是否已在 inputNode 上安装 tap（决定 stopRecording / deinit 是否需要移除）
    private var isInputTapInstalled = false
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

    /// 语音识别授权回调窗口，与 ReminderTool / AlarmTool / ContactsTool 的授权窗口同量级。
    nonisolated private static let authorizationDeadline: TimeInterval = 5

    /// 请求语音识别权限，返回是否授权。
    /// `SFSpeechRecognizer.requestAuthorization` 的回调在无法应答系统弹窗的运行环境
    /// （模拟器、无头 CI）里可能永不触发，无界 await 会把「点击语音输入」整条链路挂死，
    /// 因此超时按未授权收尾，由调用方走权限提示分支。
    func requestPermission() async -> Bool {
        let deadline = Self.authorizationDeadline
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnceContinuation(continuation)
            SFSpeechRecognizer.requestAuthorization { status in
                once.resume(returning: status == .authorized)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
                once.resume(returning: false)
            }
        }
    }

    /// 开始录音。流程：1) 熔断位与识别器可用性检查；2) 激活 AVAudioSession（必须在 installTap 之前，
    /// 未激活时 inputNode.outputFormat 返回 sampleRate=0/channelCount=0 无效格式，installTab 会崩
    /// IsFormatSampleRateAndChannelCountValid）；3) 创建识别请求；4) 输入设备检查 + installTap +
    /// 启动 audioEngine。其中 4)（含设备属性查询、取 inputNode 与创建识别任务）整段排在音频工作
    /// 队列上有界执行，见 runBoundedAudioWork。
    func startRecording() throws {
        // 0) 熔断位先看：绑不上的机器再试一次还是绑不上，但每试一次都要主线程陪等满窗口、
        //    再留下一条钉死在 CoreAudio 里的线程。这里连 CoreAudio 属性查询都不做。
        //    设备检查本身也移进队列了——`AudioObjectGetPropertyData` 同样是同步向 CoreAudio 取数，
        //    留在主线程等于把刚拆掉的挂点换个位置留着。
        guard !Self.isAudioSubsystemStalled else {
            throw NSError(domain: "VoiceService", code: -5, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("音频子系统未响应", comment: "")])
        }
        guard recognizerAvailabilityCheck() else {
            throw NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("语音识别器不可用", comment: "")])
        }
        guard let recognizer = speechRecognizer else {
            throw NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("语音识别器不可用", comment: "")])
        }
        // 1) 激活 AVAudioSession — 必须在取 outputFormat / installTap 之前完成，
        //    否则 inputNode.outputFormat(forBus:0) 会返回 sampleRate=0 / channelCount=0 的无效格式，
        //    导致 installTap 抛出 "IsFormatSampleRateAndChannelCountValid" 崩溃。激活成功只是必要
        //    条件，不充分 —— 见下面第 2 步的格式判定。
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        // 2)~5) 从设备检查到 engine.start() 整段排在音频工作队列上有界执行（见 runBoundedAudioWork）。
        let carrier = VoiceAudioSetupCarrier(engine: audioEngine, recognizer: recognizer,
                                             request: request, sink: VoiceRecognitionSink(service: self))
        let outcome = Self.runBoundedAudioWork(deadline: Self.audioSetupDeadline) {
            Self.performAudioSetup(carrier: carrier)
        }
        switch outcome {
        case .ok:
            // 信号量已经建好 happens-before，这里读 carrier.task 才是安全的
            recognitionTask = carrier.task
            isInputTapInstalled = true
            isRecording = true
        case .noInputDevice:
            // 走到这里说明属性查询答得出来，只是这台机器没有可用输入流；与"绑不上"是两种结局。
            throw NSError(domain: "VoiceService", code: -3, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("未检测到音频输入设备", comment: "")])
        case .invalidFormat:
            recognitionTask = carrier.task
            recognitionTask?.cancel()
            recognitionTask = nil
            throw NSError(domain: "VoiceService", code: -4, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("音频输入格式无效", comment: "")])
        case .startFailed(let reason):
            recognitionTask = carrier.task
            recognitionTask?.cancel()
            recognitionTask = nil
            throw NSError(domain: "VoiceService", code: -6, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("音频引擎启动失败: %@", comment: ""), reason)])
        case .stalled:
            // 熔断位已由 runBoundedAudioWork 置起，后续再点麦克风直接走这条快速失败分支。
            // 既不读也不 cancel carrier.task：那条线程还在写它，主线程读同一个强引用变量就是
            // 并发读写；cancel 也不安全，被弃用的线程稍后仍可能把 tap 装上并往 request 里灌缓冲。
            // 那次识别任务连同引擎若真跑起来，由排在同一条队列上的拆除流程收尾。
            throw NSError(domain: "VoiceService", code: -5, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("音频子系统未响应", comment: "")])
        }
    }

    /// 音频启动序列的有界窗口，与 `authorizationDeadline` 取同一量级。
    nonisolated private static let audioSetupDeadline: TimeInterval = 5

    /// 全进程共用的一条音频工作队列。
    /// 每次动作各开一条的话，一台绑不上的机器上就会每按一次麦克风多钉住一条线程；实测被拖住的
    /// 不是"那一次录音"而是整个音频子系统——#65 第二轮 CI 里连不碰输入设备的 TTS 用例
    /// （testDidCancelDuringPreviewCleansPreviewState）都报 `Stall on main thread`。
    /// 串行队列把"最多一条线程可能被钉住"变成硬上界，配合 `audioStalled` 熔断位让第二次之后
    /// 根本不再往里派活。
    nonisolated private static let audioWorkQueue = DispatchQueue(label: "com.aether.voice.audiowork")

    /// 熔断位：某次有界窗口到期即置位，本进程之后不再触碰音频引擎。
    /// 绑不上一次的机器再试一次还是绑不上，但每试一次都要主线程陪等 5 秒、多留一条钉死的线程。
    nonisolated private static let audioStalled = OSAllocatedUnfairLock(initialState: false)

    /// 熔断位当前值（internal 给单测断言用）。
    internal nonisolated static var isAudioSubsystemStalled: Bool { audioStalled.withLock { $0 } }

    /// 复位熔断位（internal 给单测用：每个用例开始时清掉，避免有界窗口的注入用例污染同类后面的
    /// 录音用例——这是进程级状态，测试必须显式归还）。
    internal nonisolated static func resetAudioSubsystemStall() { audioStalled.withLock { $0 = false } }

    /// 在音频工作队列上跑 `body`，最多等 `deadline` 秒；窗口到期置熔断位并返回 `.stalled`。
    /// `AVAudioEngine.inputNode` / `outputFormat(forBus:)` / `installTap` / `prepare` / `start()`
    /// 与 `SFSpeechRecognizer.recognitionTask(with:)` 都是同步向 CoreAudio / Assistant 守护进程
    /// 发请求的调用，在输入设备存在却绑不上的机器上可能永不返回（CI 栈停在
    /// `BindToDeviceInternal → mach_msg`，控制台同时打 `AddInstanceForFactory: No factory registered`）。
    /// 本类是 @MainActor，一次永不返回就把主线程永久钉住：用户点麦克风后 UI 再也回不来，
    /// 测试里则整条用例只能等 xcodebuild 的 60 秒 allowance 把它打死。
    /// `hasAudioInputDevice()` 只挡得住「一个输入设备都没有」，挡不住「设备存在但绑不上」，
    /// 所以这里做有界等待而不是继续加设备判定。被弃用的线程无法解绑，是这次取舍的代价，
    /// 由"共用一条队列 + 熔断位"把代价封顶。
    /// internal 是给单测留的口：用一个 sleep 远超窗口的 body 就能在本地证明它按时返回、并按时置位。
    internal nonisolated static func runBoundedAudioWork(
        deadline: TimeInterval,
        _ body: @escaping @Sendable () -> VoiceAudioSetupOutcome
    ) -> VoiceAudioSetupOutcome {
        let done = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock(initialState: VoiceAudioSetupOutcome.ok)
        audioWorkQueue.async {
            box.withLock { $0 = body() }
            done.signal()
        }
        guard done.wait(timeout: .now() + deadline) == .success else {
            audioStalled.withLock { $0 = true }
            return .stalled
        }
        return box.withLock { $0 }
    }

    /// 专用队列上执行的启动序列本体；跨线程只传 Sendable 结局，识别任务留在 carrier 里交接。
    nonisolated private static func performAudioSetup(carrier: VoiceAudioSetupCarrier) -> VoiceAudioSetupOutcome {
        // 输入设备前置检查放在这里而不是调用方：`AudioObjectGetPropertyData` 同样是同步向
        // CoreAudio 取数，留在主线程上就等于把刚拆掉的挂点换个位置留着。
        #if os(macOS)
        guard hasAudioInputDevice() else { return .noInputDevice }
        #endif
        let inputNode = carrier.engine.inputNode
        carrier.task = carrier.recognizer.recognitionTask(with: carrier.request) { result, _ in
            carrier.sink.handle(result)
        }
        // 模拟器上 setActive 可能成功而输入格式仍是 sampleRate=0 / channelCount=0，
        // 这种格式交给 installTap 会撞上 IsFormatSampleRateAndChannelCountValid 断言、整个进程被打死
        // （真机上麦克风被占用/无权限时同样可能拿到无效格式）。先判掉。
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            carrier.task?.cancel()
            return .invalidFormat
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            carrier.request.append(buffer)
        }
        carrier.engine.prepare()
        do {
            try carrier.engine.start()
        } catch {
            // tap 已经装上、引擎却没跑起来：在这里就地拆掉。回到主线程再拆要走
            // isInputTapInstalled 标记，而这条分支接下来就抛错、调用方只会去 stopRecording，
            // 那时标记为 false 就会把 tap 永久留在 inputNode 上。
            inputNode.removeTap(onBus: 0)
            return .startFailed(reason: error.localizedDescription)
        }
        return .ok
    }

    /// 停止录音，释放 audio session。
    /// 引擎侧的拆除排在音频工作队列上做、调用方不等：`isRunning` / `stop()` / `inputNode` 都是同步向
    /// CoreAudio 取设备状态的调用，在设备存在却绑不上的机器上永不返回。留在主线程时，
    /// 「点击停止录音」和 deinit 的清理都会把主线程钉住——#65 第二轮 CI 的
    /// testDeinitAsyncCleanupAfterRecordingAttempt 挂满 60 秒就挂在这段（启动序列那时已被有界窗口
    /// 护住，窗口本身不可能吃掉 60 秒）。不等就不需要窗口：可能钉死的只有那一条工作队列，
    /// 而熔断位已经保证第二次之后不再往里派活。
    func stopRecording() {
        let needRemoveTap = isInputTapInstalled
        isInputTapInstalled = false
        isRecording = false
        let box = VoiceAudioTeardownBox(engine: audioEngine, request: recognitionRequest,
                                       task: recognitionTask, removeTap: needRemoveTap)
        recognitionRequest = nil
        recognitionTask = nil
        Self.audioWorkQueue.async { box.run() }
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

    /// 释放音频资源。
    /// 引擎侧的拆除排在音频工作队列上，和 stopRecording 同一条串行队列——不会与启动序列并发碰同一个
    /// AVAudioEngine。`isRunning == true` 只可能来自 startRecording 成功，那次一定先 installTap 过，
    /// 所以拆除序列里的"running 就 removeTap"不需要额外的状态标记。
    /// AVAudioEngine 的 deinit 可能非主线程触发，而 deinit 是非 isolated 上下文：这里只读 let 属性，
    /// 识别请求/识别任务这两个 var 留给 stopRecording（deinit 阶段读它们既是数据竞争，也已经在
    /// stopRecording 里 nil 掉）。
    /// synthesizer.delegate 的清理仍在主 actor 上做——它只是断开引用，不向守护进程发请求。
    deinit {
        let audioEngine = self.audioEngine
        let synthesizer = self.synthesizer
        let box = VoiceAudioTeardownBox(engine: audioEngine, request: nil, task: nil, removeTap: false)
        Self.audioWorkQueue.async { box.run() }
        Task { @MainActor [synthesizer] in
            synthesizer.delegate = nil
        }
    }

    #if os(macOS)
    /// 系统当前是否有可用的默认音频输入设备（且该设备带输入流）。
    /// `AVAudioEngine.inputNode` / `start()` 在没有输入设备的机器上会进入 CoreAudio 的
    /// 设备绑定流程并一直等下去（CI 上栈停在 `BindToDeviceInternal → mach_msg`），线程被卡死后
    /// 该线程上的所有后续用例只能超时。这里只用 CoreAudio 的属性查询（同步、不启动 I/O）
    /// 做前置判断，无设备时直接抛错，让调用方走「录音启动失败」分支。
    nonisolated private static func hasAudioInputDevice() -> Bool {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return false
        }
        // 设备存在还要有输入流：无头机器上可能残留一个没有任何流的聚合设备。
        var streamSize: UInt32 = 0
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr else {
            return false
        }
        return streamSize > 0
    }
    #endif

}

// MARK: - 音频启动序列的跨线程载体

/// 启动序列的五种结局。只带 Sendable 值，便于跨线程交接。
internal enum VoiceAudioSetupOutcome: Sendable {
    case ok
    /// 有界窗口到期，body 仍未返回——那条线程只能弃用，同时置起进程级熔断位
    case stalled
    /// 这台机器没有带输入流的默认输入设备（CoreAudio 属性查询本身是答得出来的）
    case noInputDevice
    /// 输入格式 sampleRate / channelCount 为 0，installTap 会撞 CoreAudio 断言
    case invalidFormat
    /// engine.start() 抛错，带原始描述
    case startFailed(reason: String)
}

/// AVAudioEngine / SFSpeechRecognizer / 识别请求都不是 Sendable，但启动期间它们只被这一条专用线程
/// 使用，主线程只在信号量上等待，交接点有 happens-before，故用 @unchecked Sendable 过编译。
private final class VoiceAudioSetupCarrier {
    let engine: AVAudioEngine
    let recognizer: SFSpeechRecognizer
    let request: SFSpeechAudioBufferRecognitionRequest
    let sink: VoiceRecognitionSink
    var task: SFSpeechRecognitionTask?

    init(engine: AVAudioEngine, recognizer: SFSpeechRecognizer,
         request: SFSpeechAudioBufferRecognitionRequest, sink: VoiceRecognitionSink) {
        self.engine = engine
        self.recognizer = recognizer
        self.request = request
        self.sink = sink
    }
}

extension VoiceAudioSetupCarrier: @unchecked Sendable {}

/// 拆除序列的持有者。AVAudioEngine / 识别请求 / 识别任务都不是 Sendable，但拆除期间只有音频工作队列
/// 这一条线程碰它们，启动序列也排在同一条队列上，两者天然串行，故用 @unchecked Sendable 过编译。
/// 顺序沿用改动前的 stopRecording：先停引擎（不再往 request 里灌缓冲），再 endAudio / cancel。
private final class VoiceAudioTeardownBox {
    let engine: AVAudioEngine
    let request: SFSpeechAudioBufferRecognitionRequest?
    let task: SFSpeechRecognitionTask?
    /// 调用方确知装过 tap 时传 true；deinit 拿不到这个状态，靠 wasRunning 兜住
    /// （isRunning == true 只可能来自装过 tap 的那次成功启动）。
    let removeTap: Bool

    init(engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest?,
         task: SFSpeechRecognitionTask?, removeTap: Bool) {
        self.engine = engine
        self.request = request
        self.task = task
        self.removeTap = removeTap
    }

    func run() {
        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }
        if removeTap || wasRunning {
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        // 释放 audio session，让其它 App 可恢复音频
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

extension VoiceAudioTeardownBox: @unchecked Sendable {}

/// 把识别结果送回 @MainActor 的持有者；weak 以免 deinit 前被闭包延长生命周期。
private final class VoiceRecognitionSink {
    weak var service: VoiceService?

    init(service: VoiceService) {
        self.service = service
    }

    func handle(_ result: SFSpeechRecognitionResult?) {
        guard let text = result?.bestTranscription.formattedString else { return }
        Task { @MainActor [weak service] in
            guard let service = service else { return }
            service.recognizedText = text
            service.onRecognized?(text)
        }
    }
}

extension VoiceRecognitionSink: @unchecked Sendable {}

// MARK: - AVSpeechSynthesizerDelegate

@MainActor
extension VoiceService: @preconcurrency AVSpeechSynthesizerDelegate {
    /// 自然结束才触发 onSpeakFinished。试听结束不触发回调。
    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
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
    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
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
