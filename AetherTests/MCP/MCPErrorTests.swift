import XCTest
@testable import Aether

/// MCPError 单元测试
///
/// 覆盖所有 8 个 enum case 的 errorDescription 与 diagnosticDescription 输出，
/// 以及 WithCause 变体是否正确携带底层 Error。
final class MCPErrorTests: XCTestCase {

    // MARK: - errorDescription

    func testErrorDescriptionConnectionFailed() {
        let error = MCPError.connectionFailed("子进程退出")
        XCTAssertEqual(error.errorDescription, "MCP 连接失败: 子进程退出")
    }

    func testErrorDescriptionConnectionFailedWithCause() {
        let underlying = URLError(.notConnectedToInternet)
        let error = MCPError.connectionFailedWithCause(message: "网络不可达", underlying: underlying)
        XCTAssertEqual(error.errorDescription, "MCP 连接失败: 网络不可达")
    }

    func testErrorDescriptionTimeout() {
        let error = MCPError.timeout
        XCTAssertEqual(error.errorDescription, "MCP 请求超时")
    }

    func testErrorDescriptionProtocolError() {
        let error = MCPError.protocolError("方法不存在")
        XCTAssertEqual(error.errorDescription, "MCP 协议错误: 方法不存在")
    }

    func testErrorDescriptionTransportError() {
        let error = MCPError.transportError("写入失败")
        XCTAssertEqual(error.errorDescription, "MCP 传输错误: 写入失败")
    }

    func testErrorDescriptionTransportErrorWithCause() {
        let underlying = NSError(domain: "test", code: 42)
        let error = MCPError.transportErrorWithCause(message: "管道破裂", underlying: underlying)
        XCTAssertEqual(error.errorDescription, "MCP 传输错误: 管道破裂")
    }

    func testErrorDescriptionNotConnected() {
        let error = MCPError.notConnected
        XCTAssertEqual(error.errorDescription, "MCP 客户端未连接")
    }

    func testErrorDescriptionInvalidResponse() {
        let error = MCPError.invalidResponse("JSON 解析失败")
        XCTAssertEqual(error.errorDescription, "MCP 响应无效: JSON 解析失败")
    }

    // MARK: - diagnosticDescription

    func testDiagnosticDescriptionConnectionFailed() {
        let error = MCPError.connectionFailed("超时")
        XCTAssertEqual(error.diagnosticDescription, "MCPError.connectionFailed(超时)")
    }

    func testDiagnosticDescriptionConnectionFailedWithCause() {
        let underlying = URLError(.timedOut)
        let error = MCPError.connectionFailedWithCause(message: "超时", underlying: underlying)
        XCTAssertTrue(error.diagnosticDescription.contains("MCPError.connectionFailedWithCause(超时"))
        XCTAssertTrue(error.diagnosticDescription.contains("underlying"))
    }

    func testDiagnosticDescriptionTimeout() {
        let error = MCPError.timeout
        XCTAssertEqual(error.diagnosticDescription, "MCPError.timeout")
    }

    func testDiagnosticDescriptionProtocolError() {
        let error = MCPError.protocolError("参数无效")
        XCTAssertEqual(error.diagnosticDescription, "MCPError.protocolError(参数无效)")
    }

    func testDiagnosticDescriptionTransportError() {
        let error = MCPError.transportError("IO 错误")
        XCTAssertEqual(error.diagnosticDescription, "MCPError.transportError(IO 错误)")
    }

    func testDiagnosticDescriptionTransportErrorWithCause() {
        let underlying = NSError(domain: "POSIX", code: 32)
        let error = MCPError.transportErrorWithCause(message: "管道断裂", underlying: underlying)
        XCTAssertTrue(error.diagnosticDescription.contains("MCPError.transportErrorWithCause(管道断裂"))
        XCTAssertTrue(error.diagnosticDescription.contains("underlying"))
    }

    func testDiagnosticDescriptionNotConnected() {
        let error = MCPError.notConnected
        XCTAssertEqual(error.diagnosticDescription, "MCPError.notConnected")
    }

    func testDiagnosticDescriptionInvalidResponse() {
        let error = MCPError.invalidResponse("缺少 result 字段")
        XCTAssertEqual(error.diagnosticDescription, "MCPError.invalidResponse(缺少 result 字段)")
    }

    // MARK: - LocalizedError 一致性

    func testConformsToLocalizedError() {
        let errors: [MCPError] = [
            .connectionFailed("msg"),
            .connectionFailedWithCause(message: "msg", underlying: URLError(.badURL)),
            .timeout,
            .protocolError("msg"),
            .transportError("msg"),
            .transportErrorWithCause(message: "msg", underlying: URLError(.badServerResponse)),
            .notConnected,
            .invalidResponse("msg")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "每个 case 都应有 errorDescription")
            XCTAssertFalse(error.diagnosticDescription.isEmpty, "每个 case 都应有非空 diagnosticDescription")
        }
    }

    // MARK: - WithCause 底层错误保留

    func testConnectionFailedWithCausePreservesUnderlying() {
        let underlying = URLError(.cannotConnectToHost)
        let error = MCPError.connectionFailedWithCause(message: "无法连接", underlying: underlying)
        // diagnosticDescription 应包含底层错误的类型信息
        XCTAssertTrue(error.diagnosticDescription.contains("URLError"))
    }

    func testTransportErrorWithCausePreservesUnderlying() {
        let underlying = NSError(domain: "custom", code: 99, userInfo: [NSLocalizedDescriptionKey: "custom error"])
        let error = MCPError.transportErrorWithCause(message: "发送失败", underlying: underlying)
        XCTAssertTrue(error.diagnosticDescription.contains("custom error"))
    }

    // MARK: - Error 等价性

    func testCatchAsError() {
        func throwMCPError(_ error: MCPError) throws -> String {
            throw error
        }
        XCTAssertThrowsError(try throwMCPError(.timeout)) { error in
            XCTAssertTrue(error is MCPError, "MCPError 应可被 catch 为 Error")
        }
    }

    func testCatchSpecificCase() {
        func throwMCPError() throws {
            throw MCPError.notConnected
        }
        do {
            _ = try throwMCPError()
            XCTFail("应抛出 notConnected")
        } catch MCPError.notConnected {
            // 预期
        } catch {
            XCTFail("应匹配 notConnected，实际：\(error)")
        }
    }
}
