import XCTest
@testable import Aether

/// v1.6: MLXVoiceTTSEngine 测试
///
/// 验证 MLX-Voice TTS 引擎在 MLX-Voice 包未集成时的兜底行为：
/// - name / isLoaded 协议契约
/// - loadModel 不抛异常（no-op）
/// - synthesize 在空文本时抛 MultimodalError.emptyInput（NativeTTSEngine 行为）
/// - synthesize 在有效文本时返回 Data（CI 环境下返回 44 字节空 WAV 头）
final class MLXVoiceTTSEngineTests: XCTestCase {

    // MARK: - 协议契约

    func testNameIsMLXVoiceTTS() {
        let engine = MLXVoiceTTSEngine()
        XCTAssertEqual(engine.name, "MLXVoiceTTS (Kokoro/Matcha-TTS)")
    }

    func testIsLoadedReturnsFallbackState() {
        let engine = MLXVoiceTTSEngine()
        // NativeTTSEngine.isLoaded 始终为 true
        XCTAssertTrue(engine.isLoaded, "降级到 NativeTTSEngine 时 isLoaded 应为 true")
    }

    // MARK: - 模型加载

    func testLoadModelDoesNotThrow() async throws {
        let engine = MLXVoiceTTSEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/mlx-voice"))
        XCTAssertTrue(engine.isLoaded, "loadModel 后 isLoaded 应保持 true")
    }

    // MARK: - synthesize

    func testSynthesizeEmptyTextThrowsEmptyInput() async {
        let engine = MLXVoiceTTSEngine()
        do {
            _ = try await engine.synthesize(text: "", voiceId: nil)
            XCTFail("空文本应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput, "空文本应抛 emptyInput 错误")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testSynthesizeValidTextReturnsData() async throws {
        let engine = MLXVoiceTTSEngine()
        let data = try await engine.synthesize(text: "你好，世界", voiceId: nil)
        XCTAssertFalse(data.isEmpty, "合成应返回非空 Data")
        // 至少应含 WAV 头（44 字节）
        XCTAssertGreaterThanOrEqual(data.count, 44, "WAV 数据至少 44 字节头部")
        // 验证 WAV 头部标识
        let riffHeader = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(riffHeader, "RIFF", "WAV 文件应以 'RIFF' 开头")
        let waveHeader = String(data: data.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(waveHeader, "WAVE", "WAV 文件应含 'WAVE' 标识")
    }

    func testSynthesizeCIEnvironmentReturnsEmptyWAVHeader() async throws {
        // CI 环境下 NativeTTSEngine 返回 44 字节空 WAV 头
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        try XCTSkipIf(!isCI, "非 CI 环境跳过：本测试验证 CI 兜底逻辑")

        let engine = MLXVoiceTTSEngine()
        let data = try await engine.synthesize(text: "测试 CI 兜底", voiceId: nil)
        XCTAssertEqual(data.count, 44, "CI 环境下应返回 44 字节空 WAV 头")
    }

    func testSynthesizeWithVoiceId() async throws {
        let engine = MLXVoiceTTSEngine()
        // 使用不存在的 voiceId，应回退到默认中文音色不抛错
        let data = try await engine.synthesize(text: "测试音色回退", voiceId: "non-existent-voice-id")
        XCTAssertFalse(data.isEmpty, "即使 voiceId 无效也应返回合成数据")
    }

    func testSynthesizeLongText() async throws {
        let engine = MLXVoiceTTSEngine()
        let longText = String(repeating: "这是一段较长的测试文本，用于验证合成器的稳定性。", count: 10)
        let data = try await engine.synthesize(text: longText, voiceId: nil)
        XCTAssertFalse(data.isEmpty, "长文本合成也应返回非空 Data")
    }

    func testSynthesizeEnglishText() async throws {
        let engine = MLXVoiceTTSEngine()
        let data = try await engine.synthesize(text: "Hello, world!", voiceId: nil)
        XCTAssertFalse(data.isEmpty, "英文合成也应返回非空 Data")
    }
}
