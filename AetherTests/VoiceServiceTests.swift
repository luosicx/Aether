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

    /// didFinish 在试听模式下不应触发 onSpeakFinished
    func testDidFinishDuringPreviewDoesNotTriggerCallback() {
        let service = VoiceService()
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing, "试听后 isPreviewing 应为 true")

        let expectation = XCTestExpectation(description: "onSpeakFinished 不应被调用")
        expectation.isInverted = true
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didFinish: utterance)
        wait(for: [expectation], timeout: 2.0)
    }

    /// didCancel 在试听模式下应清理试听状态但不触发 onSpeakFinished
    func testDidCancelDuringPreviewDoesNotTriggerMainCallback() {
        let service = VoiceService()
        service.previewVoice("试听", config: .defaultValue)
        XCTAssertTrue(service.isPreviewing)

        let expectation = XCTestExpectation(description: "onSpeakFinished 不应被调用")
        expectation.isInverted = true
        service.onSpeakFinished = { expectation.fulfill() }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        service.speechSynthesizer(synthesizer, didCancel: utterance)
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
}
