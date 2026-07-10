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

        XCTAssertEqual(provider.displayName, "端侧推理", "displayName 应为 '端侧推理'")
        XCTAssertEqual(provider.defaultChatModel, "llama-3.2-1b-instruct", "defaultChatModel 应为 'llama-3.2-1b-instruct'")
        XCTAssertEqual(provider.keychainAccount, "apikey-ondevice", "keychainAccount 应为 'apikey-ondevice'")
    }
}
