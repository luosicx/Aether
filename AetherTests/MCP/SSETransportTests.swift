import XCTest
@testable import Aether

/// SSETransport 单元测试
///
/// 覆盖范围：
/// 1. init：有效 URL 与无效 URL（空字符串）解析
/// 2. send：未连接（postEndpoint 为 nil）时抛出 connectionFailed
/// 3. send：HTTP 错误状态码抛出 transportError
/// 4. disconnect：幂等性（多次调用无副作用）
/// 5. messages：返回 AsyncStream<Data>
/// 6. handleSSEEvent：endpoint 同源事件通过（通过 connect 触发）
/// 7. handleSSEEvent：endpoint 跨域事件被拒（通过 connect 触发）
final class SSETransportTests: XCTestCase {

    // MARK: - URLProtocol Mock

    /// 测试用 URLProtocol：拦截 URLSession 请求，按 HTTP 方法返回预设响应。
    /// GET 请求返回 SSE 流响应（支持 session.bytes(for:)）；
    /// POST 请求返回一次性响应（支持 session.data(for:)）。
    private final class SSEMockURLProtocol: URLProtocol {
        /// GET（SSE 流）响应体
        static var sseData: Data = Data()
        /// GET（SSE 流）状态码
        static var sseStatusCode: Int = 200
        /// POST 响应体
        static var postData: Data = Data()
        /// POST 状态码
        static var postStatusCode: Int = 200

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let method = request.httpMethod ?? "GET"
            if method == "POST" {
                // POST 请求（send 方法发起）返回预设状态码与响应体
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: SSEMockURLProtocol.postStatusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: SSEMockURLProtocol.postData)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                // GET 请求（connect 方法发起）返回 SSE 流响应
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: SSEMockURLProtocol.sseStatusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: SSEMockURLProtocol.sseData)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}

        /// 重置静态状态（测试间隔离）
        static func reset() {
            sseData = Data()
            sseStatusCode = 200
            postData = Data()
            postStatusCode = 200
        }
    }

    // MARK: - 辅助方法

    /// 创建注入了 Mock URLProtocol 的 URLSession
    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// 从 AsyncStream 收集所有消息，带超时保护（防止测试挂起）。
    /// 流正常结束后返回所有消息；超时则返回已收集的消息。
    private func collectMessages(from stream: AsyncStream<Data>, timeoutSeconds: TimeInterval = 5) async -> [Data] {
        await withTaskGroup(of: [Data].self) { group in
            // 消息收集任务：流结束时返回所有消息
            group.addTask {
                var messages: [Data] = []
                for await data in stream {
                    messages.append(data)
                }
                return messages
            }
            // 超时看门狗任务：到达超时时间返回空数组
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return []
            }
            // 等待先完成的任务，取消另一个
            let result = await group.next() ?? []
            group.cancelAll()
            return result
        }
    }

    /// 构造单条 SSE endpoint 事件响应体
    private func makeEndpointSSEResponse(endpoint: String) -> Data {
        "event: endpoint\ndata: \(endpoint)\n\n".data(using: .utf8)!
    }

    // MARK: - 1. init 测试

    /// init 接受有效 URL 字符串时，应成功构造对象，messages() 可正常调用
    func testInitWithValidURL() async {
        let transport = SSETransport(urlString: "http://localhost:9999/sse", headers: nil)
        // messages() 可调用证明对象已正确初始化
        _ = transport.messages()
        await transport.disconnect()
    }

    /// init 接受空字符串（无效 URL）时，应回退到 fileURLWithPath("")，对象仍可构造
    func testInitWithInvalidEmptyURL() async {
        let transport = SSETransport(urlString: "", headers: nil)
        // 即使 URL 无效，对象仍可构造，messages() 与 disconnect() 不崩溃
        _ = transport.messages()
        await transport.disconnect()
    }

    // MARK: - 2. send 未连接测试

    /// send 在未连接（postEndpoint 为 nil）时，应抛出 connectionFailed
    func testSendWithoutEndpointThrowsConnectionFailed() async throws {
        let transport = SSETransport(urlString: "http://localhost:9999/sse", headers: nil)

        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("未连接时 send 应抛出 connectionFailed 错误")
        } catch let error as MCPError {
            if case .connectionFailed = error {
                // 预期：postEndpoint 未设置
            } else {
                XCTFail("应为 connectionFailed 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }

        await transport.disconnect()
    }

    // MARK: - 3. send HTTP 错误状态码测试

    /// send 在 POST 请求收到 HTTP 错误状态码时，应抛出 transportError
    func testSendWithHTTPErrorStatusCodeThrowsTransportError() async throws {
        let sseURL = "http://localhost:9999/sse"
        // 同源 endpoint，使 postEndpoint 被设置
        let sseData = makeEndpointSSEResponse(endpoint: "/messages")

        SSEMockURLProtocol.reset()
        SSEMockURLProtocol.sseData = sseData
        SSEMockURLProtocol.sseStatusCode = 200
        SSEMockURLProtocol.postStatusCode = 500 // POST 返回 500

        let session = makeMockSession()
        let transport = SSETransport(urlString: sseURL, headers: nil, session: session)

        // 先启动消息流（设置 continuation），再连接
        let stream = transport.messages()
        try await transport.connect()

        // 等待读取 Task 处理完 endpoint 事件（流结束后表示读取完成）
        _ = await collectMessages(from: stream, timeoutSeconds: 3)

        // postEndpoint 已设置，send 将发起 POST 请求，收到 500 → 抛出 transportError
        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("HTTP 500 时 send 应抛出 transportError 错误")
        } catch let error as MCPError {
            if case .transportError = error {
                // 预期：POST 返回 500
            } else {
                XCTFail("应为 transportError 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }

        await transport.disconnect()
    }

    // MARK: - 4. disconnect 幂等性测试

    /// disconnect 多次调用应是幂等的，不产生副作用或崩溃
    func testDisconnectIsIdempotent() async {
        let transport = SSETransport(urlString: "http://localhost:9999/sse", headers: nil)
        _ = transport.messages()

        await transport.disconnect()
        // 再次调用不应崩溃
        await transport.disconnect()
        // 第三次调用也不应崩溃
        await transport.disconnect()
    }

    // MARK: - 5. messages 测试

    /// messages 应返回 AsyncStream<Data>，可被迭代
    func testMessagesReturnsAsyncStream() async {
        let transport = SSETransport(urlString: "http://localhost:9999/sse", headers: nil)
        let stream = transport.messages()

        // disconnect 会 finish continuation，使流结束
        await transport.disconnect()

        // 流应在 disconnect 后立即结束，不产生消息
        let messages = await collectMessages(from: stream, timeoutSeconds: 1)
        XCTAssertTrue(messages.isEmpty, "未连接的流不应产生消息")
    }

    // MARK: - 6. handleSSEEvent 同源 endpoint 测试

    /// endpoint 事件同源时应被接受，postEndpoint 被设置，send 不再抛 connectionFailed。
    /// 通过 connect() 触发内部 handleSSEEvent，验证同源校验通过。
    func testHandleSSEEventSameOriginEndpointAccepted() async throws {
        let sseURL = "http://localhost:9999/sse"
        // 同源 endpoint（相对路径，基于 SSE URL 解析为 http://localhost:9999/messages）
        let sseData = makeEndpointSSEResponse(endpoint: "/messages")

        SSEMockURLProtocol.reset()
        SSEMockURLProtocol.sseData = sseData
        SSEMockURLProtocol.sseStatusCode = 200
        SSEMockURLProtocol.postStatusCode = 200 // POST 返回 200

        let session = makeMockSession()
        let transport = SSETransport(urlString: sseURL, headers: nil, session: session)

        // 先启动消息流，再连接
        let stream = transport.messages()
        try await transport.connect()

        // 等待读取 Task 处理完 endpoint 事件（流结束表示读取完成，postEndpoint 已设置）
        _ = await collectMessages(from: stream, timeoutSeconds: 3)

        // 同源 endpoint 被接受，postEndpoint 已设置，send 应成功（POST 200）
        do {
            _ = try await transport.send(Data("{}".utf8))
            // 预期：send 成功
        } catch {
            XCTFail("同源 endpoint 应被接受，send 不应抛出错误，实际: \(error)")
        }

        await transport.disconnect()
    }

    // MARK: - 7. handleSSEEvent 跨域 endpoint 测试

    /// endpoint 事件跨域时应被拒绝，postEndpoint 保持 nil，send 抛 connectionFailed。
    /// 通过 connect() 触发内部 handleSSEEvent，验证跨域劫持防护生效。
    func testHandleSSEEventCrossOriginEndpointRejected() async throws {
        let sseURL = "http://localhost:9999/sse"
        // 跨域 endpoint（host 不同，触发劫持检测）
        let sseData = makeEndpointSSEResponse(endpoint: "http://evil.com/api")

        SSEMockURLProtocol.reset()
        SSEMockURLProtocol.sseData = sseData
        SSEMockURLProtocol.sseStatusCode = 200

        let session = makeMockSession()
        let transport = SSETransport(urlString: sseURL, headers: nil, session: session)

        // 先启动消息流，再连接
        let stream = transport.messages()
        try await transport.connect()

        // 等待读取 Task 处理（恶意）endpoint 事件
        _ = await collectMessages(from: stream, timeoutSeconds: 3)

        // 跨域 endpoint 被拒绝，postEndpoint 为 nil，send 抛 connectionFailed
        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("跨域 endpoint 应被拒绝，send 应抛出 connectionFailed 错误")
        } catch let error as MCPError {
            if case .connectionFailed = error {
                // 预期：postEndpoint 未设置
            } else {
                XCTFail("应为 connectionFailed 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }

        await transport.disconnect()
    }
}
