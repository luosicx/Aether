import XCTest
import AetherFoundation
@testable import Aether

/// ChatViewModel 朗读状态机（toggleSpeak）单元测试
///
/// 朗读一律走合成器空桩：模拟器/无头 CI 没有可用音频设备，真实 AVSpeechSynthesizer
/// 的 speak/stopSpeaking 会长时间阻塞（iOS 27 CI 上 4 次调用直接撞 60s 上限），
/// 而这些用例只验证 speakingMessageId 状态机，不验证音频输出。
@MainActor
final class ChatViewModelSpeechTests: XCTestCase {

    override func setUp() async throws {
        // 隔离 Keychain，避免 ChatViewModel 初始化触达真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
    }

    override func tearDown() async throws {
        KeychainManager.shared.backend = SystemKeychainBackend()
    }

    private func makeSpeechStubbedViewModel() -> ChatViewModel {
        let vm = ChatViewModel()
        vm.voiceService.speechSynthesizeOverride = { _ in }
        vm.voiceService.speechStopOverride = {}
        return vm
    }

    /// 17.8 同 id 调用 toggleSpeak 第二次应停止朗读并清空 speakingMessageId
    func testToggleSpeakSameIdStops() {
        let vm = makeSpeechStubbedViewModel()
        let id = UUID()

        vm.toggleSpeak(messageId: id, content: "hello")
        XCTAssertEqual(vm.speakingMessageId, id,
                       "首次调用应设 speakingMessageId")

        vm.toggleSpeak(messageId: id, content: "hello")
        XCTAssertNil(vm.speakingMessageId,
                     "同 id 第二次调用应停止并清空 speakingMessageId")
    }

    /// 17.9 不同 id 调用 toggleSpeak 应切换 speakingMessageId
    func testToggleSpeakDifferentIdSwitches() {
        let vm = makeSpeechStubbedViewModel()
        let id1 = UUID()
        let id2 = UUID()

        vm.toggleSpeak(messageId: id1, content: "hello")
        XCTAssertEqual(vm.speakingMessageId, id1)

        vm.toggleSpeak(messageId: id2, content: "world")
        XCTAssertEqual(vm.speakingMessageId, id2,
                       "切换到不同 id 应更新 speakingMessageId")
    }

    /// toggleSpeak 连续切换多个消息 id，speakingMessageId 应跟随最后一条；再次点击同一条停止
    func testToggleSpeakAcrossMultipleMessages() {
        let vm = makeSpeechStubbedViewModel()
        let id1 = UUID(), id2 = UUID(), id3 = UUID()

        vm.toggleSpeak(messageId: id1, content: "a")
        XCTAssertEqual(vm.speakingMessageId, id1)
        vm.toggleSpeak(messageId: id2, content: "b")
        XCTAssertEqual(vm.speakingMessageId, id2)
        vm.toggleSpeak(messageId: id3, content: "c")
        XCTAssertEqual(vm.speakingMessageId, id3, "连续切换后应跟随最后一条 id")
        // 再次点击同一条应停止
        vm.toggleSpeak(messageId: id3, content: "c")
        XCTAssertNil(vm.speakingMessageId, "同 id 再次点击应停止朗读")
    }
}
