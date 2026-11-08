import XCTest
import CoreGraphics
@testable import Aether

/// v1.6: SDMobileEngine 测试
///
/// 验证 Stable Diffusion Mobile 图像生成引擎的桩实现行为：
/// - name / isLoaded 协议契约
/// - loadModel / unloadModel 不抛异常（no-op）
/// - generate 抛 MultimodalError.platformUnsupported（CoreML SD 包未集成）
final class SDMobileEngineTests: XCTestCase {

    // MARK: - 协议契约

    func testNameIsSDMobile() {
        let engine = SDMobileEngine()
        XCTAssertEqual(engine.name, "SDMobile (Stable Diffusion CoreML)")
    }

    func testIsLoadedIsFalse() {
        let engine = SDMobileEngine()
        // SDMobileEngine.isLoaded 始终为 false（桩实现）
        XCTAssertFalse(engine.isLoaded, "桩实现 isLoaded 应为 false")
    }

    // MARK: - 模型加载

    func testLoadModelDoesNotThrow() async throws {
        let engine = SDMobileEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/sd-mobile"))
        // isLoaded 仍为 false（桩实现）
        XCTAssertFalse(engine.isLoaded, "桩实现 loadModel 后 isLoaded 仍为 false")
    }

    func testUnloadModelDoesNotThrow() async {
        let engine = SDMobileEngine()
        await engine.unloadModel()
        // 不崩溃即可，isLoaded 仍为 false
        XCTAssertFalse(engine.isLoaded, "unloadModel 后 isLoaded 仍为 false")
    }

    // MARK: - generate

    func testGenerateThrowsPlatformUnsupported() async {
        let engine = SDMobileEngine()
        do {
            _ = try await engine.generate(
                prompt: "a cat sitting on a chair",
                negativePrompt: nil,
                width: 512,
                height: 512,
                steps: 20,
                seed: nil
            )
            XCTFail("桩实现应抛 platformUnsupported")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .platformUnsupported,
                           "CoreML SD 包未集成时应抛 platformUnsupported")
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testGenerateThrowsPlatformUnsupportedWithNegativePrompt() async {
        let engine = SDMobileEngine()
        do {
            _ = try await engine.generate(
                prompt: "landscape",
                negativePrompt: "blurry, low quality",
                width: 256,
                height: 256,
                steps: 10,
                seed: 42
            )
            XCTFail("带 negativePrompt 的 generate 也应抛 platformUnsupported")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .platformUnsupported)
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testGenerateThrowsPlatformUnsupportedWithSeed() async {
        let engine = SDMobileEngine()
        do {
            _ = try await engine.generate(
                prompt: "test",
                negativePrompt: nil,
                width: 512,
                height: 512,
                steps: 20,
                seed: 12345
            )
            XCTFail("带 seed 的 generate 也应抛 platformUnsupported")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .platformUnsupported)
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testGenerateThrowsPlatformUnsupportedWithEmptyPrompt() async {
        let engine = SDMobileEngine()
        do {
            _ = try await engine.generate(
                prompt: "",
                negativePrompt: nil,
                width: 512,
                height: 512,
                steps: 20,
                seed: nil
            )
            // 即使 prompt 为空，桩实现优先抛 platformUnsupported（未做 prompt 校验）
            XCTFail("空 prompt 也应抛 platformUnsupported")
        } catch let error as MultimodalError {
            XCTAssertEqual(error, .platformUnsupported)
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }
}
