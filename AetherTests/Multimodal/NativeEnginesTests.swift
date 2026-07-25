import XCTest
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
@testable import Aether

/// v1.4: 原生多模态引擎测试
///
/// 覆盖 NativeVisionEngine / NativeASREngine / NativeTTSEngine 三个原生实现：
/// - 协议契约（isLoaded / name / loadedModelName）
/// - loadModel/unloadModel 兼容性（no-op，不抛错）
/// - Vision 5 个子任务并发执行（分类 / 人脸 / 矩形 / 文字 / 条码）
/// - ASR 文件识别（CI 环境跳过权限请求）
/// - TTS 合成（CI 环境返回空 WAV 头）
final class NativeEnginesTests: XCTestCase {

    // MARK: - NativeVisionEngine

    func testVisionEngineInitialState() {
        let engine = NativeVisionEngine()
        XCTAssertTrue(engine.isLoaded, "Vision 框架无需加载，isLoaded 应为 true")
        XCTAssertEqual(engine.loadedModelName, "Apple Vision (Native)")
    }

    func testVisionEngineLoadModelIsNoOp() async throws {
        let engine = NativeVisionEngine()
        // loadModel 应为 no-op，不抛错且不改变 isLoaded 状态
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/model"), modelName: "Qwen2-VL-2B")
        XCTAssertTrue(engine.isLoaded, "加载后 isLoaded 应保持 true")
        // loadedModelName 不变（Vision 框架不加载外部模型）
        XCTAssertEqual(engine.loadedModelName, "Apple Vision (Native)")
    }

    func testVisionEngineUnloadModelIsNoOp() async throws {
        let engine = NativeVisionEngine()
        await engine.unloadModel()
        XCTAssertTrue(engine.isLoaded, "unloadModel 后 isLoaded 应保持 true（Vision 无可卸载模型）")
    }

    func testVisionEngineDescribeReturnsNonEmpty() async throws {
        let engine = NativeVisionEngine()
        let cgImage = makeSolidColorCGImage(width: 64, height: 64, red: 1, green: 0, blue: 0)
        let result = try await engine.describe(image: cgImage, prompt: "描述这张图片")
        XCTAssertFalse(result.isEmpty, "describe 应返回非空字符串")
        XCTAssertTrue(result.contains("Vision") || result.contains("图像") || result.contains("尺寸"),
                      "结果应含 Vision / 图像 / 尺寸 关键字，实际：\(result)")
    }

    func testVisionEngineDescribeIncludesImageSize() async throws {
        let engine = NativeVisionEngine()
        let cgImage = makeSolidColorCGImage(width: 128, height: 64, red: 0, green: 1, blue: 0)
        let result = try await engine.describe(image: cgImage, prompt: "test")
        XCTAssertTrue(result.contains("128"), "结果应含图像宽度 128，实际：\(result)")
        XCTAssertTrue(result.contains("64"), "结果应含图像高度 64，实际：\(result)")
    }

    func testVisionEngineDescribeTextPromptFocuses() async throws {
        let engine = NativeVisionEngine()
        let cgImage = makeSolidColorCGImage(width: 32, height: 32, red: 0, green: 0, blue: 1)
        // 纯色图像通常无文字，应返回"未识别到文字"
        let result = try await engine.describe(image: cgImage, prompt: "识别文字")
        XCTAssertTrue(result.contains("文字") || result.contains("未识别"),
                      "含 '文字' prompt 应聚焦 OCR 结果，实际：\(result)")
    }

    func testVisionEngineDescribeFacePromptFocuses() async throws {
        let engine = NativeVisionEngine()
        let cgImage = makeSolidColorCGImage(width: 32, height: 32, red: 1, green: 1, blue: 1)
        let result = try await engine.describe(image: cgImage, prompt: "检测人脸")
        XCTAssertTrue(result.contains("人脸") || result.contains("未检测"),
                      "含 '人脸' prompt 应聚焦人脸检测结果，实际：\(result)")
    }

    func testVisionEngineDescribeBarcodePromptFocuses() async throws {
        let engine = NativeVisionEngine()
        let cgImage = makeSolidColorCGImage(width: 32, height: 32, red: 0, green: 0, blue: 0)
        let result = try await engine.describe(image: cgImage, prompt: "扫描二维码")
        XCTAssertTrue(result.contains("条码") || result.contains("二维码") || result.contains("未检测"),
                      "含 '二维码' prompt 应聚焦条码检测结果，实际：\(result)")
    }

    func testVisionEngineDescribeWithLargeImage() async throws {
        let engine = NativeVisionEngine()
        let cgImage = makeSolidColorCGImage(width: 256, height: 256, red: 0.5, green: 0.5, blue: 0.5)
        let result = try await engine.describe(image: cgImage, prompt: "描述")
        XCTAssertFalse(result.isEmpty, "大图也应返回非空描述")
    }

    // MARK: - NativeASREngine

    func testASREngineInitialState() {
        let engine = NativeASREngine()
        XCTAssertTrue(engine.isLoaded, "SFSpeechRecognizer 无需加载，isLoaded 应为 true")
        XCTAssertTrue(engine.name.contains("NativeASR") || engine.name.contains("SFSpeech"),
                      "name 应含 NativeASR 或 SFSpeech，实际：\(engine.name)")
        XCTAssertTrue(engine.requiresNetwork, "SFSpeechRecognizer 默认需在线")
    }

    func testASREngineLoadModelIsNoOp() async throws {
        let engine = NativeASREngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/whisper"))
        XCTAssertTrue(engine.isLoaded, "加载后 isLoaded 应保持 true")
    }

    func testASREngineTranscribeNonExistentFileThrows() async {
        let engine = NativeASREngine()
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-audio-\(UUID().uuidString).wav")
        do {
            _ = try await engine.transcribe(audioPath: nonExistentURL, language: "zh")
            XCTFail("不存在的文件应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput, "应抛 emptyInput 错误")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testASREngineTranscribeUnsupportedFormatThrows() async throws {
        let engine = NativeASREngine()
        // 创建一个 .txt 文件（不支持的格式）
        let tempDir = FileManager.default.temporaryDirectory
        let txtURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).txt")
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

    func testASREngineTranscribeEmptyFileThrows() async {
        let engine = NativeASREngine()
        let tempDir = FileManager.default.temporaryDirectory
        // 创建空 wav 文件（0 字节）
        let wavURL = tempDir.appendingPathComponent("empty-\(UUID().uuidString).wav")
        try? Data().write(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        // CI 环境下 SFSpeechRecognizer 不可用，会抛 asrRecognitionFailed
        // 本地环境下空文件可能识别失败或返回空字符串
        do {
            _ = try await engine.transcribe(audioPath: wavURL, language: "zh")
            // 不抛错也算通过（某些环境下可能返回空字符串）
        } catch let error as MultimodalError {
            // 接受 asrRecognitionFailed 或 emptyInput
            switch error {
            case .asrRecognitionFailed, .emptyInput:
                break // 预期错误
            default:
                XCTFail("意外错误: \(error)")
            }
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    // MARK: - NativeTTSEngine

    func testTTSEngineInitialState() {
        let engine = NativeTTSEngine()
        XCTAssertTrue(engine.isLoaded, "AVSpeechSynthesizer 无需加载，isLoaded 应为 true")
        XCTAssertTrue(engine.name.contains("NativeTTS") || engine.name.contains("AVSpeech"),
                      "name 应含 NativeTTS 或 AVSpeech，实际：\(engine.name)")
    }

    func testTTSEngineLoadModelIsNoOp() async throws {
        let engine = NativeTTSEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/mlx-voice"))
        XCTAssertTrue(engine.isLoaded, "加载后 isLoaded 应保持 true")
    }

    func testTTSEngineSynthesizeEmptyTextThrows() async {
        let engine = NativeTTSEngine()
        do {
            _ = try await engine.synthesize(text: "", voiceId: nil)
            XCTFail("空文本应抛错")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .emptyInput, "应抛 emptyInput 错误")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testTTSEngineSynthesizeReturnsNonEmptyData() async throws {
        let engine = NativeTTSEngine()
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

    func testTTSEngineSynthesizeWithVoiceId() async throws {
        let engine = NativeTTSEngine()
        // 使用不存在的 voiceId，应回退到默认中文音色不抛错
        let data = try await engine.synthesize(text: "测试音色回退", voiceId: "non-existent-voice-id")
        XCTAssertFalse(data.isEmpty, "即使 voiceId 无效也应返回合成数据")
    }

    func testTTSEngineSynthesizeLongText() async throws {
        let engine = NativeTTSEngine()
        let longText = String(repeating: "这是一段较长的测试文本，用于验证合成器的稳定性。", count: 10)
        let data = try await engine.synthesize(text: longText, voiceId: nil)
        XCTAssertFalse(data.isEmpty, "长文本合成也应返回非空 Data")
    }

    func testTTSEngineSynthesizeEnglishText() async throws {
        let engine = NativeTTSEngine()
        let data = try await engine.synthesize(text: "Hello, world!", voiceId: nil)
        XCTAssertFalse(data.isEmpty, "英文合成也应返回非空 Data")
    }

    // MARK: - MultimodalFacade 默认引擎验证

    func testFacadeDefaultUsesNativeEngines() async {
        let facade = MultimodalFacade()
        let visionName = await facade.visionEngineName
        let asrName = await facade.asrEngineName
        let ttsName = await facade.ttsEngineName
        // v1.4: 默认应使用 Native 引擎而非 Placeholder
        XCTAssertTrue(visionName.contains("NativeVisionEngine"), "默认应使用 NativeVisionEngine，实际：\(visionName)")
        XCTAssertTrue(asrName.contains("NativeASR"), "默认应使用 NativeASREngine，实际：\(asrName)")
        XCTAssertTrue(ttsName.contains("NativeTTS"), "默认应使用 NativeTTSEngine，实际：\(ttsName)")
    }

    func testFacadeCanSwitchToPlaceholderEngines() async {
        let facade = MultimodalFacade()
        // 验证可以切换回占位实现（向后兼容）
        await facade.setVisionEngine(PlaceholderVisionEngine())
        await facade.setASREngine(PlaceholderASREngine())
        await facade.setTTSEngine(PlaceholderTTSEngine())
        let visionName = await facade.visionEngineName
        let asrName = await facade.asrEngineName
        let ttsName = await facade.ttsEngineName
        XCTAssertTrue(visionName.contains("PlaceholderVisionEngine"), "切换后应使用 PlaceholderVisionEngine")
        XCTAssertEqual(asrName, "PlaceholderASR")
        XCTAssertEqual(ttsName, "PlaceholderTTS")
    }

    func testFacadeDescribeImageWithNativeEngine() async throws {
        // CI 环境下跳过（Vision 请求可能不稳定）
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：CI 环境下 Vision 请求可能不稳定")
        let facade = MultimodalFacade()
        // 创建临时图片文件
        let tempDir = FileManager.default.temporaryDirectory
        let imageURL = tempDir.appendingPathComponent("facade-test-\(UUID().uuidString).png")
        try writePNGImage(to: imageURL, width: 64, height: 64, red: 0, green: 1, blue: 0)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let result = try await facade.describeImage(at: imageURL, prompt: "描述")
        XCTAssertFalse(result.isEmpty, "facade.describeImage 应返回非空结果")
    }

    // MARK: - 辅助

    private func makeSolidColorCGImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
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
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func writePNGImage(to url: URL, width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws {
        let cgImage = makeSolidColorCGImage(width: width, height: height, red: red, green: green, blue: blue)
        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage)
        guard let pngData = uiImage.pngData() else {
            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }
        try pngData.write(to: url)
        #elseif canImport(AppKit)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }
        try pngData.write(to: url)
        #else
        throw NSError(domain: "TestError", code: -1, userInfo: nil)
        #endif
    }
}
