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
}
