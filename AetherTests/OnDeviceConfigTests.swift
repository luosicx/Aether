import XCTest
@testable import Aether

/// Day 16: 端侧推理配置 + ModelProvider.onDevice 元信息单元测试。
final class OnDeviceConfigTests: XCTestCase {

    // MARK: - 1. 默认配置

    func testDefaultConfig() {
        let config = OnDeviceConfig.default

        XCTAssertEqual(config.enabled, false, "默认 enabled 应为 false")
        XCTAssertEqual(config.autoSwitchOnNetworkLoss, true, "默认 autoSwitchOnNetworkLoss 应为 true")
        XCTAssertEqual(config.maxTokens, 512, "默认 maxTokens 应为 512")
        XCTAssertEqual(config.temperature, 0.7, "默认 temperature 应为 0.7")
        XCTAssertEqual(config.modelName, "Llama-3.2-1B-Instruct-Q4_K_M", "默认 modelName 应为 Llama-3.2-1B-Instruct-Q4_K_M")
    }

    // MARK: - 2. Codable 往返

    func testCodableRoundTrip() throws {
        var original = OnDeviceConfig.default
        original.enabled = true
        original.maxTokens = 1024
        original.temperature = 0.5
        original.modelName = "CustomModel"
        original.expectedSHA256 = "abc123def456"
        original.autoSwitchOnNetworkLoss = false

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OnDeviceConfig.self, from: data)

        XCTAssertEqual(decoded, original, "Codable 往返后各字段应一致")
    }

    // MARK: - 3. ModelProvider.onDevice 元信息

    func testModelProviderOnDeviceCase() {
        let provider = ModelProvider.onDevice

        XCTAssertEqual(provider.displayName, NSLocalizedString("端侧推理", comment: ""), "displayName 应为 '端侧推理'")
        XCTAssertEqual(provider.defaultChatModel, "llama-3.2-1b-instruct", "defaultChatModel 应为 'llama-3.2-1b-instruct'")
        XCTAssertEqual(provider.keychainAccount, "apikey-ondevice", "keychainAccount 应为 'apikey-ondevice'")
    }

    // MARK: - 补充小缺口测试

    /// 验证 OnDeviceConfig.default 的可选字段与 URL 字段。
    /// 覆盖 OnDeviceConfig.swift 中 modelPath、downloadURL、mirrorDownloadURL、expectedSHA256、downloadSource 的默认值断言。
    func testDefaultConfigOptionalAndURLFields() {
        let config = OnDeviceConfig.default

        // modelPath 默认应为 nil（下载完成后回写）
        XCTAssertNil(config.modelPath, "默认 modelPath 应为 nil")

        // downloadURL 应为非空 https URL
        XCTAssertEqual(config.downloadURL.scheme, "https", "默认 downloadURL scheme 应为 https")
        XCTAssertFalse(config.downloadURL.absoluteString.isEmpty, "默认 downloadURL 不应为空")
        XCTAssertTrue(config.downloadURL.absoluteString.contains("huggingface.co"),
                      "默认 downloadURL 应指向 HuggingFace CDN")

        // mirrorDownloadURL 应为非空 https URL
        XCTAssertEqual(config.mirrorDownloadURL.scheme, "https", "默认 mirrorDownloadURL scheme 应为 https")
        XCTAssertFalse(config.mirrorDownloadURL.absoluteString.isEmpty, "默认 mirrorDownloadURL 不应为空")
        XCTAssertTrue(config.mirrorDownloadURL.absoluteString.contains("modelscope.cn"),
                      "默认 mirrorDownloadURL 应指向 ModelScope 镜像")

        // expectedSHA256 默认应为空字符串
        XCTAssertEqual(config.expectedSHA256, "", "默认 expectedSHA256 应为空字符串")

        // downloadSource 默认应为 .domestic
        XCTAssertEqual(config.downloadSource, .domestic, "默认 downloadSource 应为 .domestic")
    }

    /// 验证 OnDeviceConfig.default 多次访问返回相等配置（static let 单例语义）。
    func testDefaultConfigStability() {
        let a = OnDeviceConfig.default
        let b = OnDeviceConfig.default
        XCTAssertEqual(a, b, ".default 多次访问应返回相等配置")
        XCTAssertEqual(a.modelPath, b.modelPath)
        XCTAssertEqual(a.downloadURL, b.downloadURL)
        XCTAssertEqual(a.mirrorDownloadURL, b.mirrorDownloadURL)
        XCTAssertEqual(a.expectedSHA256, b.expectedSHA256)
        XCTAssertEqual(a.downloadSource, b.downloadSource)
    }

    /// 验证设置 modelPath 为 file URL 后 Codable 往返应保持一致。
    func testCodableRoundTripWithModelPath() throws {
        var original = OnDeviceConfig.default
        let customModelPath = URL(fileURLWithPath: "/tmp/aether/model.safetensors")
        original.modelPath = customModelPath
        original.enabled = true

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OnDeviceConfig.self, from: data)

        XCTAssertEqual(decoded.modelPath, customModelPath, "往返后 modelPath 应保持一致")
        XCTAssertEqual(decoded, original, "往返后整体应相等")
    }
}
