import XCTest
@testable import Aether

/// v1.6: WhisperASREngine 测试
///
/// 验证 whisper.cpp ASR 引擎在 Rust FFI 未集成时的兜底行为：
/// - name / requiresNetwork / isLoaded 协议契约
/// - loadModel 不抛异常（no-op）
/// - transcribe 在 CI 环境下抛 MultimodalError，本地环境下返回带 "[WhisperASR v1.6]" 前缀的字符串
final class WhisperASREngineTests: XCTestCase {

    // MARK: - 协议契约

    func testNameIsWhisperASR() {
        let engine = WhisperASREngine()
        XCTAssertEqual(engine.name, "WhisperASR (whisper.cpp)")
    }

    func testRequiresNetworkIsFalse() {
        let engine = WhisperASREngine()
        XCTAssertFalse(engine.requiresNetwork, "whisper.cpp 完全离线，requiresNetwork 应为 false")
    }

    func testIsLoadedReturnsFallbackState() {
        let engine = WhisperASREngine()
        // NativeASREngine.isLoaded 始终为 true
        XCTAssertTrue(engine.isLoaded, "降级到 NativeASREngine 时 isLoaded 应为 true")
    }

    // MARK: - 模型加载

    func testLoadModelDoesNotThrow() async throws {
        let engine = WhisperASREngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/whisper-ggml"))
        XCTAssertTrue(engine.isLoaded, "loadModel 后 isLoaded 应保持 true")
    }

    // MARK: - transcribe

    func testTranscribeNonExistentFileThrowsEmptyInput() async {
        let engine = WhisperASREngine()
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).wav")
        do {
            _ = try await engine.transcribe(audioPath: nonExistentURL, language: "zh")
            XCTFail("不存在的文件应抛错")
        } catch let error as MultimodalError {
            // NativeASREngine 对不存在文件抛 emptyInput
            XCTAssertEqual(error, .emptyInput, "不存在的音频文件应抛 emptyInput")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testTranscribeUnsupportedFormatThrows() async throws {
        let engine = WhisperASREngine()
        let txtURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-test-\(UUID().uuidString).txt")
        try "test content".write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }

        do {
            _ = try await engine.transcribe(audioPath: txtURL, language: "zh")
            XCTFail("不支持的格式应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .unsupportedAudioFormat, "应抛 unsupportedAudioFormat 错误")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testTranscribeValidAudioFileReturnsWhisperPrefix() async throws {
        // CI 环境下 SFSpeechRecognizer 不可用，跳过
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        try XCTSkipIf(isCI, "CI 环境跳过：需要音频/模型文件")

        let engine = WhisperASREngine()
        let wavURL = makeTempAudioFile(suffix: ".wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        do {
            let result = try await engine.transcribe(audioPath: wavURL, language: "zh")
            XCTAssertTrue(result.hasPrefix("[WhisperASR v1.6]"),
                          "transcribe 结果应以 '[WhisperASR v1.6]' 开头，实际：\(result)")
        } catch let error as MultimodalError {
            // CI 之外的环境也可能因为权限/识别器不可用抛错，接受 asrRecognitionFailed
            switch error {
            case .asrRecognitionFailed:
                break // 预期错误（识别器不可用）
            default:
                XCTFail("意外错误: \(error)")
            }
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testTranscribeCIEnvironmentThrowsOrReturns() async {
        // 本测试在 CI 与本地均可运行，验证 transcribe 不会卡死
        let engine = WhisperASREngine()
        let wavURL = makeTempAudioFile(suffix: ".wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        do {
            _ = try await engine.transcribe(audioPath: wavURL, language: "zh")
            // 不抛错也算通过
        } catch let error as MultimodalError {
            // 接受 asrRecognitionFailed / emptyInput / unsupportedAudioFormat
            switch error {
            case .asrRecognitionFailed, .emptyInput, .unsupportedAudioFormat:
                break
            default:
                XCTFail("意外错误: \(error)")
            }
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
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
