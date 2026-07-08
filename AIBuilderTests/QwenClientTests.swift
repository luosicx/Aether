import XCTest
@testable import AIBuilder

/// Day 13 Phase 5 Task 12: QwenClient 单元测试
/// 参考 DeepSeekClientTests 的 MockURLProtocol + 全局 URLProtocol.registerClass 模式。
/// QwenClient 的 `private lazy var session: URLSession = .shared` 与 DeepSeekClient 一致，
/// 全局注册 MockURLProtocol 即可拦截 .shared 的请求，无需 KVC / 子类化注入 session。
final class QwenClientTests: XCTestCase {

    // MARK: - Mock URLProtocol

    private final class MockURLProtocol: URLProtocol {
        static var responseData: Data?
        static var statusCode: Int = 200
        static var error: Error?
        static var lastRequest: URLRequest?
        /// 保存请求 body 副本（URLSession 可能将 body 转为 httpBodyStream，
        /// 导致 lastRequest.httpBody 为 nil，此处显式保存避免测试 flaky）
        static var lastBody: Data?
        static var headers: [String: String] = ["Content-Type": "application/json"]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            // 同时抓 httpBody 和 httpBodyStream，确保测试能稳定读取 body
            if let body = request.httpBody {
                Self.lastBody = body
            } else if let stream = request.httpBodyStream {
                Self.lastBody = readAll(from: stream)
            } else {
                Self.lastBody = nil
            }
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

        private func readAll(from stream: InputStream) -> Data {
            var data = Data()
            stream.open()
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            stream.close()
            return data
        }

        static func reset() {
            responseData = nil
            statusCode = 200
            error = nil
            lastRequest = nil
            lastBody = nil
            headers = ["Content-Type": "application/json"]
        }
    }

    // MARK: - Fixture

    private let apiKey = "test-key"
    private var client: QwenClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        URLProtocol.registerClass(MockURLProtocol.self)
        client = QwenClient()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    // MARK: - 1. chat 流式返回 content

    func testChatStreamsContent() async {
        let sse = """
data: {"choices":[{"delta":{"content":"Hello"}}]}

data: {"choices":[{"delta":{"content":" World"}}]}

data: [DONE]

"""
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let messages = [APIMessage(role: "user", content: "hi", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let stream = client.chat(messages: messages, config: .default, apiKey: apiKey)

        var collected: [String] = []
        for await chunk in stream {
            collected.append(chunk)
        }
        XCTAssertEqual(collected, ["Hello", " World"])
    }

    // MARK: - 2. chat 请求发往 Qwen baseURL

    func testChatSendsToQwenBaseURL() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200

        let messages = [APIMessage(role: "user", content: "hi", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let stream = client.chat(messages: messages, config: .default, apiKey: apiKey)
        for await _ in stream {}

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.host, "dashscope.aliyuncs.com")
        // 完整路径应为 .../compatible-mode/v1/chat/completions
        let path = MockURLProtocol.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.contains("/chat/completions"), "路径应包含 /chat/completions，实际：\(path)")
    }

    // MARK: - 3. chat 请求携带 Bearer 鉴权头

    func testChatSendsBearerAuth() async {
        MockURLProtocol.responseData = Data("data: [DONE]\n\n".utf8)
        MockURLProtocol.statusCode = 200

        let messages = [APIMessage(role: "user", content: "hi", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let stream = client.chat(messages: messages, config: .default, apiKey: apiKey)
        for await _ in stream {}

        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(apiKey)"
        )
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    // MARK: - 4. chatWithTools 解析出 tool_calls

    func testChatWithToolsYieldsToolCalls() async {
        // OpenAI 兼容 SSE：delta.tool_calls 含完整 id / type / function.name / function.arguments
        let sse = """
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"calculate","arguments":"{\\"expression\\":\\"1+2\\"}"}}]}}]}

data: [DONE]

"""
        MockURLProtocol.responseData = sse.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let messages = [APIMessage(role: "user", content: "算 1+2", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let tools = [ToolDef(
            type: "function",
            function: ToolDef.FunctionDef(
                name: "calculate",
                description: "计算表达式",
                parameters: ["type": AnyCodable("object")]
            )
        )]
        let stream = client.chat(messages: messages, config: .default, tools: tools, apiKey: apiKey)

        var chunksWithToolCalls: [ParsedChunk] = []
        for await chunk in stream {
            if chunk.toolCalls != nil {
                chunksWithToolCalls.append(chunk)
            }
        }
        XCTAssertFalse(chunksWithToolCalls.isEmpty, "应收到带 toolCalls 的 ParsedChunk")
        let first = chunksWithToolCalls.first?.toolCalls?.first
        XCTAssertEqual(first?.id, "call_1")
        XCTAssertEqual(first?.name, "calculate")
        XCTAssertEqual(first?.type, "function")
        XCTAssertEqual(first?.arguments, "{\"expression\":\"1+2\"}")
    }

    // MARK: - 5. embed 返回向量数组

    func testEmbedReturnsVectors() async throws {
        let json = """
{"data":[{"embedding":[0.1,0.2,0.3],"index":0},{"embedding":[0.4,0.5,0.6],"index":1}]}
"""
        MockURLProtocol.responseData = json.data(using: .utf8)
        MockURLProtocol.statusCode = 200

        let result = try await client.embed(texts: ["a", "b"], apiKey: apiKey)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], [0.1, 0.2, 0.3])
        XCTAssertEqual(result[1], [0.4, 0.5, 0.6])
    }

    // MARK: - 6. chat HTTP 错误并发 .llmErrorOccurred 通知

    func testChatHTTPErrorPostsNotification() async {
        MockURLProtocol.responseData = Data("{}".utf8)
        MockURLProtocol.statusCode = 401

        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                if case .apiKeyInvalid = err { return true }
            }
            return false
        }

        let messages = [APIMessage(role: "user", content: "hi", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
        let stream = client.chat(messages: messages, config: .default, apiKey: apiKey)
        // 消费流直到结束；HTTP 错误路径会在 finish 前于 MainActor 发通知
        for await _ in stream {}

        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
