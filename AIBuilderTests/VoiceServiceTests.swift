import XCTest
import Speech
@testable import AIBuilder

/// VoiceService 单元测试
@MainActor
final class VoiceServiceTests: XCTestCase {

    /// 未 startRecording 直接 stopRecording 不应崩溃
    func testStopRecordingWhenNotStartedDoesNotCrash() {
        let service = VoiceService()
        service.stopRecording()
        XCTAssertFalse(service.isRecording, "未开始录音时 isRecording 应为 false")
    }

    /// SFSpeechRecognizer 不可用时 startRecording 应抛错；
    /// 若识别器可用（模拟器通常可用），跳过此用例
    func testStartRecordingWhenRecognizerUnavailable() throws {
        // VoiceService 内部使用 zh-CN 识别器；此处镜像构造以判断可用性
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        // 仅在识别器不可用时继续；可用则跳过（无法测试不可用分支）
        try XCTSkipUnless(recognizer?.isAvailable != true,
                          "zh-CN SFSpeechRecognizer 可用，跳过不可用分支测试")
        let service = VoiceService()
        XCTAssertThrowsError(try service.startRecording(),
                             "识别器不可用时 startRecording 应抛错") { error in
            let nserror = error as NSError
            XCTAssertEqual(nserror.domain, "VoiceService",
                           "抛出的错误 domain 应为 VoiceService")
        }
    }
}
