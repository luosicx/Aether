import XCTest
import CoreGraphics
@testable import Aether

/// v1.3: Placeholder 引擎占位实现测试
final class PlaceholderEnginesTests: XCTestCase {

    // MARK: - PlaceholderVisionEngine

    func testVisionEngineInitialState() {
        let engine = PlaceholderVisionEngine()
        XCTAssertFalse(engine.isLoaded)
        XCTAssertNil(engine.loadedModelName)
    }

    func testVisionEngineLoadModel() async throws {
        let engine = PlaceholderVisionEngine()
        let url = URL(fileURLWithPath: "/tmp/model")
        try await engine.loadModel(at: url, modelName: "Qwen2-VL-2B")
        XCTAssertTrue(engine.isLoaded)
        XCTAssertEqual(engine.loadedModelName, "Qwen2-VL-2B")
    }

    func testVisionEngineUnloadModel() async throws {
        let engine = PlaceholderVisionEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp"), modelName: "test")
        await engine.unloadModel()
        XCTAssertFalse(engine.isLoaded)
        XCTAssertNil(engine.loadedModelName)
    }

    func testVisionEngineDescribeWithoutLoadThrows() async {
        let engine = PlaceholderVisionEngine()
        let cgImage = makeTestCGImage()
        do {
            _ = try await engine.describe(image: cgImage, prompt: "test")
            XCTFail("未加载模型应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .engineNotLoaded)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testVisionEngineDescribeAfterLoad() async throws {
        let engine = PlaceholderVisionEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp"), modelName: "test")
        let cgImage = makeTestCGImage()
        let result = try await engine.describe(image: cgImage, prompt: "描述这张图片")
        XCTAssertTrue(result.contains("VLM 占位"), "占位实现应返回提示信息")
        XCTAssertTrue(result.contains("描述这张图片"), "应包含 prompt")
    }

    // MARK: - PlaceholderASREngine

    func testASREngineInitialState() {
        let engine = PlaceholderASREngine()
        XCTAssertEqual(engine.name, "PlaceholderASR")
        XCTAssertFalse(engine.requiresNetwork)
        XCTAssertFalse(engine.isLoaded)
    }

    func testASREngineLoadModel() async throws {
        let engine = PlaceholderASREngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/whisper"))
        XCTAssertTrue(engine.isLoaded)
    }

    func testASREngineTranscribeWithoutLoadThrows() async {
        let engine = PlaceholderASREngine()
        do {
            _ = try await engine.transcribe(audioPath: URL(fileURLWithPath: "/tmp/audio.wav"), language: "zh")
            XCTFail("未加载模型应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .engineNotLoaded)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testASREngineTranscribeAfterLoad() async throws {
        let engine = PlaceholderASREngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp"))
        let result = try await engine.transcribe(audioPath: URL(fileURLWithPath: "/tmp/audio.wav"), language: "zh")
        XCTAssertTrue(result.contains("ASR 占位"))
        XCTAssertTrue(result.contains("audio.wav"))
    }

    // MARK: - PlaceholderTTSEngine

    func testTTSEngineInitialState() {
        let engine = PlaceholderTTSEngine()
        XCTAssertEqual(engine.name, "PlaceholderTTS")
        XCTAssertFalse(engine.isLoaded)
    }

    func testTTSEngineLoadModel() async throws {
        let engine = PlaceholderTTSEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/mlx-voice"))
        XCTAssertTrue(engine.isLoaded)
    }

    func testTTSEngineSynthesizeWithoutLoadThrows() async {
        let engine = PlaceholderTTSEngine()
        do {
            _ = try await engine.synthesize(text: "test", voiceId: nil)
            XCTFail("未加载模型应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .engineNotLoaded)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testTTSEngineSynthesizeEmptyTextThrows() async throws {
        let engine = PlaceholderTTSEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp"))
        do {
            _ = try await engine.synthesize(text: "", voiceId: nil)
            XCTFail("空文本应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testTTSEngineSynthesizeSuccess() async throws {
        let engine = PlaceholderTTSEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp"))
        let data = try await engine.synthesize(text: "你好", voiceId: nil)
        XCTAssertTrue(data.isEmpty, "占位实现返回空 Data")
    }

    // MARK: - PlaceholderVoiceCloner

    func testVoiceClonerInitialState() {
        let cloner = PlaceholderVoiceCloner()
        XCTAssertFalse(cloner.isLoaded)
        XCTAssertTrue(cloner.clonedVoices.isEmpty)
    }

    func testVoiceClonerLoadModel() async throws {
        let cloner = PlaceholderVoiceCloner()
        try await cloner.loadModel(at: URL(fileURLWithPath: "/tmp/openvoice"))
        XCTAssertTrue(cloner.isLoaded)
    }

    func testVoiceClonerCloneWithoutLoadThrows() async {
        let cloner = PlaceholderVoiceCloner()
        do {
            _ = try await cloner.clone(audioPath: URL(fileURLWithPath: "/tmp/sample.wav"), voiceName: "voice1")
            XCTFail("未加载模型应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .engineNotLoaded)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testVoiceClonerCloneSuccess() async throws {
        let cloner = PlaceholderVoiceCloner()
        try await cloner.loadModel(at: URL(fileURLWithPath: "/tmp"))
        let voice = try await cloner.clone(audioPath: URL(fileURLWithPath: "/tmp/sample.wav"), voiceName: "我的音色")
        XCTAssertEqual(voice.name, "我的音色")
        XCTAssertEqual(cloner.clonedVoices.count, 1)
        XCTAssertEqual(cloner.clonedVoices.first?.id, voice.id)
    }

    func testVoiceClonerDeleteVoice() async throws {
        let cloner = PlaceholderVoiceCloner()
        try await cloner.loadModel(at: URL(fileURLWithPath: "/tmp"))
        let voice = try await cloner.clone(audioPath: URL(fileURLWithPath: "/tmp/sample.wav"), voiceName: "voice1")
        await cloner.deleteVoice(voiceId: voice.id)
        XCTAssertTrue(cloner.clonedVoices.isEmpty)
    }

    func testVoiceClonerVoiceForId() async throws {
        let cloner = PlaceholderVoiceCloner()
        try await cloner.loadModel(at: URL(fileURLWithPath: "/tmp"))
        let voice = try await cloner.clone(audioPath: URL(fileURLWithPath: "/tmp/sample.wav"), voiceName: "voice1")
        let found = cloner.voice(forId: voice.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "voice1")
        XCTAssertNil(cloner.voice(forId: "nonexistent"))
    }

    // MARK: - PlaceholderImageGenerationEngine

    func testImageGenEngineInitialState() {
        let engine = PlaceholderImageGenerationEngine()
        XCTAssertEqual(engine.name, "PlaceholderImageGen")
        XCTAssertFalse(engine.isLoaded)
    }

    func testImageGenEngineLoadModelNoOp() async throws {
        let engine = PlaceholderImageGenerationEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/sd"))
        // isLoaded 始终为 false（占位）
        XCTAssertFalse(engine.isLoaded)
    }

    func testImageGenEngineUnloadModelNoOp() async {
        let engine = PlaceholderImageGenerationEngine()
        await engine.unloadModel()
        // 不崩溃即可
    }

    func testImageGenEngineGenerateThrows() async {
        let engine = PlaceholderImageGenerationEngine()
        do {
            _ = try await engine.generate(
                prompt: "cat",
                negativePrompt: nil,
                width: 512,
                height: 512,
                steps: 20,
                seed: nil
            )
            XCTFail("占位实现应抛 platformUnsupported")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .platformUnsupported)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - ClonedVoice 数据结构

    func testClonedVoiceEquality() {
        let path = URL(fileURLWithPath: "/tmp/sample.wav")
        let voice1 = ClonedVoice(name: "voice1", sampleAudioPath: path, embeddingBase64: "abc")
        let voice2 = ClonedVoice(name: "voice1", sampleAudioPath: path, embeddingBase64: "abc")
        XCTAssertEqual(voice1, voice2)
    }

    func testClonedVoiceIdDefault() {
        let voice1 = ClonedVoice(name: "v", sampleAudioPath: URL(fileURLWithPath: "/"), embeddingBase64: "")
        let voice2 = ClonedVoice(name: "v", sampleAudioPath: URL(fileURLWithPath: "/"), embeddingBase64: "")
        XCTAssertNotEqual(voice1.id, voice2.id, "默认 id 应为 UUID，每次不同")
    }

    // MARK: - 辅助

    private func makeTestCGImage() -> CGImage {
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
