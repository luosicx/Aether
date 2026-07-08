import XCTest
@testable import AIBuilder

/// Day 15 Phase 5 Task 11: BFFProxyClient 单元测试
/// 验证 BFF 代理客户端的请求头注入（X-BFF-Token / X-Provider）、
/// SSE 流式解析、以及 HTTP 错误（401/429/5xx）通过通知分发 LLMError。
final class BFFProxyClientTests: XCTestCase {

    // MARK: - Mock URLProtocol（支持自定义响应头，用于 Retry-After 等场景）

    private final class MockURLProtocol: URLProtocol {
        static var responseData: Data?
        static var statusCode: Int = 200
        static var error: Error?
        static var lastRequest: URLRequest?
        /// 响应头（含 Content-Type / Retry-After 等）
        static var responseHeaders: [String: String] = ["Content-Type": "text/event-stream"]

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
                headerFields: Self.responseHeaders
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
            responseHeaders = ["Content-Type": "text/event-stream"]
        }
    }

    // MARK: - Fixture

    private let bffToken = "test-bff-token-123"
    private var mockSession: URLSession!
    private var client: BFFProxyClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        let bffConfig = BFFConfig(
            enabled: true,
            endpointURL: URL(string: "https://bff.example.com")!,
            userToken: bffToken,
            chatRateLimitPerMin: 20,
            embedRateLimitPerMin: 10
        )
        client = BFFProxyClient(provider: .deepseek, config: bffConfig, session: mockSession)
    }

    override func tearDown() {
        client = nil
        mockSession = nil
        super.tearDown()
    }

    /// 辅助：构造一条 user 消息
    private func makeMessages() -> [APIMessage] {
        [APIMessage(role: "user", content: "hi", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
    }

    /// 辅助：完全消费 chat 流，返回累积内容
    private func consume(stream: AsyncStream<String>) async -> String {
        var collected = ""
        for await chunk in stream {
            collected += chunk
        }
        return collected
    }

    // MARK: - 1. 请求头含 X-BFF-Token 且值为 config.userToken

    func testChatSendsXBFFTokenHeader() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200

        _ = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))

        let token = MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-BFF-Token")
        XCTAssertEqual(token, bffToken, "X-BFF-Token 应等于 config.userToken")
    }

    // MARK: - 2. 请求头含 X-Provider 且值为 provider.rawValue

    func testChatSendsXProviderHeader() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200

        _ = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))

        let provider = MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Provider")
        XCTAssertEqual(provider, "deepseek", "X-Provider 应等于 provider.rawValue")
    }

    // MARK: - 3. 请求头不含 Authorization（BFF 模式不携带 Bearer Token）

    func testChatDoesNotSendAuthorizationBearer() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200

        _ = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))

        let auth = MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertNil(auth, "BFF 模式不应发送 Authorization Header")
    }

    // MARK: - 4. SSE 流式内容累积

    func testChatStreamsSSEContent() async {
        let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let collected = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))
        XCTAssertEqual(collected, "Hello", "应累积 SSE content 为 'Hello'")
    }

    // MARK: - 5. 401 → LLMError.llmErrorOccurred("BFF Token 无效")

    func testChat401ThrowsLLMError() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 401

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        let collected = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))
        XCTAssertEqual(collected, "", "401 不应产生内容")

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .llmErrorOccurred(let msg) = capturedError else {
            XCTFail("期望 .llmErrorOccurred，实际：\(String(describing: capturedError))")
            return
        }
        XCTAssertTrue(msg.contains("BFF Token 无效"), "userMessage 应含 'BFF Token 无效'，实际：\(msg)")
    }

    // MARK: - 6. 429 + Retry-After: 60 → LLMError.rateLimited(retryAfter: 60)

    func testChat429ThrowsRateLimited() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 429
        MockURLProtocol.responseHeaders = [
            "Content-Type": "text/event-stream",
            "Retry-After": "60"
        ]

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        _ = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .rateLimited(let retryAfter) = capturedError else {
            XCTFail("期望 .rateLimited，实际：\(String(describing: capturedError))")
            return
        }
        XCTAssertEqual(retryAfter, 60, "retryAfter 应为 60")
    }

    // MARK: - 7. 5xx → LLMError.llmErrorOccurred("BFF 服务异常")

    func testChat5xxThrowsLLMError() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 500

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        _ = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .llmErrorOccurred(let msg) = capturedError else {
            XCTFail("期望 .llmErrorOccurred，实际：\(String(describing: capturedError))")
            return
        }
        XCTAssertTrue(msg.contains("BFF 服务异常"), "userMessage 应含 'BFF 服务异常'，实际：\(msg)")
    }
}
