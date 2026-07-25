import XCTest
@testable import Aether

/// v1.3: OCRTool 跨平台改造测试
///
/// 验证：
/// - 工具定义正确（name / description / parameters）
/// - iOS / iPadOS / macOS 三端可用
/// - 不传 image_path 时 iOS 返回错误提示，macOS 调用 ScreenshotTool
/// - 传入不存在的路径返回错误
final class OCRCrossPlatformTests: XCTestCase {

    func testOCRToolDefinitionName() {
        let tool = OCRTool()
        XCTAssertEqual(tool.definition.name, "extract_text_from_image")
    }

    func testOCRToolDefinitionDescriptionMentionsCrossPlatform() {
        let tool = OCRTool()
        XCTAssertTrue(tool.definition.description.contains("跨平台"), "description 应提及跨平台")
    }

    func testOCRToolDefinitionParametersContainsImagePath() {
        let tool = OCRTool()
        let properties = tool.definition.parameters["properties"] as? [String: Any] ?? [:]
        XCTAssertNotNil(properties["image_path"], "parameters 应包含 image_path")
    }

    @MainActor
    func testExecuteWithNonExistentImagePath() async throws {
        let tool = OCRTool()
        let result = try await tool.execute(arguments: ["image_path": "/tmp/aether_v1_3_nonexistent.png"])
        XCTAssertTrue(result.hasPrefix("错误"), "不存在的图片应返回错误")
        XCTAssertTrue(result.contains("无法加载图片"))
    }

    @MainActor
    func testExecuteWithEmptyImagePath() async throws {
        let tool = OCRTool()
        let result = try await tool.execute(arguments: ["image_path": ""])
        // 空路径走不传 image_path 分支
        #if os(macOS)
        // macOS 调用 ScreenshotTool，可能因权限失败但应返回字符串
        XCTAssertFalse(result.isEmpty)
        #else
        // iOS / iPadOS 返回要求传入 image_path 的错误
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("image_path"))
        #endif
    }

    @MainActor
    func testExecuteWithoutImagePath() async throws {
        let tool = OCRTool()
        let result = try await tool.execute(arguments: [:])
        #if os(macOS)
        // macOS 调用 ScreenshotTool（可能因权限失败，但应返回字符串）
        XCTAssertFalse(result.isEmpty)
        #else
        // iOS / iPadOS 返回错误提示
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("iOS"))
        #endif
    }

    @MainActor
    func testExecuteWithNonExistentImagePathReturnsLoadError() async throws {
        let tool = OCRTool()
        let result = try await tool.execute(arguments: ["image_path": "/tmp/aether_v1_3_nonexistent_\(UUID().uuidString).png"])
        XCTAssertTrue(result.contains("无法加载图片"), "应返回加载图片错误")
    }

    // MARK: - 跨平台编译验证

    /// 此测试本身用于验证 OCRTool 在 iOS / macOS 双端均可编译
    func testOCRToolInstantiableOnAllPlatforms() {
        let tool = OCRTool()
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool.definition.name, "extract_text_from_image")
    }
}
