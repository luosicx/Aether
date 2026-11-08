import XCTest
@testable import Aether

/// v1.6: OpenVoiceCloner 测试
///
/// 验证 OpenVoice v2 语音克隆引擎的桩实现行为：
/// - name / requiresNetwork / isLoaded 协议契约
/// - clone 在音频文件不存在时抛 MultimodalError.emptyInput
/// - clone 在有效音频文件时返回 ClonedVoice（含 id / name / embeddingBase64）
/// - clonedVoices 初始为空
/// - deleteVoice 后 clonedVoices 不再包含该 voice
/// - voice(forId:) 返回正确的 voice
final class OpenVoiceClonerTests: XCTestCase {

    // MARK: - 协议契约

    func testNameIsOpenVoiceCloner() {
        let cloner = OpenVoiceCloner()
        XCTAssertEqual(cloner.name, "OpenVoiceCloner (OpenVoice v2)")
    }

    func testRequiresNetworkIsFalse() {
        let cloner = OpenVoiceCloner()
        XCTAssertFalse(cloner.requiresNetwork, "OpenVoice 完全端侧，requiresNetwork 应为 false")
    }

    func testIsLoadedIsFalse() {
        let cloner = OpenVoiceCloner()
        // OpenVoiceCloner.isLoaded 始终为 false（桩实现）
        XCTAssertFalse(cloner.isLoaded, "桩实现 isLoaded 应为 false")
    }

    // MARK: - 初始状态

    func testClonedVoicesInitiallyEmpty() {
        let cloner = OpenVoiceCloner()
        XCTAssertTrue(cloner.clonedVoices.isEmpty, "clonedVoices 初始应为空")
    }

    // MARK: - loadModel

    func testLoadModelDoesNotThrow() async throws {
        let cloner = OpenVoiceCloner()
        try await cloner.loadModel(at: URL(fileURLWithPath: "/tmp/openvoice"))
        // isLoaded 仍为 false（桩实现）
        XCTAssertFalse(cloner.isLoaded, "桩实现 loadModel 后 isLoaded 仍为 false")
    }

    // MARK: - clone

    func testCloneNonExistentFileThrowsEmptyInput() async {
        let cloner = OpenVoiceCloner()
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).wav")
        do {
            _ = try await cloner.clone(audioPath: nonExistentURL, voiceName: "voice1")
            XCTFail("不存在的文件应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput, "不存在的音频文件应抛 emptyInput")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testCloneValidAudioReturnsClonedVoice() async throws {
        let cloner = OpenVoiceCloner()
        let audioURL = makeTempAudioFile(suffix: ".wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let voice = try await cloner.clone(audioPath: audioURL, voiceName: "我的音色")
        XCTAssertFalse(voice.id.isEmpty, "ClonedVoice.id 应非空")
        XCTAssertEqual(voice.name, "我的音色", "ClonedVoice.name 应等于传入的 voiceName")
        XCTAssertFalse(voice.embeddingBase64.isEmpty, "ClonedVoice.embeddingBase64 应非空（占位 embedding）")
        XCTAssertEqual(voice.sampleAudioPath, audioURL, "ClonedVoice.sampleAudioPath 应等于传入的 audioPath")
        XCTAssertEqual(cloner.clonedVoices.count, 1, "克隆后 clonedVoices 应有 1 个元素")
        XCTAssertEqual(cloner.clonedVoices.first?.id, voice.id, "clonedVoices 应包含刚克隆的 voice")
    }

    func testCloneMultipleVoices() async throws {
        let cloner = OpenVoiceCloner()
        let audioURL1 = makeTempAudioFile(suffix: ".wav")
        let audioURL2 = makeTempAudioFile(suffix: ".wav")
        defer {
            try? FileManager.default.removeItem(at: audioURL1)
            try? FileManager.default.removeItem(at: audioURL2)
        }

        let voice1 = try await cloner.clone(audioPath: audioURL1, voiceName: "音色1")
        let voice2 = try await cloner.clone(audioPath: audioURL2, voiceName: "音色2")
        XCTAssertNotEqual(voice1.id, voice2.id, "两个 voice 的 id 应不同")
        XCTAssertEqual(cloner.clonedVoices.count, 2, "clonedVoices 应有 2 个元素")
    }

    // MARK: - deleteVoice

    func testDeleteVoiceRemovesFromList() async throws {
        let cloner = OpenVoiceCloner()
        let audioURL = makeTempAudioFile(suffix: ".wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let voice = try await cloner.clone(audioPath: audioURL, voiceName: "to-delete")
        XCTAssertEqual(cloner.clonedVoices.count, 1, "克隆后应有 1 个 voice")

        await cloner.deleteVoice(voiceId: voice.id)
        XCTAssertTrue(cloner.clonedVoices.isEmpty, "deleteVoice 后 clonedVoices 应为空")
        XCTAssertNil(cloner.voice(forId: voice.id), "deleteVoice 后 voice(forId:) 应返回 nil")
    }

    func testDeleteNonExistentVoiceIsNoOp() async throws {
        let cloner = OpenVoiceCloner()
        let audioURL = makeTempAudioFile(suffix: ".wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        _ = try await cloner.clone(audioPath: audioURL, voiceName: "voice1")
        XCTAssertEqual(cloner.clonedVoices.count, 1)

        // 删除不存在的 id，应不抛错且不影响现有列表
        await cloner.deleteVoice(voiceId: "non-existent-id")
        XCTAssertEqual(cloner.clonedVoices.count, 1, "删除不存在的 id 不应影响列表")
    }

    // MARK: - voice(forId:)

    func testVoiceForIdReturnsCorrectVoice() async throws {
        let cloner = OpenVoiceCloner()
        let audioURL = makeTempAudioFile(suffix: ".wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let voice = try await cloner.clone(audioPath: audioURL, voiceName: "查找我")
        let found = cloner.voice(forId: voice.id)
        XCTAssertNotNil(found, "voice(forId:) 应返回刚克隆的 voice")
        XCTAssertEqual(found?.id, voice.id)
        XCTAssertEqual(found?.name, "查找我")
    }

    func testVoiceForNonExistentIdReturnsNil() {
        let cloner = OpenVoiceCloner()
        XCTAssertNil(cloner.voice(forId: "non-existent-id"), "voice(forId:) 不存在时应返回 nil")
    }

    // MARK: - 辅助

    private func makeTempAudioFile(suffix: String = ".wav") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + suffix)
        // 写入最小 WAV 头（RIFF + WAVE）
        let data = Data([0x52, 0x49, 0x46, 0x46,  // RIFF
                         0x00, 0x00, 0x00, 0x00,  // size
                         0x57, 0x41, 0x56, 0x45]) // WAVE
        try? data.write(to: url)
        return url
    }
}
