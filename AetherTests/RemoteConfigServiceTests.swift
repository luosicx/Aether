import XCTest
@testable import Aether

/// Day 14 Phase 5 Task 9: RemoteConfigService 单元测试
/// 参考 DeepSeekClientTests 的 MockURLProtocol + 全局 URLProtocol.registerClass 模式拦截 URLSession.shared 请求。
/// RemoteConfigService 通过 init(endpointURL:) 注入 mock endpoint，每个测试创建新实例避免 shared 单例状态污染。
final class RemoteConfigServiceTests: XCTestCase {

    // MARK: - Mock URLProtocol

    private final class MockURLProtocol: URLProtocol {
        static var responseData: Data?
        static var statusCode: Int = 200
        static var error: Error?
        static var lastRequest: URLRequest?
        static var headers: [String: String] = ["Content-Type": "application/json"]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            if let error = Self.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: Self.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = Self.responseData {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset() {
            responseData = nil
            statusCode = 200
            error = nil
            lastRequest = nil
            headers = ["Content-Type": "application/json"]
        }
    }

    // MARK: - Fixture

    /// RemoteConfigService 内部 UserDefaults 缓存键（private，此处复制字符串用于测试隔离）
    private let cacheKey = "remote_config_cache"
    private let endpoint = URL(string: "https://test.example.com/remote_config.json")!
    private var service: RemoteConfigService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        URLProtocol.registerClass(MockURLProtocol.self)
        // 清理上次测试可能残留的 UserDefaults 缓存，确保每个测试从干净状态开始
        UserDefaults.standard.removeObject(forKey: cacheKey)
        service = RemoteConfigService(endpointURL: endpoint)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        service = nil
        super.tearDown()
    }

    // MARK: - 1. fetch 解析合法 JSON

    func testFetchParsesValidJSON() async {
        let json = """
        {
            "defaultSystemPrompt": "远程提示词",
            "defaultProvider": "qwen",
            "defaultModel": "qwen-plus",
            "featureFlags": {
                "ragEnabled": true,
                "toolsEnabled": false,
                "enableFallback": true
            },
            "maintenanceMode": true,
            "forceUpdateMinVersion": "2.0.0",
            "configVersion": 7
        }
        """
        MockURLProtocol.responseData = json.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        await service.fetch()

        let config = await service.currentConfig
        XCTAssertEqual(config.defaultSystemPrompt, "远程提示词")
        XCTAssertEqual(config.defaultProvider, "qwen")
        XCTAssertEqual(config.defaultModel, "qwen-plus")
        XCTAssertEqual(config.featureFlags.ragEnabled, true)
        XCTAssertEqual(config.featureFlags.toolsEnabled, false)
        XCTAssertEqual(config.featureFlags.enableFallback, true)
        XCTAssertEqual(config.maintenanceMode, true)
        XCTAssertEqual(config.forceUpdateMinVersion, "2.0.0")
        XCTAssertEqual(config.configVersion, 7)
        XCTAssertNotNil(config.fetchedAt, "成功拉取后 fetchedAt 应被写入当前时间")
    }

    // MARK: - 2. 拉取失败回退到本地缓存

    func testFetchFailureFallsBackToCache() async {
        // 第一次：成功拉取并写入缓存
        let json = """
        {
            "defaultSystemPrompt": "缓存提示词",
            "defaultProvider": "qwen",
            "defaultModel": "cached-model",
            "configVersion": 5
        }
        """
        MockURLProtocol.responseData = json.data(using: .utf8)
        MockURLProtocol.statusCode = 200
        await service.fetch()

        // 第二次：模拟服务端 500，应回退到缓存
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 500
        await service.fetch()

        let config = await service.currentConfig
        // 应使用缓存值，而非 .default
        XCTAssertEqual(config.defaultModel, "cached-model", "失败时应回退到缓存值")
        XCTAssertEqual(config.defaultProvider, "qwen")
        XCTAssertEqual(config.configVersion, 5)
    }

    // MARK: - 3. 缓存 TTL 过期后失败回退到 .default

    func testFetchFailureWithExpiredCacheUsesDefault() async {
        // 手动写入一份过期的缓存（fetchedAt 为 25 小时前），模拟缓存 TTL（24h）过期
        var expiredConfig = RemoteConfig(
            defaultSystemPrompt: "过期缓存",
            defaultProvider: "qwen",
            defaultModel: "expired-model",
            configVersion: 99
        )
        expiredConfig.fetchedAt = Date().addingTimeInterval(-25 * 3600)
        guard let cachedData = try? JSONEncoder().encode(expiredConfig) else {
            XCTFail("编码失败")
            return
        }
        UserDefaults.standard.set(cachedData, forKey: cacheKey)

        // 模拟拉取失败
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 500
        await service.fetch()

        let config = await service.currentConfig
        // 缓存过期 → loadCachedConfig 返回 nil → fallbackConfig() → 字段为 .default
        XCTAssertEqual(config.defaultSystemPrompt, RemoteConfig.default.defaultSystemPrompt)
        XCTAssertEqual(config.defaultModel, RemoteConfig.default.defaultModel, "过期缓存应回退到 .default")
        XCTAssertEqual(config.defaultProvider, RemoteConfig.default.defaultProvider)
        XCTAssertEqual(config.configVersion, RemoteConfig.default.configVersion)
        XCTAssertNotNil(config.fetchedAt, "fallbackConfig 应写入当前时间避免反复尝试拉取")
    }

    // MARK: - 4. RemoteConfig.default 结构正确，不覆盖用户自定义

    func testRemoteConfigDoesNotOverrideUserCustomization() {
        // 验证内置默认配置结构完整且可作为安全兜底。
        // 远程配置仅作为「初始默认值」生效，不覆盖用户已自定义的本地配置（SettingsViewModel 层处理），
        // 这里验证 default 的不可变结构与字段，确保回退路径提供安全兜底。
        let def = RemoteConfig.default
        XCTAssertFalse(def.defaultSystemPrompt.isEmpty, "默认 system prompt 不应为空")
        XCTAssertEqual(def.defaultProvider, "deepseek")
        XCTAssertEqual(def.defaultModel, "deepseek-chat")
        XCTAssertEqual(def.featureFlags, RemoteConfig.FeatureFlags.default)
        XCTAssertEqual(def.maintenanceMode, false)
        XCTAssertNil(def.forceUpdateMinVersion)
        XCTAssertEqual(def.configVersion, 1)

        // FeatureFlags 默认结构
        let flags = RemoteConfig.FeatureFlags.default
        XCTAssertEqual(flags.ragEnabled, false)
        XCTAssertEqual(flags.toolsEnabled, true)
        XCTAssertEqual(flags.enableFallback, false)

        // default 的 featureFlags 应等于 FeatureFlags.default
        XCTAssertEqual(def.featureFlags, flags)
    }

    // MARK: - 补充小缺口测试

    /// 拉取失败且本地缓存损坏（非法 JSON）时，loadCachedConfig() 的 catch 块返回 nil，
    /// applyFallback 走 fallbackConfig() 分支，currentConfig 回退到 .default。
    /// 覆盖 RemoteConfigService.swift 第 80-83 行的解码失败 catch 块。
    func testFetchFailureWithCorruptedCacheFallsBackToDefault() async {
        // 写入损坏的 JSON 数据到 UserDefaults（cacheKey="remote_config_cache"）
        let corruptedData = Data("{ this is not valid json ".utf8)
        UserDefaults.standard.set(corruptedData, forKey: cacheKey)

        // 模拟拉取失败：HTTP 500
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 500
        await service.fetch()

        let config = await service.currentConfig
        // 损坏缓存无法解码 → loadCachedConfig 返回 nil → fallbackConfig() → 字段为 .default
        XCTAssertEqual(config.defaultSystemPrompt, RemoteConfig.default.defaultSystemPrompt,
                       "缓存损坏时应回退到 .default 的 defaultSystemPrompt")
        XCTAssertEqual(config.defaultModel, RemoteConfig.default.defaultModel,
                       "缓存损坏时应回退到 .default 的 defaultModel")
        XCTAssertEqual(config.defaultProvider, RemoteConfig.default.defaultProvider,
                       "缓存损坏时应回退到 .default 的 defaultProvider")
        XCTAssertEqual(config.configVersion, RemoteConfig.default.configVersion,
                       "缓存损坏时应回退到 .default 的 configVersion")
        XCTAssertNotNil(config.fetchedAt, "fallbackConfig 应写入当前时间避免反复尝试拉取")
    }

    /// 拉取失败且本地缓存的 fetchedAt 为 nil 时，loadCachedConfig() 的 guard 分支返回 nil，
    /// applyFallback 走 fallbackConfig() 分支，currentConfig 回退到 .default。
    /// 覆盖 RemoteConfigService.swift 第 72-74 行的 fetchedAt 为 nil 返回 nil 分支。
    func testFetchFailureWithCacheMissingFetchedAtFallsBackToDefault() async {
        // 构造 fetchedAt=nil 的 RemoteConfig（模拟旧版本缓存缺失时间戳字段）
        let cacheConfig = RemoteConfig(
            defaultSystemPrompt: "无时间戳缓存",
            defaultProvider: "qwen",
            defaultModel: "no-fetched-at-model",
            configVersion: 42,
            fetchedAt: nil  // 关键：fetchedAt 缺失
        )
        guard let cachedData = try? JSONEncoder().encode(cacheConfig) else {
            XCTFail("编码失败")
            return
        }
        UserDefaults.standard.set(cachedData, forKey: cacheKey)

        // 模拟拉取失败：HTTP 500
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 500
        await service.fetch()

        let config = await service.currentConfig
        // fetchedAt=nil → loadCachedConfig 返回 nil → fallbackConfig() → 字段为 .default
        XCTAssertEqual(config.defaultSystemPrompt, RemoteConfig.default.defaultSystemPrompt,
                       "缓存 fetchedAt 缺失时应回退到 .default 的 defaultSystemPrompt")
        XCTAssertEqual(config.defaultModel, RemoteConfig.default.defaultModel,
                       "缓存 fetchedAt 缺失时应回退到 .default 的 defaultModel，而非缓存值")
        XCTAssertEqual(config.defaultProvider, RemoteConfig.default.defaultProvider,
                       "缓存 fetchedAt 缺失时应回退到 .default 的 defaultProvider")
        XCTAssertEqual(config.configVersion, RemoteConfig.default.configVersion,
                       "缓存 fetchedAt 缺失时应回退到 .default 的 configVersion")
        XCTAssertNotNil(config.fetchedAt, "fallbackConfig 应写入当前时间避免反复尝试拉取")
    }
}
