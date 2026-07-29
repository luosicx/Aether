import XCTest
import CoreGraphics
@testable import Aether

/// v1.6: MLXVisionEngine 测试
///
/// 验证 MLX-VLM 视觉引擎在 MLX-VLM 包未集成时的兜底行为：
/// - init 不抛异常
/// - isLoaded / loadedModelName 透传 NativeVisionEngine
/// - loadModel / unloadModel 不抛异常（no-op）
/// - describe 返回带 "[MLXVisionEngine v1.6]" 前缀的字符串
final class MLXVisionEngineTests: XCTestCase {

    // MARK: - 初始化与状态

    func testInitDoesNotThrow() {
        let engine = MLXVisionEngine()
        XCTAssertTrue(engine.isLoaded, "MLXVisionEngine 应降级到 NativeVisionEngine，isLoaded 为 true")
    }

    func testIsLoadedReturnsFallbackState() {
        let engine = MLXVisionEngine()
        // NativeVisionEngine.isLoaded 始终为 true
        XCTAssertTrue(engine.isLoaded, "降级到 NativeVisionEngine 时 isLoaded 应为 true")
    }

    func testLoadedModelNameReturnsFallbackName() {
        let engine = MLXVisionEngine()
        XCTAssertEqual(engine.loadedModelName, "Apple Vision (Native)",
                       "loadedModelName 应透传 NativeVisionEngine 的模型名")
    }

    // MARK: - 模型加载

    func testLoadModelDoesNotThrow() async throws {
        let engine = MLXVisionEngine()
        try await engine.loadModel(at: URL(fileURLWithPath: "/tmp/mlx-vlm"), modelName: "Qwen2-VL-2B")
        XCTAssertTrue(engine.isLoaded, "loadModel 后 isLoaded 应保持 true")
    }

    func testUnloadModelDoesNotThrow() async throws {
        let engine = MLXVisionEngine()
        await engine.unloadModel()
        // NativeVisionEngine.unloadModel 是 no-op，isLoaded 保持 true
        XCTAssertTrue(engine.isLoaded, "unloadModel 后 NativeVisionEngine.isLoaded 仍为 true（无可卸载模型）")
    }

    // MARK: - describe

    func testDescribeReturnsMLXVisionPrefix() async throws {
        let engine = MLXVisionEngine()
        let cgImage = makeTestCGImage(width: 1, height: 1)
        let result = try await engine.describe(image: cgImage, prompt: "描述这张图片")
        XCTAssertTrue(result.hasPrefix("[MLXVisionEngine v1.6]"),
                      "describe 结果应以 '[MLXVisionEngine v1.6]' 开头，实际：\(result)")
        XCTAssertFalse(result.isEmpty, "describe 应返回非空字符串")
    }

    func testDescribeIncludesFallbackContent() async throws {
        let engine = MLXVisionEngine()
        let cgImage = makeTestCGImage(width: 32, height: 32)
        let result = try await engine.describe(image: cgImage, prompt: "描述这张图片")
        // 去掉前缀后的内容应来自 NativeVisionEngine
        let fallbackContent = String(result.dropFirst("[MLXVisionEngine v1.6] ".count))
        XCTAssertFalse(fallbackContent.isEmpty, "去掉前缀后应有 NativeVisionEngine 的描述内容")
    }

    func testDescribeWithDifferentPrompt() async throws {
        let engine = MLXVisionEngine()
        let cgImage = makeTestCGImage(width: 16, height: 16)
        let result = try await engine.describe(image: cgImage, prompt: "识别文字")
        XCTAssertTrue(result.hasPrefix("[MLXVisionEngine v1.6]"),
                      "不同 prompt 也应带 [MLXVisionEngine v1.6] 前缀")
    }

    // MARK: - 辅助

    private func makeTestCGImage(width: Int = 1, height: Int = 1) -> CGImage {
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
        return context.makeImage()!
    }
}
