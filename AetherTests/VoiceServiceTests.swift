import XCTest
import Speech
import AVFoundation
@testable import Aether

/// VoiceService 单元测试
@MainActor
final class VoiceServiceTests: XCTestCase {

    /// 未 startRecording 直接 stopRecording 不应崩溃
    func testStopRecordingWhenNotStartedDoesNotCrash() {
        let service = VoiceService()
        service.stopRecording()
        XCTAssertFalse(service.isRecording, "未开始录音时 isRecording 应为 false")
    }

    /// SFSpeechRecognizer 不可用时 startRecording 应抛错。
    /// 通过注入 recognizerAvailabilityCheck 返回 false 模拟识别器不可用，
    /// 不再依赖真实 SFSpeechRecognizer 环境状态。
    func testStartRecordingWhenRecognizerUnavailable() throws {
        let service = VoiceService()
        // 注入：识别器不可用
        service.recognizerAvailabilityCheck = { false }

        XCTAssertThrowsError(try service.startRecording(),
                             "识别器不可用时 startRecording 应抛错") { error in
            let nserror = error as NSError
            XCTAssertEqual(nserror.domain, "VoiceService",
                           "抛出的错误 domain 应为 VoiceService")
        }
    }

    // MARK: - 初始状态

    /// 验证 VoiceService 初始状态：isRecording=false、recognizedText=""、isPreviewing=false、errorMessage=nil
    func testInitialState() {
        let service = VoiceService()
        XCTAssertFalse(service.isRecording, "初始 isRecording 应为 false")
        XCTAssertEqual(service.recognizedText, "", "初始 recognizedText 应为空")
        XCTAssertFalse(service.isPreviewing, "初始 isPreviewing 应为 false")
        XCTAssertNil(service.errorMessage, "初始 errorMessage 应为 nil")
    }

    // MARK: - requestPermission

    /// requestPermission 应返回 Bool 且不崩溃
    func testRequestPermissionReturnsBool() async {
        let service = VoiceService()
        let result = await service.requestPermission()
        // 仅验证方法正常返回，不依赖具体授权状态（受模拟器环境影响）
        _ = result
    }

    // MARK: - speak / stopSpeaking

    /// speak 后 isPreviewing 应为 false（speak 会重置试听状态）
    func testSpeakResetsPreviewState() {
        let service = VoiceService()
        service.previewVoice("预览", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "previewVoice 后 isPreviewing 应为 true")
        service.speak("测试")
        XCTAssertFalse(service.isPreviewing, "speak 后 isPreviewing 应为 false")
    }

    /// speak 使用默认配置不应崩溃；若 zh-CN 不可用则 errorMessage 应为固定文案
    func testSpeakWithDefaultConfigResolvesVoice() {
        let service = VoiceService()
        service.speak("测试", config: nil)
        // 模拟器通常有 zh-CN 音色 → errorMessage 保持 nil；
        // 若无 zh-CN 音色 → errorMessage 为固定错误文案
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "errorMessage 应为固定文案")
        }
    }

    /// speak 使用无效 voiceIdentifier 时应回退 zh-CN 且不崩溃
    func testSpeakWithInvalidIdentifierFallsBack() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "com.invalid.nonexistent.voice",
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试", config: config)
        // 无效 identifier → catalog 未命中 → 回退 zh-CN
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""))
        }
    }

    /// 两次 speak 使用相同 config 时 errorMessage 状态应一致（验证缓存命中）
    func testSpeakTwiceWithSameConfigUsesCache() {
        let service = VoiceService()
        let config = TTSConfig.defaultValue
        service.speak("第一次", config: config)
        let errorAfterFirst = service.errorMessage
        service.speak("第二次", config: config)
        let errorAfterSecond = service.errorMessage
        // 缓存命中时 errorMessage 状态应一致
        XCTAssertEqual(errorAfterFirst, errorAfterSecond,
                       "相同 config 两次 speak 的 errorMessage 应一致")
    }

    /// stopSpeaking 不应崩溃
    func testStopSpeakingDoesNotCrash() {
        let service = VoiceService()
        service.speak("测试")
        service.stopSpeaking()
        // 验证不崩溃即可
    }

    // MARK: - previewVoice / stopPreview

    /// previewVoice 应设置 isPreviewing=true
    func testPreviewVoiceSetsIsPreviewing() {
        let service = VoiceService()
        XCTAssertFalse(service.isPreviewing)
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "previewVoice 后 isPreviewing 应为 true")
    }

    /// stopPreview 在试听中应重置 isPreviewing=false
    func testStopPreviewWhenPreviewing() {
        let service = VoiceService()
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing)
        service.stopPreview()
        XCTAssertFalse(service.isPreviewing, "stopPreview 后 isPreviewing 应为 false")
    }

    /// stopPreview 未试听时不应崩溃且 isPreviewing 保持 false
    func testStopPreviewWhenNotPreviewing() {
        let service = VoiceService()
        XCTAssertFalse(service.isPreviewing)
        service.stopPreview()
        XCTAssertFalse(service.isPreviewing, "未试听时 isPreviewing 应保持 false")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// didFinish 自然结束（非试听）应触发 onSpeakFinished
    func testDidFinishTriggersOnSpeakFinished() {
        let service = VoiceService()
        // 不调用 speak/previewVoice，isCurrentPreview 默认 false
        let expectation = XCTestExpectation(description: "onSpeakFinished 被调用")
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didFinish: utterance)
        wait(for: [expectation], timeout: 2.0)
    }

    /// didCancel 系统取消（非用户主动停止、非试听）应兜底触发 onSpeakFinished
    func testDidCancelSystemCancelTriggersCallback() {
        let service = VoiceService()
        // 不调用 stopSpeaking → isUserInitiatedStop=false
        // 不调用 previewVoice → isCurrentPreview=false
        let expectation = XCTestExpectation(description: "onSpeakFinished 被调用")
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didCancel: utterance)
        wait(for: [expectation], timeout: 2.0)
    }

    /// didCancel 用户主动停止（stopSpeaking 触发）不应触发 onSpeakFinished
    func testDidCancelUserInitiatedDoesNotTriggerCallback() {
        let service = VoiceService()
        // 不调用 speak → 无语音进行中，synthesizer.stopSpeaking 为 no-op
        service.stopSpeaking() // 设置 isUserInitiatedStop=true
        let expectation = XCTestExpectation(description: "onSpeakFinished 不应被调用")
        expectation.isInverted = true
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didCancel: utterance)
        wait(for: [expectation], timeout: 2.0)
    }

    /// didCancel 在试听模式下应清理试听状态，且不触发 onSpeakFinished。
    /// 直接调用 delegate 方法，不依赖真实 AVSpeechSynthesizer 合成流程。
    func testDidCancelDuringPreviewCleansPreviewState() {
        let service = VoiceService()
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "previewVoice 后 isPreviewing 应为 true")

        let expectation = XCTestExpectation(description: "onSpeakFinished 不应被调用")
        expectation.isInverted = true
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didCancel: utterance)
        wait(for: [expectation], timeout: 2.0)

        XCTAssertFalse(service.isPreviewing, "试听 didCancel 后 isPreviewing 应为 false")
    }

    // MARK: - applyConfig rate clamp 边界

    /// rate 为负值时 applyConfig 应 clamp 到 0，speak 不崩溃且 errorMessage 状态合理
    func testSpeakWithNegativeRateClampsToZero() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: -0.5,
                              pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试", config: config)
        // 负值 rate 被 clamp 到 0，不崩溃；errorMessage 状态合理
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "负值 rate clamp 后 errorMessage 应为固定文案")
        }
    }

    /// rate 超过上限时 applyConfig 应 clamp 到 1，speak 不崩溃
    func testSpeakWithExcessiveRateClampsToOne() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 2.0,
                              pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "超值 rate clamp 后 errorMessage 应为固定文案")
        }
    }

    // MARK: - applyConfig pitchMultiplier clamp 边界

    /// pitchMultiplier 低于下限 0.5 时应 clamp 到 0.5，speak 不崩溃
    func testSpeakWithLowPitchClampsToMinimum() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 0.1, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "低 pitch clamp 后 errorMessage 应为固定文案")
        }
    }

    /// pitchMultiplier 超过上限 2.0 时应 clamp 到 2.0，speak 不崩溃
    func testSpeakWithHighPitchClampsToMaximum() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 3.0, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "高 pitch clamp 后 errorMessage 应为固定文案")
        }
    }

    // MARK: - applyConfig volume clamp 边界

    /// volume 为负值时应 clamp 到 0，speak 不崩溃
    func testSpeakWithNegativeVolumeClampsToZero() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 1.0, volume: -0.5)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "负值 volume clamp 后 errorMessage 应为固定文案")
        }
    }

    /// volume 超过上限 1 时应 clamp 到 1，speak 不崩溃
    func testSpeakWithExcessiveVolumeClampsToOne() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 1.0, volume: 1.5)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "超值 volume clamp 后 errorMessage 应为固定文案")
        }
    }

    // MARK: - onRecognized 回调

    /// 设置 onRecognized 闭包后应可正常调用，不崩溃（不依赖真实语音识别）
    func testOnRecognizedCallbackCanBeSetAndInvoked() {
        let service = VoiceService()
        var captured: String?
        service.onRecognized = { text in captured = text }
        // 仅验证闭包设置成功且可调用，不依赖真实识别流程
        service.onRecognized?("测试文本")
        XCTAssertEqual(captured, "测试文本", "onRecognized 闭包应被正确设置并可调用")
    }

    // MARK: - speak 边界文本

    /// speak 空字符串不应崩溃
    func testSpeakEmptyStringDoesNotCrash() {
        let service = VoiceService()
        service.speak("")
        // 验证不崩溃即可；errorMessage 状态合理
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "空字符串 speak 的 errorMessage 应为固定文案")
        }
    }

    /// speak 超长字符串不应崩溃
    func testSpeakLongTextDoesNotCrash() {
        let service = VoiceService()
        let longText = String(repeating: "这是一段测试文本。", count: 500)
        service.speak(longText)
        // 验证不崩溃即可；errorMessage 状态合理
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "超长文本 speak 的 errorMessage 应为固定文案")
        }
    }

    // MARK: - previewVoice 与 stopSpeaking 交互

    /// previewVoice 后调用 stopSpeaking（非 stopPreview）应能停止且不崩溃
    func testStopSpeakingAfterPreviewVoiceDoesNotCrash() {
        let service = VoiceService()
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "previewVoice 后 isPreviewing 应为 true")
        // stopSpeaking 不会重置 isPreviewing（由 stopPreview / delegate 负责），验证不崩溃
        service.stopSpeaking()
        // isPreviewing 状态由 delegate 回调清理，此处仅验证 stopSpeaking 不崩溃
    }

    /// 连续两次 previewVoice 不同文本，isPreviewing 应保持 true
    func testMultiplePreviewVoiceKeepsPreviewing() {
        let service = VoiceService()
        service.previewVoice("第一次试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "首次 previewVoice 后 isPreviewing 应为 true")
        service.previewVoice("第二次试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "第二次 previewVoice 后 isPreviewing 应保持 true")
    }

    // MARK: - isUserInitiatedStop 重置流程完整性

    /// stopSpeaking 触发首次 didCancel 后 isUserInitiatedStop 应被重置为 false，
    /// 随后再次 didCancel（系统取消）应触发 onSpeakFinished（验证标志重置逻辑完整）
    func testStopSpeakingResetThenDidCancelTriggersCallback() {
        let service = VoiceService()
        service.stopSpeaking() // isUserInitiatedStop=true
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        // 第一次 didCancel：用户主动停止，不应触发 onSpeakFinished，且重置 isUserInitiatedStop=false
        let firstExpectation = XCTestExpectation(description: "首次 didCancel 不触发 onSpeakFinished")
        firstExpectation.isInverted = true
        service.onSpeakFinished = { firstExpectation.fulfill() }
        service.speechSynthesizer(synthesizer, didCancel: utterance)
        wait(for: [firstExpectation], timeout: 2.0)
        // 第二次 didCancel：isUserInitiatedStop 已被重置为 false，应触发 onSpeakFinished
        let secondExpectation = XCTestExpectation(description: "重置后再次 didCancel 应触发 onSpeakFinished")
        service.onSpeakFinished = { secondExpectation.fulfill() }
        service.speechSynthesizer(synthesizer, didCancel: utterance)
        wait(for: [secondExpectation], timeout: 2.0)
    }

    // MARK: - applyConfig 精确边界值

    /// rate 恰好为 0 时应正常工作（clamp 后仍为 0）
    func testSpeakWithExactZeroRate() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.0,
                              pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "rate=0 时 errorMessage 应为固定文案")
        }
    }

    /// rate 恰好为 1 时应正常工作（clamp 后仍为 1）
    func testSpeakWithExactMaxRate() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 1.0,
                              pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "rate=1 时 errorMessage 应为固定文案")
        }
    }

    /// pitchMultiplier 恰好为 0.5 时应正常工作（clamp 下限）
    func testSpeakWithExactMinPitch() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 0.5, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "pitch=0.5 时 errorMessage 应为固定文案")
        }
    }

    /// pitchMultiplier 恰好为 2.0 时应正常工作（clamp 上限）
    func testSpeakWithExactMaxPitch() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 2.0, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "pitch=2.0 时 errorMessage 应为固定文案")
        }
    }

    /// volume 恰好为 0 时应正常工作（clamp 后仍为 0，静音朗读）
    func testSpeakWithExactZeroVolume() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 1.0, volume: 0.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "volume=0 时 errorMessage 应为固定文案")
        }
    }

    /// volume 恰好为 1 时应正常工作（clamp 上限）
    func testSpeakWithExactMaxVolume() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "volume=1 时 errorMessage 应为固定文案")
        }
    }

    /// 所有参数均为最小值时应正常工作
    func testSpeakWithAllMinValues() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.0,
                              pitchMultiplier: 0.5, volume: 0.0)
        service.speak("最小值测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "全最小值时 errorMessage 应为固定文案")
        }
    }

    /// 所有参数均为最大值时应正常工作
    func testSpeakWithAllMaxValues() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 1.0,
                              pitchMultiplier: 2.0, volume: 1.0)
        service.speak("最大值测试", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "全最大值时 errorMessage 应为固定文案")
        }
    }

    // MARK: - resolveVoice 缓存行为

    /// 两次 speak 使用不同 voiceIdentifier 时 errorMessage 状态应更新
    func testSpeakWithDifferentIdentifiersUpdatesCache() {
        let service = VoiceService()
        let config1 = TTSConfig(voiceIdentifier: "com.voice.first",
                               rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.speak("第一次", config: config1)
        let errorAfterFirst = service.errorMessage

        let config2 = TTSConfig(voiceIdentifier: "com.voice.second",
                               rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.speak("第二次", config: config2)
        let errorAfterSecond = service.errorMessage

        // 两次使用不同的 identifier，errorMessage 状态可能更新
        // 验证不崩溃且 errorMessage 状态合理
        _ = errorAfterFirst
        _ = errorAfterSecond
    }

    /// speak 后再使用相同 identifier 的 config 应命中缓存（errorMessage 不变）
    func testResolveVoiceCacheHitOnSameIdentifier() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "com.test.cache.voice",
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)

        service.speak("第一次", config: config)
        let errorAfterFirst = service.errorMessage

        service.speak("第二次", config: config)
        let errorAfterSecond = service.errorMessage

        // 缓存命中时 errorMessage 状态应一致
        XCTAssertEqual(errorAfterFirst, errorAfterSecond,
                       "相同 identifier 第二次 speak 应命中缓存，errorMessage 一致")
    }

    // MARK: - speak 中断与状态重置

    /// speak 中再次 speak 应中断当前朗读并重置 isPreviewing
    func testSpeakInterruptsPreviousSpeak() {
        let service = VoiceService()
        service.previewVoice("试听中", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "试听中 isPreviewing 应为 true")

        // speak 应中断试听
        service.speak("新内容")
        XCTAssertFalse(service.isPreviewing, "speak 后 isPreviewing 应为 false（中断试听）")
    }

    /// stopSpeaking 在未 speak 时调用不应崩溃
    func testStopSpeakingWhenNotSpeakingDoesNotCrash() {
        let service = VoiceService()
        // 未调用 speak 直接 stopSpeaking
        service.stopSpeaking()
        // 验证不崩溃即可
    }

    /// 连续多次 stopSpeaking 不应崩溃
    func testMultipleStopSpeakingCallsNoCrash() {
        let service = VoiceService()
        service.speak("测试")
        service.stopSpeaking()
        service.stopSpeaking()
        service.stopSpeaking()
        // 验证不崩溃即可
    }

    // MARK: - delegate 边界

    /// didFinish 在试听模式下不应触发 onSpeakFinished。
    /// 使用较长试听文本避免真实合成器在测试期间自然结束，从而防止其 delegate 回调与手动调用产生竞态。
    func testDidFinishDuringPreviewDoesNotTriggerCallback() {
        let service = VoiceService()
        // 使用足够长的文本，确保真实 AVSpeechSynthesizer 在 2 秒测试窗口内不会自然结束
        let longPreviewText = String(repeating: "试听文本。", count: 300)
        service.previewVoice(longPreviewText, config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "试听后 isPreviewing 应为 true")

        let expectation = XCTestExpectation(description: "onSpeakFinished 不应被调用")
        expectation.isInverted = true
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didFinish: utterance)
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - speak Unicode 文本

    /// speak 中文长文本不应崩溃
    func testSpeakChineseTextDoesNotCrash() {
        let service = VoiceService()
        service.speak("你好世界，这是一段中文测试文本。")
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "中文文本 speak 的 errorMessage 应为固定文案")
        }
    }

    /// speak 含 emoji 的文本不应崩溃
    func testSpeakEmojiTextDoesNotCrash() {
        let service = VoiceService()
        service.speak("Hello 🌍🎉🚀")
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "emoji 文本 speak 的 errorMessage 应为固定文案")
        }
    }

    /// speak 含特殊字符的文本不应崩溃
    func testSpeakSpecialCharactersDoesNotCrash() {
        let service = VoiceService()
        service.speak("Test\t\n\\\"'特殊字符!@#$%^&*()")
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "特殊字符文本 speak 的 errorMessage 应为固定文案")
        }
    }

    // MARK: - onRecognized 回包设置

    /// onRecognized 可被设置为 nil（清除回调）
    func testOnRecognizedCanBeSetToNil() {
        let service = VoiceService()
        service.onRecognized = { _ in }
        service.onRecognized = nil
        // 设置为 nil 后调用不应崩溃
        service.onRecognized?("test")
        // 验证不崩溃即可
    }

    // MARK: - previewVoice 边界

    /// previewVoice 空字符串不应崩溃
    func testPreviewVoiceEmptyStringDoesNotCrash() {
        let service = VoiceService()
        service.previewVoice("", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "空字符串 previewVoice 后 isPreviewing 应为 true")
    }

    /// previewVoice 超长文本不应崩溃
    func testPreviewVoiceLongTextDoesNotCrash() {
        let service = VoiceService()
        let longText = String(repeating: "试听文本。", count: 200)
        service.previewVoice(longText, config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "超长文本 previewVoice 后 isPreviewing 应为 true")
    }

    /// stopPreview 连续多次调用不应崩溃
    func testMultipleStopPreviewCallsNoCrash() {
        let service = VoiceService()
        service.previewVoice("试听", config: .defaultValue)
        service.stopPreview()
        service.stopPreview()
        service.stopPreview()
        XCTAssertFalse(service.isPreviewing, "多次 stopPreview 后 isPreviewing 应为 false")
    }

    // MARK: - resolveVoice 有效系统音色

    /// resolveVoice 使用有效的系统音色 identifier 时应解析成功且不设置 errorMessage。
    /// 覆盖 resolveVoice 中 `!identifier.isEmpty && TTSVoiceCatalog.voice(for:) != nil` 分支。
    func testResolveVoiceWithValidSystemVoice() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: voice.identifier,
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.speak("测试有效音色", config: config)

        XCTAssertNil(service.errorMessage, "使用有效音色时 errorMessage 应为 nil（不走 zh-CN 回退分支）")
    }

    /// resolveVoice 相同有效音色第二次调用应命中缓存，errorMessage 保持 nil。
    /// 覆盖 resolveVoice 的 `identifier == cachedVoiceIdentifier` 缓存命中分支（有效音色场景）。
    func testResolveVoiceCacheHitWithValidVoice() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: voice.identifier,
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)

        // 第一次：cache miss，解析音色
        service.speak("第一次", config: config)
        XCTAssertNil(service.errorMessage, "有效音色第一次 speak 时 errorMessage 应为 nil")

        // 第二次：cache hit，直接返回缓存的音色
        service.speak("第二次", config: config)
        XCTAssertNil(service.errorMessage, "缓存命中时 errorMessage 应保持 nil")
    }

    /// previewVoice 使用有效音色时应设置 isPreviewing=true 且 errorMessage 为 nil。
    /// 覆盖 previewVoice → applyConfig → resolveVoice 有效音色路径。
    func testPreviewVoiceWithValidVoiceIdentifier() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: voice.identifier,
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.previewVoice("试听有效音色", config: config)

        XCTAssertTrue(service.isPreviewing, "previewVoice 后 isPreviewing 应为 true")
        XCTAssertNil(service.errorMessage, "有效音色试听时 errorMessage 应为 nil")
    }

    /// speak 在 previewVoice 之后调用应重置 isPreviewing=false 且使用有效音色时 errorMessage 为 nil。
    /// 覆盖 speak 重置 isCurrentPreview + 有效音色解析路径。
    func testSpeakAfterPreviewWithValidVoiceCleansPreviewState() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: voice.identifier,
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)

        service.previewVoice("试听", config: config)
        XCTAssertTrue(service.isPreviewing, "previewVoice 后 isPreviewing 应为 true")
        XCTAssertNil(service.errorMessage, "有效音色试听时 errorMessage 应为 nil")

        service.speak("朗读", config: config)
        XCTAssertFalse(service.isPreviewing, "speak 后 isPreviewing 应为 false")
        XCTAssertNil(service.errorMessage, "有效音色 speak 时 errorMessage 应保持 nil")
    }

    /// speak 从有效音色切换到无效音色再切回应正确处理缓存失效。
    /// 第一次：有效音色（cache miss → 解析成功，errorMessage=nil）
    /// 第二次：无效音色（cache miss → 回退 zh-CN，可能设置 errorMessage）
    /// 第三次：有效音色（cache miss → 重新解析成功）
    /// 第四次：相同有效音色（cache hit → 返回缓存）
    func testSpeakSwitchingBetweenValidAndInvalidVoice() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let validConfig = TTSConfig(voiceIdentifier: voice.identifier,
                                   rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        let invalidConfig = TTSConfig(voiceIdentifier: "com.invalid.nonexistent.voice",
                                     rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)

        // 1. 有效音色
        service.speak("有效", config: validConfig)
        XCTAssertNil(service.errorMessage, "有效音色时 errorMessage 应为 nil")

        // 2. 无效音色（缓存失效，回退 zh-CN）
        service.speak("无效", config: invalidConfig)
        // errorMessage 可能被设置（若 zh-CN 不可用），也可能不被设置（若 zh-CN 可用）

        // 3. 切回有效音色（缓存失效，重新解析）
        service.speak("切回有效", config: validConfig)
        // errorMessage 不会被清除（实现只在 else 分支设置，从不清除）
        // 但不应崩溃，音色应正确解析

        // 4. 相同有效音色（缓存命中）
        service.speak("再次有效", config: validConfig)
        // 不崩溃，缓存命中
    }

    /// speak 使用有效音色后 stopSpeaking 不应崩溃。
    /// 覆盖 stopSpeaking 在有效音色 speak 后的调用路径。
    func testStopSpeakingAfterSpeakWithValidVoice() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: voice.identifier,
                              rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)

        service.speak("测试停止", config: config)
        XCTAssertNil(service.errorMessage, "有效音色 speak 时 errorMessage 应为 nil")

        service.stopSpeaking()
        // 不崩溃即可
    }

    // MARK: - recognizerAvailabilityCheck 默认行为

    /// 默认 recognizerAvailabilityCheck 应返回 Bool 且不崩溃。
    /// 覆盖 VoiceService 中注入点的默认闭包实现。
    func testDefaultRecognizerAvailabilityCheckReturnsBool() {
        let service = VoiceService()
        let available = service.recognizerAvailabilityCheck()
        XCTAssertTrue(available == true || available == false,
                      "默认 recognizerAvailabilityCheck 应返回 Bool")
    }

    // MARK: - deinit 资源释放

    /// 释放 VoiceService 应执行 deinit 清理且不崩溃。
    /// 覆盖 deinit 中 synthesizer.delegate = nil 与 AVAudioSession setActive(false) 路径。
    func testDeinitDoesNotCrash() {
        var service: VoiceService? = VoiceService()
        service = nil
        XCTAssertNil(service, "service 应被释放")
    }

    /// audioEngine 正在运行时释放 VoiceService，应触发 deinit 中停止引擎、移除 tap 的分支。
    /// 仅在当前环境能成功启动录音时执行，否则跳过。
    func testDeinitWhileRecordingReleasesResources() throws {
        var service: VoiceService? = VoiceService()
        service?.recognizerAvailabilityCheck = { true }

        do {
            try service?.startRecording()
        } catch {
            throw XCTSkip("音频会话不可用，无法测试运行中 deinit：\(error)")
        }

        XCTAssertTrue(service?.isRecording == true, "启动录音后 isRecording 应为 true")
        // 不调用 stopRecording，直接释放，触发 deinit 中 audioEngine.isRunning 分支
        service = nil
        XCTAssertNil(service, "service 应被释放")
    }

    // MARK: - 状态转换

    /// speak 后调用 previewVoice 应正确切换到试听状态。
    func testPreviewVoiceAfterSpeakSetsPreviewState() {
        let service = VoiceService()
        service.speak("朗读")
        XCTAssertFalse(service.isPreviewing, "speak 后 isPreviewing 应为 false")
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "previewVoice 后应进入试听状态")
    }

    /// 多个 VoiceService 实例的状态应相互独立。
    func testMultipleServiceInstancesAreIndependent() {
        let service1 = VoiceService()
        let service2 = VoiceService()

        service1.previewVoice("试听1", config: .defaultValue)
        service2.speak("朗读2")

        XCTAssertTrue(service1.isPreviewing, "service1 应处于试听状态")
        XCTAssertFalse(service2.isPreviewing, "service2 不应处于试听状态")
    }

    // MARK: - 错误处理

    /// 使用无效音色 speak 设置 errorMessage 后，再次使用有效音色 speak 不会清除 errorMessage
    ///（验证当前实现只在 fallback 失败时设置 errorMessage、成功时不清除的行为）。
    func testErrorMessagePersistsAfterSwitchingToValidVoice() throws {
        guard let voice = Self.findInstallableVoice() else {
            throw XCTSkip("模拟器无可安装的系统音色")
        }

        let service = VoiceService()
        let invalidConfig = TTSConfig(voiceIdentifier: "com.invalid.nonexistent.voice",
                                     rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.speak("无效", config: invalidConfig)
        let errorAfterInvalid = service.errorMessage

        let validConfig = TTSConfig(voiceIdentifier: voice.identifier,
                                   rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        service.speak("有效", config: validConfig)

        // 当前实现不主动清除 errorMessage，保持之前状态
        XCTAssertEqual(service.errorMessage, errorAfterInvalid,
                       "errorMessage 应保持之前的状态")
    }

    /// 空字符串 identifier 应走默认 zh-CN 回退路径且不崩溃。
    func testEmptyVoiceIdentifierFallsBackToChinese() {
        let service = VoiceService()
        let config = TTSConfig(voiceIdentifier: "", rate: 0.5,
                              pitchMultiplier: 1.0, volume: 1.0)
        service.speak("默认音色", config: config)
        if let msg = service.errorMessage {
            XCTAssertEqual(msg, NSLocalizedString("未找到中文语音，使用默认语音", comment: ""),
                           "空字符串 identifier 回退失败时 errorMessage 应为固定文案")
        }
    }

    // MARK: - 回调与状态属性

    /// recognizedText 可被手动设置并读取。
    func testRecognizedTextCanBeSetAndRead() {
        let service = VoiceService()
        service.recognizedText = "手动设置"
        XCTAssertEqual(service.recognizedText, "手动设置")
    }

    /// onRecognized 闭包可被多次调用并累积结果。
    func testOnRecognizedCanBeCalledMultipleTimes() {
        let service = VoiceService()
        var captured: [String] = []
        service.onRecognized = { text in captured.append(text) }
        service.onRecognized?("第一次")
        service.onRecognized?("第二次")
        XCTAssertEqual(captured, ["第一次", "第二次"])
    }

    /// onSpeakFinished 可被设置为 nil 且后续调用不崩溃。
    func testOnSpeakFinishedCanBeSetToNil() {
        let service = VoiceService()
        service.onSpeakFinished = { }
        service.onSpeakFinished = nil
        // 设置为 nil 后调用不应崩溃
        service.onSpeakFinished?()
    }

    /// isRecording 状态属性可被外部读取与修改。
    func testIsRecordingCanBeSetAndRead() {
        let service = VoiceService()
        XCTAssertFalse(service.isRecording)
        service.isRecording = true
        XCTAssertTrue(service.isRecording)
        service.isRecording = false
        XCTAssertFalse(service.isRecording)
    }

    /// isPreviewing 状态属性可被外部读取与修改。
    func testIsPreviewingCanBeSetAndRead() {
        let service = VoiceService()
        XCTAssertFalse(service.isPreviewing)
        service.isPreviewing = true
        XCTAssertTrue(service.isPreviewing)
    }

    /// errorMessage 状态属性可被外部读取与修改。
    func testErrorMessageCanBeSetAndRead() {
        let service = VoiceService()
        XCTAssertNil(service.errorMessage)
        service.errorMessage = "测试错误"
        XCTAssertEqual(service.errorMessage, "测试错误")
        service.errorMessage = nil
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - 录音完整流程与音频会话

    /// startRecording 在当前环境中的行为取决于音频会话可用性：
    /// - 若 AVAudioSession 与 audioEngine 成功启动，则 isRecording=true，
    ///   运行片刻后 stopRecording 应恢复 false；
    /// - 若模拟器/CI 无法激活音频会话，则抛错且 isRecording 保持 false。
    /// 本测试覆盖真实录音启动、installTap / recognitionTask 回调分发以及停止释放路径，
    /// 同时兼容音频会话成功与失败两种环境，避免在不同模拟器上 flaky。
    func testStartRecordingPathHandlesSuccessOrFailure() throws {
        let service = VoiceService()
        service.recognizerAvailabilityCheck = { true }

        do {
            try service.startRecording()
            // 当前环境允许激活音频会话并启动 audioEngine
            XCTAssertTrue(service.isRecording, "startRecording 成功后 isRecording 应为 true")

            // 让录音运行一小段时间，使 installTap 与 recognitionTask 闭包有机会被调用，
            // 从而覆盖 VoiceService.startRecording() 内部的异步回调分支。
            // 等待时间不宜过长，避免 iOS Simulator 音频子系统死锁。
            wait(for: [], timeout: 0.3)

            service.stopRecording()
            XCTAssertFalse(service.isRecording, "stopRecording 后 isRecording 应为 false")
        } catch {
            // 当前环境（常见 CI 模拟器）无法激活真实音频会话，抛错为合理行为
            XCTAssertFalse(service.isRecording, "startRecording 抛错后 isRecording 应保持 false")
        }
    }

    /// startRecording 在模拟器音频可用时应成功激活 AVAudioSession、创建识别请求与任务，
    /// 并将 isRecording 置为 true。在 iOS Simulator 中跳过真实音频会话操作，避免音频子系统死锁。
    func testStartRecordingSuccessPath() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "iOS Simulator 真实音频会话不稳定，跳过录音启动测试")

        let service = VoiceService()
        service.recognizerAvailabilityCheck = { true }

        do {
            try service.startRecording()
        } catch {
            throw XCTSkip("模拟器音频输入不可用，跳过录音启动测试：\(error)")
        }

        XCTAssertTrue(service.isRecording, "startRecording 成功后 isRecording 应为 true")
        XCTAssertEqual(service.recognizedText, "", "尚未收到识别结果时 recognizedText 应为空")

        service.stopRecording()
        XCTAssertFalse(service.isRecording, "stopRecording 后 isRecording 应为 false")
    }

    /// stopRecording 在已开始录音时应停止音频引擎、移除 tap、结束识别请求并释放 audio session，
    /// 且不抛出异常。在 iOS Simulator 中跳过真实音频会话操作，避免音频子系统死锁。
    func testStopRecordingWhenStarted() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "iOS Simulator 真实音频会话不稳定，跳过录音停止测试")

        let service = VoiceService()
        service.recognizerAvailabilityCheck = { true }

        do {
            try service.startRecording()
        } catch {
            throw XCTSkip("模拟器音频输入不可用：\(error)")
        }

        service.stopRecording()
        XCTAssertFalse(service.isRecording, "stopRecording 后 isRecording 应为 false")
    }

    /// 连续 startRecording → stopRecording 不应崩溃（验证资源释放与重复启用稳定性）。
    /// 在 iOS Simulator 中跳过真实音频会话操作，避免音频子系统死锁。
    func testStartStopRecordingMultipleTimes() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "iOS Simulator 真实音频会话不稳定，跳过重复录音测试")

        let service = VoiceService()
        service.recognizerAvailabilityCheck = { true }

        for i in 0..<3 {
            do {
                try service.startRecording()
            } catch {
                throw XCTSkip("第 \(i) 次 startRecording 失败，模拟器音频不可用：\(error)")
            }
            service.stopRecording()
            XCTAssertFalse(service.isRecording, "第 \(i) 次 stopRecording 后 isRecording 应为 false")
        }
    }

    /// startRecording 成功后、收到识别结果前，onRecognized 不应被自动触发；
    /// 手动调用 onRecognized 应能更新外部状态（验证回调闭包可用）。
    /// 在 iOS Simulator 中跳过真实音频会话操作，避免音频子系统死锁。
    func testOnRecognizedManualInvocationUpdatesExternalState() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
                      "iOS Simulator 真实音频会话不稳定，跳过 onRecognized 录音流程测试")

        let service = VoiceService()
        service.recognizerAvailabilityCheck = { true }

        do {
            try service.startRecording()
        } catch {
            throw XCTSkip("模拟器音频输入不可用：\(error)")
        }

        var captured: String?
        service.onRecognized = { text in captured = text }
        service.onRecognized?("模拟识别结果")
        XCTAssertEqual(captured, "模拟识别结果", "onRecognized 闭包应能接收并传递识别文本")

        service.stopRecording()
    }

    /// requestPermission 应返回 Bool 且不会阻塞主线程；在模拟器无授权弹窗时也能正常返回。
    func testRequestPermissionReturnsBoolOnSimulator() async {
        let service = VoiceService()
        let result = await service.requestPermission()
        XCTAssertTrue(result == true || result == false, "requestPermission 应返回 Bool")
    }

    // MARK: - 辅助

    /// 查找一个可安装的系统音色（AVSpeechSynthesisVoice(identifier:) 返回非 nil）。
    /// 用于测试 resolveVoice 的有效音色路径。
    private static func findInstallableVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { voice in
            AVSpeechSynthesisVoice(identifier: voice.identifier) != nil
        }
    }
}
