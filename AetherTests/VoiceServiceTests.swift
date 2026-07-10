import XCTest
import Speech
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
}
