import XCTest
@testable import Aether

/// RemoteConfig 单元测试：验证 Codable 编解码、默认值、featureFlags 嵌套结构。
final class RemoteConfigTests: XCTestCase {

    // MARK: - 默认值

    func testDefaultConfigValues() {
        let config = RemoteConfig.default
        XCTAssertEqual(config.defaultSystemPrompt, "你是一个有帮助的AI助手。")
        XCTAssertEqual(config.defaultProvider, "deepseek")
        XCTAssertEqual(config.defaultModel, "deepseek-chat")
        XCTAssertEqual(config.featureFlags, RemoteConfig.FeatureFlags.default)
        XCTAssertFalse(config.maintenanceMode)
        XCTAssertNil(config.forceUpdateMinVersion)
        XCTAssertEqual(config.configVersion, 1)
        XCTAssertNil(config.fetchedAt)
    }

    func testDefaultFeatureFlags() {
        let flags = RemoteConfig.FeatureFlags.default
        XCTAssertFalse(flags.ragEnabled)
        XCTAssertTrue(flags.toolsEnabled)
        XCTAssertFalse(flags.enableFallback)
    }

    // MARK: - Codable 编解码往返

    func testEncodeAndDecodeRoundTrip() throws {
        let original = RemoteConfig(
            defaultSystemPrompt: "测试提示词",
            defaultProvider: "qwen",
            defaultModel: "qwen-plus",
            featureFlags: RemoteConfig.FeatureFlags(ragEnabled: true, toolsEnabled: false, enableFallback: true),
            maintenanceMode: true,
            forceUpdateMinVersion: "2.0.0",
            configVersion: 5,
            fetchedAt: Date(timeIntervalSince1970: 1000000)
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RemoteConfig.self, from: data)
        XCTAssertEqual(decoded.defaultSystemPrompt, original.defaultSystemPrompt)
        XCTAssertEqual(decoded.defaultProvider, original.defaultProvider)
        XCTAssertEqual(decoded.defaultModel, original.defaultModel)
        XCTAssertEqual(decoded.featureFlags, original.featureFlags)
        XCTAssertEqual(decoded.maintenanceMode, original.maintenanceMode)
        XCTAssertEqual(decoded.forceUpdateMinVersion, original.forceUpdateMinVersion)
        XCTAssertEqual(decoded.configVersion, original.configVersion)
        XCTAssertNotNil(decoded.fetchedAt)
    }

    func testFeatureFlagsEncodeAndDecodeRoundTrip() throws {
        let original = RemoteConfig.FeatureFlags(ragEnabled: true, toolsEnabled: false, enableFallback: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteConfig.FeatureFlags.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - 缺可选字段解码

    func testDecodeWithMissingOptionalFields() throws {
        let json = """
        {
            "defaultSystemPrompt": "test",
            "defaultProvider": "qwen",
            "defaultModel": "model",
            "maintenanceMode": true,
            "configVersion": 3
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
        XCTAssertEqual(config.defaultSystemPrompt, "test")
        XCTAssertEqual(config.defaultProvider, "qwen")
        XCTAssertEqual(config.defaultModel, "model")
        XCTAssertTrue(config.maintenanceMode)
        XCTAssertEqual(config.configVersion, 3)
        XCTAssertNil(config.forceUpdateMinVersion, "缺省字段应回退到 nil")
        XCTAssertNil(config.fetchedAt, "fetchedAt 应为 nil")
        XCTAssertEqual(config.featureFlags, RemoteConfig.FeatureFlags.default, "featureFlags 缺失应回退到 default")
    }

    func testDecodeEmptyJSON() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
        XCTAssertEqual(config.defaultSystemPrompt, RemoteConfig.default.defaultSystemPrompt)
        XCTAssertEqual(config.defaultProvider, RemoteConfig.default.defaultProvider)
        XCTAssertEqual(config.defaultModel, RemoteConfig.default.defaultModel)
        XCTAssertEqual(config.featureFlags, RemoteConfig.default.featureFlags)
        XCTAssertFalse(config.maintenanceMode)
        XCTAssertNil(config.forceUpdateMinVersion)
        XCTAssertEqual(config.configVersion, RemoteConfig.default.configVersion)
        XCTAssertNil(config.fetchedAt)
    }

    // MARK: - featureFlags 嵌套结构

    func testFeatureFlagsDecodeWithMissingFields() throws {
        let json = """
        {
            "ragEnabled": true
        }
        """
        let data = json.data(using: .utf8)!
        let flags = try JSONDecoder().decode(RemoteConfig.FeatureFlags.self, from: data)
        XCTAssertTrue(flags.ragEnabled, "提供的字段应使用提供的值")
        XCTAssertTrue(flags.toolsEnabled, "缺失字段应使用默认值 true")
        XCTAssertFalse(flags.enableFallback, "缺失字段应使用默认值 false")
    }

    func testFeatureFlagsDecodeEmptyJSON() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let flags = try JSONDecoder().decode(RemoteConfig.FeatureFlags.self, from: data)
        XCTAssertEqual(flags, RemoteConfig.FeatureFlags.default, "空 JSON 应回退到全部默认值")
    }

    func testFeatureFlagsDecodeAllFields() throws {
        let json = """
        {
            "ragEnabled": true,
            "toolsEnabled": false,
            "enableFallback": true
        }
        """
        let data = json.data(using: .utf8)!
        let flags = try JSONDecoder().decode(RemoteConfig.FeatureFlags.self, from: data)
        XCTAssertTrue(flags.ragEnabled)
        XCTAssertFalse(flags.toolsEnabled)
        XCTAssertTrue(flags.enableFallback)
    }

    func testFeatureFlagsNestedInRemoteConfig() throws {
        let json = """
        {
            "featureFlags": {
                "ragEnabled": true,
                "toolsEnabled": false,
                "enableFallback": true
            }
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
        XCTAssertTrue(config.featureFlags.ragEnabled)
        XCTAssertFalse(config.featureFlags.toolsEnabled)
        XCTAssertTrue(config.featureFlags.enableFallback)
    }

    // MARK: - 特殊字段

    func testDecodeWithForceUpdateMinVersion() throws {
        let json = """
        {
            "forceUpdateMinVersion": "3.0.0"
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
        XCTAssertEqual(config.forceUpdateMinVersion, "3.0.0")
    }

    func testDecodeWithNullForceUpdateMinVersion() throws {
        let json = """
        {
            "forceUpdateMinVersion": null
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
        XCTAssertNil(config.forceUpdateMinVersion)
    }

    // MARK: - 成员逐一初始化器

    func testMemberwiseInitializerWithDefaults() {
        let config = RemoteConfig()
        XCTAssertEqual(config, RemoteConfig.default)
    }

    func testFeatureFlagsMemberwiseInitializerWithDefaults() {
        let flags = RemoteConfig.FeatureFlags()
        XCTAssertEqual(flags, RemoteConfig.FeatureFlags.default)
    }

    func testFeatureFlagsCustomValues() {
        let flags = RemoteConfig.FeatureFlags(ragEnabled: true, toolsEnabled: false, enableFallback: true)
        XCTAssertTrue(flags.ragEnabled)
        XCTAssertFalse(flags.toolsEnabled)
        XCTAssertTrue(flags.enableFallback)
    }

    func testFeatureFlagsPartialInitializer() {
        let flags = RemoteConfig.FeatureFlags(ragEnabled: true)
        XCTAssertTrue(flags.ragEnabled)
        XCTAssertTrue(flags.toolsEnabled, "未提供字段应使用默认值")
        XCTAssertFalse(flags.enableFallback, "未提供字段应使用默认值")
    }

    // MARK: - Equatable

    func testEquatableEquality() {
        let config1 = RemoteConfig(defaultSystemPrompt: "a", defaultProvider: "p", defaultModel: "m")
        let config2 = RemoteConfig(defaultSystemPrompt: "a", defaultProvider: "p", defaultModel: "m")
        XCTAssertEqual(config1, config2)
    }

    func testEquatableInequality() {
        let config1 = RemoteConfig(configVersion: 1)
        let config2 = RemoteConfig(configVersion: 2)
        XCTAssertNotEqual(config1, config2)
    }

    func testFeatureFlagsEquatable() {
        let flags1 = RemoteConfig.FeatureFlags(ragEnabled: true, toolsEnabled: false, enableFallback: true)
        let flags2 = RemoteConfig.FeatureFlags(ragEnabled: true, toolsEnabled: false, enableFallback: true)
        let flags3 = RemoteConfig.FeatureFlags(ragEnabled: false, toolsEnabled: false, enableFallback: true)
        XCTAssertEqual(flags1, flags2)
        XCTAssertNotEqual(flags1, flags3)
    }
}
