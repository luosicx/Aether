import XCTest
@testable import Aether

/// BFFConfig 单元测试
/// 覆盖默认值、JSON 编解码往返、字段读写、UserDefaults 缓存键。
final class BFFConfigTests: XCTestCase {

    // MARK: - 默认值

    /// 默认配置 enabled 应为 false
    func testDefaultEnabledIsFalse() {
        let config = BFFConfig.default
        XCTAssertFalse(config.enabled, "默认 enabled 应为 false")
    }

    /// 默认 endpointURL 应为占位地址
    func testDefaultEndpointURL() {
        let config = BFFConfig.default
        XCTAssertEqual(config.endpointURL.absoluteString,
                       "https://aether-bff.example.com",
                       "默认 endpointURL 应为占位地址")
    }

    /// 默认 userToken 应为空字符串
    func testDefaultUserTokenIsEmpty() {
        let config = BFFConfig.default
        XCTAssertEqual(config.userToken, "", "默认 userToken 应为空字符串")
    }

    /// 默认 chatRateLimitPerMin 应为 20
    func testDefaultChatRateLimitPerMin() {
        let config = BFFConfig.default
        XCTAssertEqual(config.chatRateLimitPerMin, 20, "默认 chatRateLimitPerMin 应为 20")
    }

    /// 默认 embedRateLimitPerMin 应为 10
    func testDefaultEmbedRateLimitPerMin() {
        let config = BFFConfig.default
        XCTAssertEqual(config.embedRateLimitPerMin, 10, "默认 embedRateLimitPerMin 应为 10")
    }

    /// BFFConfig() 无参构造应与 .default 一致
    func testParameterlessInitMatchesDefault() {
        let config = BFFConfig()
        XCTAssertEqual(config, BFFConfig.default, "BFFConfig() 应与 BFFConfig.default 相等")
    }

    // MARK: - JSON 编解码往返

    /// 默认配置 JSON 编解码往返应保持一致
    func testDefaultConfigRoundTrip() throws {
        let original = BFFConfig.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BFFConfig.self, from: data)
        XCTAssertEqual(decoded, original, "默认配置编解码往返后应相等")
    }

    /// 自定义配置 JSON 编解码往返应保持一致
    func testCustomConfigRoundTrip() throws {
        var config = BFFConfig()
        config.enabled = true
        config.endpointURL = URL(string: "https://my-bff.gateway.com")!
        config.userToken = "user-token-xyz-789"
        config.chatRateLimitPerMin = 60
        config.embedRateLimitPerMin = 30

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BFFConfig.self, from: data)

        XCTAssertEqual(decoded.enabled, true, "往返后 enabled 应为 true")
        XCTAssertEqual(decoded.endpointURL.absoluteString, "https://my-bff.gateway.com",
                       "往返后 endpointURL 应保持一致")
        XCTAssertEqual(decoded.userToken, "user-token-xyz-789", "往返后 userToken 应保持一致")
        XCTAssertEqual(decoded.chatRateLimitPerMin, 60, "往返后 chatRateLimitPerMin 应为 60")
        XCTAssertEqual(decoded.embedRateLimitPerMin, 30, "往返后 embedRateLimitPerMin 应为 30")
        XCTAssertEqual(decoded, config, "往返后整体应相等")
    }

    /// 从部分 JSON（仅含 enabled 字段）解码，缺失字段时合成 Codable 会抛出 keyNotFound 错误
    /// （合成的 Decodable 不使用属性默认值填充缺失 key，需显式 decodeIfPresent 才支持）
    func testDecodePartialJSONThrowsOnMissingKeys() {
        // JSON 仅含 enabled=true，其余字段缺失
        let json = #"{"enabled":true}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BFFConfig.self, from: json),
                             "部分 JSON 缺失 key 时应抛出 DecodingError") { error in
            XCTAssertTrue(error is DecodingError, "应为 DecodingError 类型")
        }
    }

    /// 从空 JSON 对象解码，所有 key 缺失时应抛出解码错误
    func testDecodeEmptyJSONObjectThrowsOnMissingKeys() {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BFFConfig.self, from: json),
                             "空 JSON 对象缺失所有 key 时应抛出 DecodingError") { error in
            XCTAssertTrue(error is DecodingError, "应为 DecodingError 类型")
        }
    }

    // MARK: - 字段读写

    /// 修改各字段后应反映新值
    func testFieldMutation() {
        var config = BFFConfig()
        config.enabled = true
        config.endpointURL = URL(string: "https://new.endpoint")!
        config.userToken = "new-token"
        config.chatRateLimitPerMin = 100
        config.embedRateLimitPerMin = 50

        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.endpointURL.absoluteString, "https://new.endpoint")
        XCTAssertEqual(config.userToken, "new-token")
        XCTAssertEqual(config.chatRateLimitPerMin, 100)
        XCTAssertEqual(config.embedRateLimitPerMin, 50)
    }

    /// endpoint/token 边界值：空字符串 token、0 限流值
    func testEndpointAndTokenBoundaryValues() throws {
        var config = BFFConfig()
        config.userToken = ""
        config.chatRateLimitPerMin = 0
        config.embedRateLimitPerMin = 0

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BFFConfig.self, from: data)

        XCTAssertEqual(decoded.userToken, "", "空字符串 token 应可往返")
        XCTAssertEqual(decoded.chatRateLimitPerMin, 0, "限流值 0 应可往返")
        XCTAssertEqual(decoded.embedRateLimitPerMin, 0, "限流值 0 应可往返")
    }

    // MARK: - 缓存键

    /// userDefaultsKey 应为固定字符串常量
    func testUserDefaultsKey() {
        XCTAssertEqual(BFFConfig.userDefaultsKey, "bff_config_cache",
                       "userDefaultsKey 应为 'bff_config_cache'")
    }

    /// 每次 default 应返回相同的实例（static let 单例语义）
    func testDefaultIsStableSingleton() {
        let a = BFFConfig.default
        let b = BFFConfig.default
        XCTAssertEqual(a, b, ".default 多次访问应返回相等配置")
    }
}
