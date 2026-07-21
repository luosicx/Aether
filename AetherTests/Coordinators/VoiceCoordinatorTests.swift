import XCTest
@testable import Aether

/// P2-6 Task 1: VoiceCoordinator 单元测试
///
/// 验证 VoiceCoordinator 正确封装 STT 启停、TTS 朗读切换与朗读完成回调，
/// 通过闭包回调更新外部状态，不直接持有 @Observable 属性。
@MainActor
final class VoiceCoordinatorTests: XCTestCase {

    // MARK: - 辅助

    /// VoiceCoordinator 测试夹具：构造 coordinator 同时持有闭包回调写入的 Box，便于断言。
    /// 使用 struct 而非多元组返回，避免触发 SwiftLint large_tuple（warning 阈值 4）。
    private struct VoiceFixture {
        let coordinator: VoiceCoordinator
        let isRecording: NonIsolatedBox<Bool>
        let speakingMessageId: NonIsolatedBox<UUID?>
        let inputText: NonIsolatedBox<String>
        let errorMessage: NonIsolatedBox<String?>
    }

    /// 构造一个 VoiceCoordinator 并捕获闭包回调值，便于断言。
    /// isRecordingProvider 默认从 isRecordingBox 读取，模拟 ChatViewModel 的 @Observable var isRecording。
    private func makeCoordinator(
        voiceService: VoiceService = VoiceService(),
        ttsConfig: TTSConfig = .defaultValue
    ) -> VoiceFixture {
        let isRecordingBox = NonIsolatedBox<Bool>(false)
        let speakingBox = NonIsolatedBox<UUID?>(nil)
        let inputTextBox = NonIsolatedBox<String>("")
        let errorBox = NonIsolatedBox<String?>(nil)
        let coordinator = VoiceCoordinator(
            voiceService: voiceService,
            ttsConfigProvider: { ttsConfig },
            isRecordingProvider: { isRecordingBox.value },
            onIsRecordingChange: { isRecordingBox.value = $0 },
            onSpeakingMessageIdChange: { speakingBox.value = $0 },
            onInputTextChange: { inputTextBox.value = $0 },
            onErrorMessageChange: { errorBox.value = $0 }
        )
        return VoiceFixture(
            coordinator: coordinator,
            isRecording: isRecordingBox,
            speakingMessageId: speakingBox,
            inputText: inputTextBox,
            errorMessage: errorBox
        )
    }

    // MARK: - toggleVoiceInput

    /// toggleVoiceInput 在未录音时调用应启动录音并触发 onIsRecordingChange(true)。
    /// 模拟器环境下 SFSpeechRecognizer.requestAuthorization 永不返回，跳过；
    /// 真机音频会话不可用时跳过（errorMessage 被设置）。
    func testToggleVoiceInputStartsRecording() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
            "跳过：模拟器环境下 SFSpeechRecognizer.requestAuthorization 永不返回"
        )
        let voiceService = VoiceService()
        voiceService.recognizerAvailabilityCheck = { true }
        let fx = makeCoordinator(voiceService: voiceService)

        fx.coordinator.toggleVoiceInput()

        // 轮询等待异步 Task 完成：成功时 isRecording=true，失败时 errorMessage 被设置
        for _ in 0..<50 {
            if fx.isRecording.value == true || fx.errorMessage.value != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        if let err = fx.errorMessage.value {
            throw XCTSkip("音频会话不可用，跳过录音启动测试：\(err)")
        }
        XCTAssertEqual(fx.isRecording.value, true,
                       "toggleVoiceInput 应启动录音并通过 onIsRecordingChange 通知 true")
    }

    /// toggleVoiceInput 在录音中时再次调用应停止录音并触发 onIsRecordingChange(false)。
    /// 不依赖真实音频会话：直接预置 isRecordingBox.value=true（模拟 ChatViewModel.isRecording=true），
    /// toggleVoiceInput 通过 isRecordingProvider 闭包读取该值，走停止分支。
    func testToggleVoiceInputStopsRecording() {
        let voiceService = VoiceService()
        let fx = makeCoordinator(voiceService: voiceService)
        // 预置录音状态为 true（模拟 ChatViewModel.isRecording=true）
        fx.isRecording.value = true

        fx.coordinator.toggleVoiceInput()

        XCTAssertEqual(fx.isRecording.value, false,
                       "录音中再次 toggle 应停止并通过 onIsRecordingChange 通知 false")
    }

    /// toggleVoiceInput 在识别器不可用时应设置 errorMessage 且不进入录音状态。
    /// 模拟器环境下 SFSpeechRecognizer.requestAuthorization 永不返回，跳过。
    func testToggleVoiceInputWhenUnavailableSetsError() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
            "跳过：模拟器环境下 SFSpeechRecognizer.requestAuthorization 永不返回"
        )
        let voiceService = VoiceService()
        voiceService.recognizerAvailabilityCheck = { false }
        let fx = makeCoordinator(voiceService: voiceService)

        fx.coordinator.toggleVoiceInput()

        // 轮询等待异步 Task 完成（requestPermission + startRecording 抛错路径）
        for _ in 0..<50 {
            if fx.errorMessage.value != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        XCTAssertNotNil(fx.errorMessage.value, "识别器不可用时应通过 onErrorMessageChange 通知错误")
        XCTAssertEqual(fx.isRecording.value, false,
                       "不可用时 isRecording 应保持 false")
    }

    // MARK: - toggleSpeak

    /// toggleSpeak 同 id 第二次调用应停止朗读并通过 onSpeakingMessageIdChange(nil) 清空
    func testToggleSpeakSameIdStops() {
        let fx = makeCoordinator()
        let id = UUID()

        fx.coordinator.toggleSpeak(messageId: id, content: "hello")
        XCTAssertEqual(fx.speakingMessageId.value, id,
                       "首次 toggleSpeak 应通过 onSpeakingMessageIdChange 通知 id")

        fx.coordinator.toggleSpeak(messageId: id, content: "hello")
        XCTAssertNil(fx.speakingMessageId.value,
                     "同 id 第二次 toggleSpeak 应停止并通知 nil")
    }

    /// toggleSpeak 不同 id 调用应切换 speakingMessageId
    func testToggleSpeakDifferentIdSwitches() {
        let fx = makeCoordinator()
        let id1 = UUID()
        let id2 = UUID()

        fx.coordinator.toggleSpeak(messageId: id1, content: "hello")
        XCTAssertEqual(fx.speakingMessageId.value, id1,
                       "首次 toggleSpeak 应通知 id1")

        fx.coordinator.toggleSpeak(messageId: id2, content: "world")
        XCTAssertEqual(fx.speakingMessageId.value, id2,
                       "切换到不同 id 应通知 id2")
    }

    // MARK: - voiceService 回调注册

    /// voiceService.onSpeakFinished 触发时应清空 speakingMessageId（验证 VoiceCoordinator 在 init 中注册回调）
    func testOnSpeakFinishedClearsSpeakingMessageId() {
        let voiceService = VoiceService()
        let fx = makeCoordinator(voiceService: voiceService)
        let id = UUID()

        fx.coordinator.toggleSpeak(messageId: id, content: "hello")
        XCTAssertEqual(fx.speakingMessageId.value, id, "前置：toggleSpeak 应设置 speakingMessageId")

        voiceService.onSpeakFinished?()

        XCTAssertNil(fx.speakingMessageId.value,
                     "onSpeakFinished 应通过 onSpeakingMessageIdChange 通知 nil")
    }

    /// voiceService.onRecognized 触发时应通过 onInputTextChange 更新 inputText（验证回调注册）
    func testOnRecognizedUpdatesInputText() {
        let voiceService = VoiceService()
        let fx = makeCoordinator(voiceService: voiceService)

        voiceService.onRecognized?("识别结果文本")

        XCTAssertEqual(fx.inputText.value, "识别结果文本",
                       "onRecognized 应通过 onInputTextChange 通知识别结果")
    }
}

/// 非 actor 隔离的值容器，便于测试闭包回调捕获的值。
/// VoiceCoordinator 的闭包在 @MainActor 上下文中调用，写入此 Box 安全。
final class NonIsolatedBox<T>: @unchecked Sendable {
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { _value }
        set { _value = newValue }
    }
}
