import XCTest
@testable import AetherSDK
import AetherFoundation
import AetherServices

/// Task 24 阶段 1: AetherConfig 单元测试
final class AetherConfigTests: XCTestCase {

    // MARK: - 基础初始化

    func testInitWithRequiredFields() {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test-123")
        XCTAssertEqual(config.provider, .deepSeek)
        XCTAssertEqual(config.apiKey, "sk-test-123")
        XCTAssertNil(config.baseURL)
        XCTAssertNil(config.cache)
        XCTAssertNil(config.rag)
        XCTAssertNil(config.rateLimit)
        XCTAssertEqual(config.auth, .defaultConfig)
        XCTAssertEqual(config.auth, .apiKey)
        XCTAssertEqual(config.retryPolicy, .defaultPolicy)
    }

    func testInitWithAllFields() {
        let config = AetherConfig(
            provider: .qwen,
            apiKey: "sk-qwen",
            baseURL: URL(string: "https://custom.example.com"),
            cache: CacheConfig(enabled: true, ttl: 1800, similarityThreshold: 0.95, maxCapacity: 50),
            rag: RAGConfig(knowledgeBaseID: "kb-1", topK: 10),
            rateLimit: RateLimitConfig(qps: 5, maxConcurrent: 2),
            auth: .oauth(OAuthCredential(accessToken: "token-xyz")),
            retryPolicy: RetryPolicy(maxAttempts: 5, initialDelay: 0.5, backoffMultiplier: 3.0)
        )
        XCTAssertEqual(config.provider, .qwen)
        XCTAssertEqual(config.cache?.ttl, 1800)
        XCTAssertEqual(config.cache?.similarityThreshold, 0.95)
        XCTAssertEqual(config.rag?.knowledgeBaseID, "kb-1")
        XCTAssertEqual(config.rag?.topK, 10)
        XCTAssertEqual(config.rateLimit?.qps, 5)
        XCTAssertEqual(config.retryPolicy?.maxAttempts, 5)
        if case .oauth(let cred) = config.auth {
            XCTAssertEqual(cred.accessToken, "token-xyz")
        } else {
            XCTFail("auth 应为 .oauth")
        }
    }

    // MARK: - validate()

    func testValidateEmptyApiKeyFails() {
        let config = AetherConfig(provider: .deepSeek, apiKey: "")
        let reason = config.validate()
        XCTAssertNotNil(reason)
        XCTAssertEqual(reason, "apiKey 不能为空")
    }

    func testValidateOnDeviceAllowsEmptyApiKey() {
        let config = AetherConfig(provider: .onDevice, apiKey: "")
        let reason = config.validate()
        XCTAssertNil(reason, "onDevice 应允许空 apiKey")
    }

    func testValidateInvalidSimilarityThreshold() {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-x",
            cache: CacheConfig(enabled: true, ttl: 3600, similarityThreshold: 1.5, maxCapacity: 100)
        )
        let reason = config.validate()
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("similarityThreshold") == true)
    }

    func testValidateInvalidTopK() {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-x",
            rag: RAGConfig(knowledgeBaseID: "kb", topK: 0)
        )
        let reason = config.validate()
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("topK") == true)
    }

    func testValidateInvalidRateLimit() {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-x",
            rateLimit: RateLimitConfig(qps: 0, maxConcurrent: 4)
        )
        let reason = config.validate()
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("qps") == true)
    }

    func testValidateValidConfigReturnsNil() {
        let config = AetherConfig(
            provider: .deepSeek,
            apiKey: "sk-valid",
            cache: CacheConfig.defaultConfig,
            rag: RAGConfig(knowledgeBaseID: "kb-1"),
            rateLimit: RateLimitConfig.defaultConfig
        )
        XCTAssertNil(config.validate())
    }

    // MARK: - 默认值

    func testCacheConfigDefaults() {
        let cache = CacheConfig.defaultConfig
        XCTAssertTrue(cache.enabled)
        XCTAssertEqual(cache.ttl, 3600)
        XCTAssertEqual(cache.similarityThreshold, 0.92, accuracy: 0.001)
        XCTAssertEqual(cache.maxCapacity, 100)
    }

    func testRateLimitConfigDefaults() {
        let rl = RateLimitConfig.defaultConfig
        XCTAssertEqual(rl.qps, 10)
        XCTAssertEqual(rl.maxConcurrent, 4)
    }

    // MARK: - AetherProvider

    func testProviderAllCases() {
        XCTAssertEqual(AetherProvider.allCases.count, 4)
        XCTAssertTrue(AetherProvider.allCases.contains(.deepSeek))
        XCTAssertTrue(AetherProvider.allCases.contains(.qwen))
        XCTAssertTrue(AetherProvider.allCases.contains(.bff))
        XCTAssertTrue(AetherProvider.allCases.contains(.onDevice))
    }

    func testProviderInternalMapping() {
        XCTAssertEqual(AetherProvider.deepSeek.internalProvider, .deepseek)
        XCTAssertEqual(AetherProvider.qwen.internalProvider, .qwen)
        XCTAssertEqual(AetherProvider.bff.internalProvider, .deepseek)
        XCTAssertEqual(AetherProvider.onDevice.internalProvider, .onDevice)
    }

    // MARK: - Sendable / Equatable

    func testConfigIsSendable() {
        let config = AetherConfig(provider: .deepSeek, apiKey: "sk-test")
        let closure: @Sendable () -> AetherProvider = { config.provider }
        XCTAssertEqual(closure(), .deepSeek)
    }

    func testConfigEquality() {
        let c1 = AetherConfig(provider: .deepSeek, apiKey: "sk-1")
        let c2 = AetherConfig(provider: .deepSeek, apiKey: "sk-1")
        let c3 = AetherConfig(provider: .qwen, apiKey: "sk-1")
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c1, c3)
    }
}
