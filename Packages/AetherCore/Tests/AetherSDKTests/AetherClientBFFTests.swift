import XCTest
@testable import AetherSDK
import AetherFoundation
import AetherServices

/// P1-10: SDK `.bff` 模式必须经 BFFProxyClient 转发，
/// Token 只能以 `X-BFF-Token` 发送，绝不能作为上游 Bearer。
final class AetherClientBFFTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BFFStubURLProtocol.reset()
        URLProtocol.registerClass(BFFStubURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(BFFStubURLProtocol.self)
        BFFStubURLProtocol.reset()
        super.tearDown()
    }

    func testStreamSendsTokenAsBFFHeaderAndNotBearer() async throws {
        BFFStubURLProtocol.responseBody = """
        data: {"choices":[{"delta":{"content":"hi"}}]}

        data: [DONE]

        """
        let config = AetherConfig(
            provider: .bff,
            apiKey: "bff-user-token",
            baseURL: URL(string: "https://bff.test")
        )
        let client = try AetherClient(config: config)

        var contents: [String] = []
        for await chunk in client.stream(messages: [.user("hello")]) {
            if let content = chunk.content {
                contents.append(content)
            }
        }

        XCTAssertEqual(contents.joined(), "hi")

        let request = try XCTUnwrap(BFFStubURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-BFF-Token"), "bff-user-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Provider"), "deepseek")
        XCTAssertNil(
            request.value(forHTTPHeaderField: "Authorization"),
            "BFF Token 不能作为上游 Bearer 发送"
        )
    }

    func testEmbedUsesBFFEndpoint() async throws {
        BFFStubURLProtocol.responseBody = """
        {"data":[{"index":0,"embedding":[0.1,0.2]}]}
        """
        let config = AetherConfig(
            provider: .bff,
            apiKey: "bff-user-token",
            baseURL: URL(string: "https://bff.test")
        )
        let client = try AetherClient(config: config)

        let vectors = try await client.embed(texts: ["hello"])

        XCTAssertEqual(vectors, [[0.1, 0.2]])
        let request = try XCTUnwrap(BFFStubURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/embeddings")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-BFF-Token"), "bff-user-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}

/// 拦截 URLSession.shared 请求，返回预置响应并记录请求头。
private final class BFFStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = ""
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    static func reset() {
        responseBody = ""
        capturedRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequest = request
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
