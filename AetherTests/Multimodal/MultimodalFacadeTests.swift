import XCTest
@testable import Aether

/// v1.3: MultimodalFacade 多模态门面测试
final class MultimodalFacadeTests: XCTestCase {

    // MARK: - 默认引擎

    func testDefaultEnginesArePlaceholder() async {
        let facade = MultimodalFacade()
        XCTAssertTrue(facade.visionEngineName.contains("PlaceholderVisionEngine"))
        XCTAssertEqual(facade.asrEngineName, "PlaceholderASR")
        XCTAssertEqual(facade.ttsEngineName, "PlaceholderTTS")
        XCTAssertTrue(facade.voiceClonerName.contains("PlaceholderVoiceCloner"))
        XCTAssertEqual(facade.imageGenEngineName, "PlaceholderImageGen")
    }

    // MARK: - describeImage

    @MainActor
    func testDescribeImageEmptyPromptThrows() async {
        let facade = MultimodalFacade()
        do {
            _ = try await facade.describeImage(at: URL(fileURLWithPath: "/tmp/test.png"), prompt: "")
            XCTFail("空 prompt 应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    @MainActor
    func testDescribeImageNonExistentFileThrows() async {
        let facade = MultimodalFacade()
        do {
            _ = try await facade.describeImage(at: URL(fileURLWithPath: "/tmp/nonexistent.png"), prompt: "describe")
            XCTFail("不存在的文件应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .unsupportedImageFormat)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - transcribeAudio

    @MainActor
    func testTranscribeAudioNonExistentFileThrows() async {
        let facade = MultimodalFacade()
        do {
            _ = try await facade.transcribeAudio(at: URL(fileURLWithPath: "/tmp/nonexistent.wav"), language: "zh")
            XCTFail("不存在的文件应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - synthesizeSpeech

    @MainActor
    func testSynthesizeSpeechEmptyTextThrows() async {
        let facade = MultimodalFacade()
        do {
            _ = try await facade.synthesizeSpeech(text: "", voiceId: nil)
            XCTFail("空文本应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - generateImage

    @MainActor
    func testGenerateImageEmptyPromptThrows() async {
        let facade = MultimodalFacade()
        do {
            _ = try await facade.generateImage(prompt: "")
            XCTFail("空 prompt 应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    @MainActor
    func testGenerateImagePlaceholderThrowsPlatformUnsupported() async {
        let facade = MultimodalFacade()
        do {
            _ = try await facade.generateImage(prompt: "cat")
            XCTFail("占位实现应抛 platformUnsupported")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .platformUnsupported)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - cloneVoice

    @MainActor
    func testCloneVoiceWithPlaceholder() async throws {
        let facade = MultimodalFacade()
        // PlaceholderVoiceCloner 未 loadModel 应抛 engineNotLoaded
        do {
            _ = try await facade.cloneVoice(audioPath: URL(fileURLWithPath: "/tmp/sample.wav"), voiceName: "voice1")
            XCTFail("未加载克隆模型应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .engineNotLoaded)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - 引擎切换（依赖注入）

    @MainActor
    func testSetVisionEngine() async {
        let facade = MultimodalFacade()
        let customEngine = PlaceholderVisionEngine()
        await facade.setVisionEngine(customEngine)
        XCTAssertTrue(facade.visionEngineName.contains("PlaceholderVisionEngine"))
    }

    @MainActor
    func testSetASREngine() async {
        let facade = MultimodalFacade()
        await facade.setASREngine(PlaceholderASREngine())
        XCTAssertEqual(facade.asrEngineName, "PlaceholderASR")
    }

    @MainActor
    func testSetTTSEngine() async {
        let facade = MultimodalFacade()
        await facade.setTTSEngine(PlaceholderTTSEngine())
        XCTAssertEqual(facade.ttsEngineName, "PlaceholderTTS")
    }

    @MainActor
    func testSetVoiceCloner() async {
        let facade = MultimodalFacade()
        await facade.setVoiceCloner(PlaceholderVoiceCloner())
        XCTAssertTrue(facade.voiceClonerName.contains("PlaceholderVoiceCloner"))
    }

    @MainActor
    func testSetImageGenEngine() async {
        let facade = MultimodalFacade()
        await facade.setImageGenEngine(PlaceholderImageGenerationEngine())
        XCTAssertEqual(facade.imageGenEngineName, "PlaceholderImageGen")
    }

    // MARK: - budgetSnapshot

    func testBudgetSnapshot() async {
        let facade = MultimodalFacade()
        let snapshot = await facade.budgetSnapshot()
        XCTAssertGreaterThanOrEqual(snapshot.totalMB, 0)
        XCTAssertGreaterThanOrEqual(snapshot.availableMB, 0)
    }
}
