import XCTest
@testable import Aether

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
            endpointURL: URL(string: "https://bff.example.com"),
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
        XCTAssertTrue(msg.contains(NSLocalizedString("BFF Token 无效", comment: "")), "userMessage 应含 'BFF Token 无效'，实际：\(msg)")
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
        XCTAssertTrue(msg.contains(NSLocalizedString("BFF 服务异常", comment: "")), "userMessage 应含 'BFF 服务异常'，实际：\(msg)")
    }

    // MARK: - 8. 429 无 Retry-After Header → 默认 60 秒

    func testChat429WithoutRetryAfterDefaultsTo60() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 429
        // 不设置 Retry-After Header
        MockURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]

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
        XCTAssertEqual(retryAfter, 60, "无 Retry-After 时应默认 60 秒")
    }

    // MARK: - 9. 429 非法 Retry-After → 默认 60 秒

    func testChat429WithInvalidRetryAfterDefaultsTo60() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 429
        MockURLProtocol.responseHeaders = [
            "Content-Type": "text/event-stream",
            "Retry-After": "not-a-number"
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
        XCTAssertEqual(retryAfter, 60, "非法 Retry-After 应默认 60 秒")
    }

    // MARK: - 10. 403 → apiError

    func testChat403ReturnsApiError() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 403

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
        guard case .apiError(let code, _) = capturedError else {
            XCTFail("期望 .apiError，实际：\(String(describing: capturedError))")
            return
        }
        XCTAssertEqual(code, 403, "403 应映射到 apiError(403)")
    }

    // MARK: - 11. 网络错误 → LLMError.networkError 通知

    func testChatNetworkErrorPostsNotification() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        MockURLProtocol.statusCode = 200

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
        guard case .networkError = capturedError else {
            XCTFail("期望 .networkError，实际：\(String(describing: capturedError))")
            return
        }
    }

    // MARK: - 12. SSE 跳过非 data 前缀行

    func testChatSkipsNonDataLines() async {
        let sse = """
        : comment line

        event: ping

        data: {"choices":[{"delta":{"content":"OK"}}]}

        data: [DONE]

        """
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let collected = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))
        XCTAssertEqual(collected, "OK", "应仅解析 data: 前缀行的内容")
    }

    // MARK: - 13. SSE 损坏 JSON 不崩溃

    func testChatHandlesMalformedJSON() async {
        let sse = """
        data: {invalid json}

        data: {"choices":[{"delta":{"content":"valid"}}]}

        data: [DONE]

        """
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let collected = await consume(stream: client.chat(messages: makeMessages(), config: .default, apiKey: ""))
        XCTAssertEqual(collected, "valid", "损坏 JSON 行应被跳过，仅解析有效内容")
    }

    // MARK: - 14. embed 空入参短路

    func testEmbedEmptyInputShortCircuits() async throws {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.lastRequest = nil

        let result = try await client.embed(texts: [], apiKey: "")
        XCTAssertEqual(result, [], "空入参应返回空数组")
        XCTAssertNil(MockURLProtocol.lastRequest, "空入参不应发出 HTTP 请求")
    }

    // MARK: - 15. embed HTTP 错误抛 LLMError

    func testEmbedHTTPErrorThrows() async {
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

        do {
            _ = try await client.embed(texts: ["x"], apiKey: "")
            XCTFail("应抛出错误")
        } catch let err as LLMError {
            guard case .llmErrorOccurred = err else {
                XCTFail("期望 llmErrorOccurred（401），实际：\(err)")
                return
            }
        } catch {
            XCTFail("期望 LLMError，实际：\(type(of: error))")
        }

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - 16. embed 请求携带 X-BFF-Token 和 X-Provider

    func testEmbedSendsHeaders() async throws {
        let json = """
        {"data":[{"embedding":[0.1,0.2],"index":0}]}
        """
        MockURLProtocol.responseData = json.data(using: .utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.lastRequest = nil

        _ = try await client.embed(texts: ["test"], apiKey: "")

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-BFF-Token"), bffToken,
                       "embed 应携带 X-BFF-Token")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Provider"), "deepseek",
                       "embed 应携带 X-Provider")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json",
                       "embed Content-Type 应为 application/json")
    }

    // MARK: - 17. embed 返回按 index 排序的向量

    func testEmbedReturnsSortedVectors() async throws {
        let json = """
        {"data":[{"embedding":[0.3,0.4],"index":1},{"embedding":[0.1,0.2],"index":0}]}
        """
        MockURLProtocol.responseData = json.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let result = try await client.embed(texts: ["a", "b"], apiKey: "")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], [0.1, 0.2], "index 0 应排在前")
        XCTAssertEqual(result[1], [0.3, 0.4], "index 1 应排在后")
    }

    // MARK: - 18. embed 请求路径包含 v1/embeddings

    func testEmbedSendsToCorrectEndpoint() async throws {
        let json = """
        {"data":[{"embedding":[0.1],"index":0}]}
        """
        MockURLProtocol.responseData = json.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        _ = try await client.embed(texts: ["x"], apiKey: "")

        let path = MockURLProtocol.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.contains("/v1/embeddings"), "embed 路径应包含 /v1/embeddings，实际：\(path)")
    }

    // MARK: - 19. chatWithTools 成功解析 SSE 并 yield ParsedChunk

    func testChatWithToolsStreamsContent() async {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: [DONE]

        """
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        var chunks: [ParsedChunk] = []
        for await chunk in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.count, 1, "应 yield 1 个 ParsedChunk")
        XCTAssertEqual(chunks[0].content, "Hello")
    }

    // MARK: - 20. chatWithTools 成功解析 tool_calls

    func testChatWithToolsAccumulatesToolCalls() async {
        let sse = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"calc","arguments":""}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"x\":1}"}}]}}]}

        data: [DONE]

        """
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        var chunks: [ParsedChunk] = []
        for await chunk in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertTrue(chunks.count >= 1, "应至少 yield 1 个 chunk")
        let lastChunk = chunks.last!
        XCTAssertNotNil(lastChunk.toolCalls, "最后一个 chunk 应包含累积的 toolCalls")
        XCTAssertEqual(lastChunk.toolCalls?.first?.id, "call_1")
        XCTAssertEqual(lastChunk.toolCalls?.first?.name, "calc")
        XCTAssertEqual(lastChunk.toolCalls?.first?.arguments, "{\"x\":1}")
    }

    // MARK: - 21. chatWithTools 401 → LLMError

    func testChatWithTools401ThrowsLLMError() async {
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

        var chunks: [ParsedChunk] = []
        for await chunk in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.count, 0, "401 不应产出 chunk")

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .llmErrorOccurred = capturedError else {
            XCTFail("期望 .llmErrorOccurred，实际：\(String(describing: capturedError))")
            return
        }
    }

    // MARK: - 22. chatWithTools 网络错误 → 通知

    func testChatWithToolsNetworkErrorPostsNotification() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        MockURLProtocol.statusCode = 200

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        for await _ in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {}

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .networkError = capturedError else {
            XCTFail("期望 .networkError，实际：\(String(describing: capturedError))")
            return
        }
    }

    // MARK: - 23. chatWithTools SSE 跳过非 data 行

    func testChatWithToolsSkipsNonDataLines() async {
        let sse = """
        : comment

        event: ping

        data: {"choices":[{"delta":{"content":"OK"}}]}

        data: [DONE]

        """
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        var chunks: [ParsedChunk] = []
        for await chunk in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].content, "OK")
    }

    // MARK: - 24. chatWithTools 损坏 JSON 不崩溃

    func testChatWithToolsHandlesMalformedJSON() async {
        let sse = """
        data: {invalid json}

        data: {"choices":[{"delta":{"content":"valid"}}]}

        data: [DONE]

        """
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        var chunks: [ParsedChunk] = []
        for await chunk in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].content, "valid")
    }

    // MARK: - 25. chatWithTools 5xx 错误

    func testChatWithTools5xxThrowsLLMError() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 503

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        for await _ in client.chat(messages: makeMessages(), config: .default, tools: [], apiKey: "") {}

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .llmErrorOccurred = capturedError else {
            XCTFail("期望 .llmErrorOccurred，实际：\(String(describing: capturedError))")
            return
        }
    }

    // MARK: - 26. chat 携带多模态图片内容

    func testChatWithImagesSendsMultimodalContent() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.lastRequest = nil

        let messages = [APIMessage(role: "user", content: "看这张图", images: ["base64imgdata"], toolCallId: nil, toolName: nil, toolCalls: nil)]
        _ = await consume(stream: client.chat(messages: messages, config: .default, apiKey: ""))

        let bodyData = MockURLProtocol.lastRequest?.httpBody
        XCTAssertNotNil(bodyData, "应发送请求体")
        let bodyStr = String(data: bodyData ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyStr.contains("image_url"), "请求体应包含 image_url 字段")
        XCTAssertTrue(bodyStr.contains("data:image/jpeg;base64,base64imgdata"), "应包含 base64 图片数据")
    }

    // MARK: - 27. chat 携带 tool_call_id（tool 结果消息）

    func testChatWithToolCallIdInMessages() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.lastRequest = nil

        let messages = [APIMessage(role: "tool", content: "result data", images: nil, toolCallId: "call_123", toolName: nil, toolCalls: nil)]
        _ = await consume(stream: client.chat(messages: messages, config: .default, apiKey: ""))

        let bodyStr = String(data: MockURLProtocol.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyStr.contains("tool_call_id"), "请求体应包含 tool_call_id")
        XCTAssertTrue(bodyStr.contains("call_123"), "应包含 toolCallId 值")
    }

    // MARK: - 28. chat 携带 tool_calls（assistant 历史消息）

    func testChatWithToolCallsInMessages() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.lastRequest = nil
    
        let toolCalls = [ToolCallParam(id: "call_456", type: "function", function: FunctionCall(name: "search", arguments: "{\"q\":\"test\"}"))]
        let messages = [APIMessage(role: "assistant", content: "", images: nil, toolCallId: nil, toolName: nil, toolCalls: toolCalls)]
        _ = await consume(stream: client.chat(messages: messages, config: .default, apiKey: ""))
    
        let bodyStr = String(data: MockURLProtocol.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyStr.contains("tool_calls"), "请求体应包含 tool_calls")
        XCTAssertTrue(bodyStr.contains("call_456"), "应包含 toolCall id")
        XCTAssertTrue(bodyStr.contains("search"), "应包含函数名")
    }

    // MARK: - 29. embed 网络错误抛 LLMError

    func testEmbedNetworkErrorThrows() async {
        MockURLProtocol.error = URLError(.timedOut)
        MockURLProtocol.statusCode = 200

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        do {
            _ = try await client.embed(texts: ["test"], apiKey: "")
            XCTFail("应抛出错误")
        } catch let err as LLMError {
            guard case .networkError = err else {
                XCTFail("期望 networkError，实际：\(err)")
                return
            }
        } catch {
            XCTFail("期望 LLMError，实际：\(type(of: error))")
        }

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - 30. embed 响应解码失败

    func testEmbedDecodeFailureThrows() async {
        MockURLProtocol.responseData = Data("not valid json".utf8)
        MockURLProtocol.statusCode = 200

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        expectation.handler = { _ in true }

        do {
            _ = try await client.embed(texts: ["test"], apiKey: "")
            XCTFail("应抛出错误")
        } catch {
            XCTAssertTrue(error is LLMError || error is DecodingError, "应抛 LLMError 或 DecodingError")
        }

        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
