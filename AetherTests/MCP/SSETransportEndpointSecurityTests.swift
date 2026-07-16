import XCTest
@testable import Aether

/// SSETransport endpoint 同源校验回归测试（V4：MCP SSE endpoint 劫持防护）。
///
/// 安全审计报告 [V4] 指出：恶意 MCP Server 可通过 SSE `endpoint` 事件返回任意 URL，
/// 将客户端后续 JSON-RPC 请求（含 Authorization 头与请求体）劫持到攻击者服务器。
/// 修复方案在 `SSETransport.handleSSEEvent` 的 `endpoint` 分支增加同源校验
///（scheme + host + port 必须与 SSE 连接一致）。
///
/// 本测试集直接调用 `handleSSEEvent` 验证该校验逻辑，防止回归：
/// - 跨域 host / scheme / port 的 endpoint 必须被拒绝（postEndpoint 保持 nil）
/// - 同源（含相对路径解析、大小写变体）的 endpoint 必须被接受
final class SSETransportEndpointSecurityTests: XCTestCase {

    // MARK: - 同源 endpoint 应被接受

    /// 同源绝对 URL endpoint：scheme/host/port 与 SSE 连接一致，应被接受
    func testSameOriginAbsoluteEndpointAccepted() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "https://example.com/mcp/post")

        XCTAssertNotNil(transport.postEndpoint, "同源绝对 endpoint 应被接受")
        XCTAssertEqual(transport.postEndpoint?.absoluteString, "https://example.com/mcp/post")
    }

    /// 相对路径 endpoint：基于 SSE URL 解析后同源，应被接受
    /// 这是 MCP SSE 规范允许的合法用法（Server 通常返回相对路径）
    func testRelativeEndpointSameOriginAccepted() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "/mcp/post")

        XCTAssertNotNil(transport.postEndpoint, "相对路径 endpoint 解析后同源应被接受")
        // 相对路径解析后应指向同源的 POST 端点
        XCTAssertEqual(transport.postEndpoint?.host, "example.com")
        XCTAssertEqual(transport.postEndpoint?.scheme, "https")
    }

    /// 同源且显式端口一致：应被接受
    func testSameExplicitPortAccepted() {
        let transport = SSETransport(urlString: "https://example.com:9000/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "https://example.com:9000/mcp/post")

        XCTAssertNotNil(transport.postEndpoint, "同源同端口 endpoint 应被接受")
    }

    /// host 大小写变体（Example.com vs example.com）：host 比较已 lowercased，应被接受
    func testHostCaseInsensitiveAccepted() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "https://Example.com/mcp/post")

        XCTAssertNotNil(transport.postEndpoint, "host 大小写变体应被接受（比较已 lowercased）")
    }

    /// scheme 大小写变体（HTTPS vs https）：scheme 比较已 lowercased，应被接受
    func testSchemeCaseInsensitiveAccepted() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "HTTPS://example.com/mcp/post")

        XCTAssertNotNil(transport.postEndpoint, "scheme 大小写变体应被接受（比较已 lowercased）")
    }

    // MARK: - 跨域 endpoint 应被拒绝（核心安全断言）

    /// 跨域 host：审计报告 PoC — 攻击者 Server 返回 https://attacker.com/collect
    /// 必须被拒绝，否则后续请求（含 Authorization 头）会被发送到攻击者服务器
    func testCrossOriginHostEndpointRejected() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "https://attacker.com/collect")

        XCTAssertNil(transport.postEndpoint,
                     "跨域 host endpoint 必须被拒绝，否则凭据会泄露给攻击者")
    }

    /// 跨域 host（子域名伪装 example.com.evil.com）：必须被拒绝
    func testCrossOriginSubdomainImpersonationRejected() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "https://example.com.evil.com/collect")

        XCTAssertNil(transport.postEndpoint, "子域名伪装的跨域 endpoint 必须被拒绝")
    }

    /// 跨域 scheme（http vs https）：必须被拒绝，防止降级到明文传输
    func testCrossOriginSchemeRejected() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "http://example.com/mcp/post")

        XCTAssertNil(transport.postEndpoint, "跨域 scheme（http 降级）endpoint 必须被拒绝")
    }

    /// 跨域 scheme（file:// vs https://）：必须被拒绝
    func testFileSchemeEndpointRejected() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "file:///etc/passwd")

        XCTAssertNil(transport.postEndpoint, "file:// endpoint 必须被拒绝")
    }

    /// 跨域端口：SSE 在 9000，endpoint 在 9001，必须被拒绝
    func testDifferentPortRejected() {
        let transport = SSETransport(urlString: "https://example.com:9000/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "endpoint", data: "https://example.com:9001/mcp/post")

        XCTAssertNil(transport.postEndpoint, "跨域端口 endpoint 必须被拒绝")
    }

    // MARK: - 非 endpoint 事件不应设置 postEndpoint

    /// message 事件不应设置 postEndpoint（仅 endpoint 事件可设置）
    func testMessageEventDoesNotSetEndpoint() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "message", data: "https://example.com/mcp/post")

        XCTAssertNil(transport.postEndpoint, "message 事件不应设置 postEndpoint")
    }

    /// 未知事件类型不应设置 postEndpoint
    func testUnknownEventDoesNotSetEndpoint() {
        let transport = SSETransport(urlString: "https://example.com/mcp/sse", headers: nil)
        transport.handleSSEEvent(event: "ping", data: "https://example.com/mcp/post")

        XCTAssertNil(transport.postEndpoint, "未知事件不应设置 postEndpoint")
    }

    // MARK: - 劫持防护端到端语义验证

    /// 模拟审计报告 [V4] 的完整攻击场景：
    /// 1. 用户连接合法 MCP Server（SSE URL = https://mcp.example.com/sse）
    /// 2. 恶意/被攻陷的 Server 在 SSE 流中发送跨域 endpoint 事件
    /// 3. 客户端必须拒绝该 endpoint，postEndpoint 保持 nil
    /// 4. 后续 send() 因 postEndpoint 为 nil 抛出 connectionFailed，凭据不会被外传
    func testAuditPoCAttackerEndpointRejected() async throws {
        let transport = SSETransport(
            urlString: "https://mcp.example.com/sse",
            headers: ["Authorization": "Bearer secret-token-123"]
        )

        // 攻击者尝试将 endpoint 劫持到自己的服务器
        transport.handleSSEEvent(event: "endpoint", data: "https://attacker.com/collect")

        // 关键断言：跨域 endpoint 被拒绝，postEndpoint 保持 nil
        XCTAssertNil(transport.postEndpoint,
                     "审计 V4 PoC：攻击者跨域 endpoint 必须被拒绝")

        // 因 postEndpoint 为 nil，send() 必须抛出 connectionFailed，
        // 不会将含 Authorization 头的请求发送到攻击者服务器
        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("postEndpoint 为 nil 时 send 应抛出 connectionFailed，防止凭据外传")
        } catch let error as MCPError {
            if case .connectionFailed = error {
                // 预期：postEndpoint 未就绪
            } else {
                XCTFail("应为 connectionFailed 错误，实际: \(error)")
            }
        } catch {
            XCTFail("应为 MCPError，实际: \(error)")
        }
    }
}
