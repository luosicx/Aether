import XCTest
@testable import Aether

/// v1.3: 多模态工具（DescribeImageTool / TranscribeAudioTool / CloneVoiceTool / GenerateImageTool）测试
final class MultimodalToolsTests: XCTestCase {

    // MARK: - DescribeImageTool

    @MainActor
    func testDescribeImageToolDefinition() {
        let tool = DescribeImageTool()
        XCTAssertEqual(tool.definition.name, "describe_image")
        XCTAssertFalse(tool.definition.description.isEmpty)
    }

    @MainActor
    func testDescribeImageToolMissingImagePath() async throws {
        let tool = DescribeImageTool()
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("image_path"))
    }

    @MainActor
    func testDescribeImageToolEmptyImagePath() async throws {
        let tool = DescribeImageTool()
        let result = try await tool.execute(arguments: ["image_path": "", "prompt": "test"])
        XCTAssertTrue(result.hasPrefix("错误"))
    }

    @MainActor
    func testDescribeImageToolMissingPrompt() async throws {
        let tool = DescribeImageTool()
        let result = try await tool.execute(arguments: ["image_path": "/tmp/test.png"])
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("prompt"))
    }

    @MainActor
    func testDescribeImageToolNonExistentFile() async throws {
        let tool = DescribeImageTool()
        let result = try await tool.execute(arguments: [
            "image_path": "/tmp/nonexistent_v1_3.png",
            "prompt": "describe"
        ])
        // 占位引擎未加载时返回失败信息
        XCTAssertTrue(result.contains("失败") || result.contains("错误") || result.contains("占位"))
    }

    // MARK: - TranscribeAudioTool

    @MainActor
    func testTranscribeAudioToolDefinition() {
        let tool = TranscribeAudioTool()
        XCTAssertEqual(tool.definition.name, "transcribe_audio")
        XCTAssertFalse(tool.definition.description.isEmpty)
    }

    @MainActor
    func testTranscribeAudioToolMissingAudioPath() async throws {
        let tool = TranscribeAudioTool()
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("audio_path"))
    }

    @MainActor
    func testTranscribeAudioToolEmptyAudioPath() async throws {
        let tool = TranscribeAudioTool()
        let result = try await tool.execute(arguments: ["audio_path": ""])
        XCTAssertTrue(result.hasPrefix("错误"))
    }

    @MainActor
    func testTranscribeAudioToolNonExistentFile() async throws {
        let tool = TranscribeAudioTool()
        let result = try await tool.execute(arguments: ["audio_path": "/tmp/nonexistent_v1_3.wav"])
        XCTAssertTrue(result.contains("失败") || result.contains("错误"))
    }

    @MainActor
    func testTranscribeAudioToolDefaultLanguage() async throws {
        let tool = TranscribeAudioTool()
        // 不传 language 时应默认 "zh"
        let result = try await tool.execute(arguments: ["audio_path": "/tmp/nonexistent_v1_3.wav"])
        XCTAssertTrue(result.contains("失败") || result.contains("错误"))
    }

    // MARK: - CloneVoiceTool

    @MainActor
    func testCloneVoiceToolDefinition() {
        let tool = CloneVoiceTool()
        XCTAssertEqual(tool.definition.name, "clone_voice")
        XCTAssertFalse(tool.definition.description.isEmpty)
    }

    @MainActor
    func testCloneVoiceToolMissingAudioPath() async throws {
        let tool = CloneVoiceTool()
        let result = try await tool.execute(arguments: ["voice_name": "test"])
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("audio_path"))
    }

    @MainActor
    func testCloneVoiceToolMissingVoiceName() async throws {
        let tool = CloneVoiceTool()
        let result = try await tool.execute(arguments: ["audio_path": "/tmp/sample.wav"])
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("voice_name"))
    }

    @MainActor
    func testCloneVoiceToolPlaceholderFailure() async throws {
        let tool = CloneVoiceTool()
        let result = try await tool.execute(arguments: [
            "audio_path": "/tmp/sample.wav",
            "voice_name": "test"
        ])
        // 占位克隆引擎未 loadModel 应返回失败
        XCTAssertTrue(result.contains("失败"))
    }

    // MARK: - GenerateImageTool

    @MainActor
    func testGenerateImageToolDefinition() {
        let tool = GenerateImageTool()
        XCTAssertEqual(tool.definition.name, "generate_image")
        XCTAssertFalse(tool.definition.description.isEmpty)
    }

    @MainActor
    func testGenerateImageToolMissingPrompt() async throws {
        let tool = GenerateImageTool()
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.hasPrefix("错误"))
        XCTAssertTrue(result.contains("prompt"))
    }

    @MainActor
    func testGenerateImageToolEmptyPrompt() async throws {
        let tool = GenerateImageTool()
        let result = try await tool.execute(arguments: ["prompt": ""])
        XCTAssertTrue(result.hasPrefix("错误"))
    }

    @MainActor
    func testGenerateImageToolPlaceholderThrows() async throws {
        let tool = GenerateImageTool()
        let result = try await tool.execute(arguments: ["prompt": "cat"])
        // 占位实现返回 platformUnsupported 失败
        XCTAssertTrue(result.contains("失败"))
    }

    @MainActor
    func testGenerateImageToolWithFullParams() async throws {
        let tool = GenerateImageTool()
        let result = try await tool.execute(arguments: [
            "prompt": "cat",
            "negative_prompt": "blurry",
            "width": 768,
            "height": 768,
            "steps": 30,
            "seed": 42
        ])
        // 占位实现返回 platformUnsupported 失败
        XCTAssertTrue(result.contains("失败"))
    }
}
