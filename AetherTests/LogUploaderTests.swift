import XCTest
@testable import Aether

/// Day 14 Phase 5 Task 11: LogUploader 单元测试
/// 参考 DeepSeekClientTests 的 MockURLProtocol 模式，扩展为支持响应队列以测试重试。
/// LogUploader 通过 init(endpointURL:) 注入 mock endpoint；
/// 内部调用 TelemetryService.shared.drain()，因此需通过 shared 写入事件。
final class LogUploaderTests: XCTestCase {

    // MARK: - Mock URLProtocol（支持响应队列用于重试测试）

    private final class MockURLProtocol: URLProtocol {
        /// 响应队列：按请求顺序消费；队列空时使用 fallbackStatusCode
        static var responseQueue: [Int] = []
        static var fallbackStatusCode: Int = 200
        static var responseData: Data?
        static var error: Error?
        static var lastRequest: URLRequest?
        /// 保存请求 body 副本（URLSession 可能将 body 转为 httpBodyStream，
        /// 导致 lastRequest.httpBody 为 nil，此处显式保存避免测试 flaky）
        static var lastBody: Data?
        static var requestCount: Int = 0
        static var headers: [String: String] = ["Content-Type": "application/json"]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            Self.requestCount += 1
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
            let statusCode: Int
            if !Self.responseQueue.isEmpty {
                statusCode = Self.responseQueue.removeFirst()
            } else {
                statusCode = Self.fallbackStatusCode
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
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
            responseQueue = []
            fallbackStatusCode = 200
            responseData = nil
            error = nil
            lastRequest = nil
            lastBody = nil
            requestCount = 0
            headers = ["Content-Type": "application/json"]
        }
    }

    // MARK: - Fixture

    private let endpoint = URL(string: "https://test.example.com/logs")!
    private var uploader: LogUploader!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        URLProtocol.registerClass(MockURLProtocol.self)
        uploader = LogUploader(endpointURL: endpoint)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        uploader = nil
        super.tearDown()
    }

    /// 清空 TelemetryService.shared 缓冲，确保测试隔离
    private func drainShared() async {
        _ = await TelemetryService.shared.drain()
    }

    /// 向 TelemetryService.shared 写入若干事件
    private func seedEvents(_ count: Int) async {
        for i in 0..<count {
            await TelemetryService.shared.track(.messageSent(provider: "p", model: "m", inputTokens: i))
        }
    }

    // MARK: - 1. 成功上报：POST JSON 数组到 endpoint

    func testUploadBatchPostsJSONToEndpoint() async {
        await drainShared()
        await seedEvents(3)
        MockURLProtocol.fallbackStatusCode = 200
        MockURLProtocol.responseData = Data("{}".utf8)

        await uploader.uploadIfNeeded()

        XCTAssertEqual(MockURLProtocol.requestCount, 1, "应发出 1 次请求")
        XCTAssertNotNil(MockURLProtocol.lastBody)
        let json = try? JSONSerialization.jsonObject(with: MockURLProtocol.lastBody ?? Data(), options: []) as? [[String: Any]]
        XCTAssertNotNil(json, "请求体应为 JSON 数组")
        XCTAssertEqual(json?.count, 3, "应含 3 条记录")

        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "success")
    }

    // MARK: - 2. 持续失败重试 3 次后失败

    func testUploadFailureRetriesThreeTimes() async {
        await drainShared()
        await seedEvents(2)
        // 所有请求均返回 500
        MockURLProtocol.fallbackStatusCode = 500

        await uploader.uploadIfNeeded()

        // maxRetries = 3：共 3 次尝试（retry 0/1/2），其中 retry 0 和 1 各 sleep 1s/2s
        XCTAssertEqual(MockURLProtocol.requestCount, 3, "应重试共 3 次")
        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "failed")
    }

    // MARK: - 3. 成功上报更新 lastUploadAt

    func testUploadSuccessUpdatesLastUploadAt() async {
        await drainShared()
        await seedEvents(1)
        MockURLProtocol.fallbackStatusCode = 200

        await uploader.uploadIfNeeded()

        let lastUploadAt = await uploader.lastUploadAt
        XCTAssertNotNil(lastUploadAt, "成功上报后 lastUploadAt 应非空")
        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "success")
    }

    // MARK: - 4. 空缓冲跳过请求

    func testUploadEmptyBufferSkipsRequest() async {
        // 先 drain 清空 shared 缓冲
        await drainShared()
        MockURLProtocol.fallbackStatusCode = 200

        await uploader.uploadIfNeeded()

        XCTAssertEqual(MockURLProtocol.requestCount, 0, "空缓冲不应发出请求")
        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "success", "无数据上报应记为 success")
        let lastUploadAt = await uploader.lastUploadAt
        XCTAssertNotNil(lastUploadAt, "即使无数据也应更新 lastUploadAt")
    }

    // MARK: - 5. 指数退避重试：前 2 次 500 + 第 3 次 200

    func testUploadRetriesWithExponentialBackoff() async {
        await drainShared()
        await seedEvents(1)
        // 前 2 次返回 500，第 3 次返回 200
        MockURLProtocol.responseQueue = [500, 500, 200]

        await uploader.uploadIfNeeded()

        XCTAssertEqual(MockURLProtocol.requestCount, 3, "应共 3 次请求")
        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "success", "第 3 次成功后应记为 success")
    }

    // MARK: - 边缘测试补充

    // 上报请求应使用 POST 方法并设置 Content-Type: application/json
    func testUploadSetsPOSTMethodAndContentType() async {
        await drainShared()
        await seedEvents(1)
        MockURLProtocol.fallbackStatusCode = 200

        await uploader.uploadIfNeeded()

        XCTAssertNotNil(MockURLProtocol.lastRequest)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "POST", "应使用 POST 方法")
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json",
            "Content-Type 应为 application/json"
        )
    }

    // 上报请求体应包含记录的 event / payload / timestamp 字段
    func testUploadRequestBodyContainsRecordFields() async {
        await drainShared()
        await TelemetryService.shared.track(.toolCall(toolName: "alarm", success: true, durationMs: 42))
        MockURLProtocol.fallbackStatusCode = 200

        await uploader.uploadIfNeeded()

        XCTAssertNotNil(MockURLProtocol.lastBody)
        let json = try? JSONSerialization.jsonObject(with: MockURLProtocol.lastBody ?? Data(), options: []) as? [[String: Any]]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?.count, 1)
        let record = json?.first
        XCTAssertEqual(record?["event"] as? String, "toolCall")
        let payload = record?["payload"] as? [String: String]
        XCTAssertEqual(payload?["toolName"], "alarm")
        XCTAssertEqual(payload?["durationMs"], "42")
        XCTAssertNotNil(record?["timestamp"], "请求体应包含 timestamp 字段")
        XCTAssertNotNil(record?["id"], "请求体应包含 id 字段")
    }

    // 上报失败时 lastUploadAt 不应被更新（保持 nil）
    func testFailureDoesNotUpdateLastUploadAt() async {
        await drainShared()
        await seedEvents(2)
        MockURLProtocol.fallbackStatusCode = 500

        await uploader.uploadIfNeeded()

        let lastUploadAt = await uploader.lastUploadAt
        XCTAssertNil(lastUploadAt, "失败时 lastUploadAt 不应更新，保持 nil")
        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "failed")
    }

    // 4xx 响应（如 404）同样触发重试逻辑
    func test4xxResponseTriggersRetry() async {
        await drainShared()
        await seedEvents(1)
        // 404 不在 2xx 范围，应触发重试：前 2 次 404 + 第 3 次 200
        MockURLProtocol.responseQueue = [404, 404, 200]

        await uploader.uploadIfNeeded()

        XCTAssertEqual(MockURLProtocol.requestCount, 3, "404 应触发重试，共 3 次请求")
        let status = await uploader.lastUploadStatus
        XCTAssertEqual(status, "success", "第 3 次 200 后应记为 success")
    }
}
