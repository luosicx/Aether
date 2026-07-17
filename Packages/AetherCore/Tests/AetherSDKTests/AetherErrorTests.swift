import XCTest
@testable import AetherSDK
import AetherFoundation

/// Task 24 阶段 1: AetherError 公共枚举测试
final class AetherErrorTests: XCTestCase {

    // MARK: - 8 种错误类型

    func testAuthFailed() {
        let error = AetherError.authFailed(reason: "invalid token")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("鉴权失败") == true)
        XCTAssertFalse(error.isRetryable)
    }

    func testRateLimited() {
        let error = AetherError.rateLimited(retryAfter: 30)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("30") == true)
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError() {
        let error = AetherError.providerError(code: 500, message: "internal error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("500") == true)
        XCTAssertFalse(error.isRetryable)
    }

    func testProviderError503Retryable() {
        XCTAssertTrue(AetherError.providerError(code: 503, message: "").isRetryable)
        XCTAssertTrue(AetherError.providerError(code: 502, message: "").isRetryable)
        XCTAssertTrue(AetherError.providerError(code: 504, message: "").isRetryable)
    }

    func testNetworkUnreachable() {
        let error = AetherError.networkUnreachable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("网络") == true)
        XCTAssertTrue(error.isRetryable)
    }

    func testToolExecutionFailed() {
        let error = AetherError.toolExecutionFailed(name: "calc", errorDescription: "div by zero")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("calc") == true)
        XCTAssertFalse(error.isRetryable)
    }

    func testRagRetrievalFailed() {
        let error = AetherError.ragRetrievalFailed(reason: "no docs")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("知识库") == true)
        XCTAssertFalse(error.isRetryable)
    }

    func testInvalidConfig() {
        let error = AetherError.invalidConfig(reason: "missing apiKey")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("配置无效") == true)
        XCTAssertFalse(error.isRetryable)
    }

    func testOnDeviceInferenceFailed() {
        let onDeviceErr = OnDeviceError.insufficientMemory
        let error = AetherError.onDeviceInferenceFailed(error: onDeviceErr)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.isRetryable)
    }

    // MARK: - 从 LLMError 构造

    func testFromLLMErrorNetwork() {
        let llmErr = LLMError.networkError("disconnected")
        let aetherErr = AetherError.from(llmErr)
        if case .networkUnreachable = aetherErr {
            // 预期
        } else {
            XCTFail("期望 networkUnreachable，实际：\(aetherErr)")
        }
    }

    func testFromLLMErrorApiKeyMissing() {
        let llmErr = LLMError.apiKeyMissing
        let aetherErr = AetherError.from(llmErr)
        if case .authFailed = aetherErr {
            // 预期
        } else {
            XCTFail("期望 authFailed，实际：\(aetherErr)")
        }
    }

    func testFromLLMErrorApiKeyInvalid() {
        let llmErr = LLMError.apiKeyInvalid
        let aetherErr = AetherError.from(llmErr)
        if case .authFailed = aetherErr {
            // 预期
        } else {
            XCTFail("期望 authFailed，实际：\(aetherErr)")
        }
    }

    func testFromLLMError401() {
        let llmErr = LLMError.apiError(code: 401, message: "unauthorized")
        let aetherErr = AetherError.from(llmErr)
        if case .authFailed = aetherErr {
            // 预期
        } else {
            XCTFail("期望 authFailed，实际：\(aetherErr)")
        }
    }

    func testFromLLMError429() {
        let llmErr = LLMError.apiError(code: 429, message: "too many requests")
        let aetherErr = AetherError.from(llmErr)
        if case .rateLimited = aetherErr {
            // 预期
        } else {
            XCTFail("期望 rateLimited，实际：\(aetherErr)")
        }
    }

    func testFromLLMError500() {
        let llmErr = LLMError.apiError(code: 500, message: "server error")
        let aetherErr = AetherError.from(llmErr)
        if case .providerError(let code, _) = aetherErr {
            XCTAssertEqual(code, 500)
        } else {
            XCTFail("期望 providerError，实际：\(aetherErr)")
        }
    }

    func testFromLLMErrorTimeout() {
        let llmErr = LLMError.timeout
        let aetherErr = AetherError.from(llmErr)
        if case .networkUnreachable = aetherErr {
            // 预期
        } else {
            XCTFail("期望 networkUnreachable，实际：\(aetherErr)")
        }
    }

    func testFromLLMErrorRateLimited() {
        let llmErr = LLMError.rateLimited(retryAfter: 10)
        let aetherErr = AetherError.from(llmErr)
        if case .rateLimited(let retryAfter) = aetherErr {
            XCTAssertEqual(retryAfter, 10)
        } else {
            XCTFail("期望 rateLimited，实际：\(aetherErr)")
        }
    }

    // MARK: - Sendable

    func testErrorIsSendable() {
        let error = AetherError.networkUnreachable
        let closure: @Sendable () -> Bool = { error.isRetryable }
        XCTAssertTrue(closure())
    }
}
