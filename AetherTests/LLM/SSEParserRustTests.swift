import XCTest
@testable import AetherServices
@testable import AetherRust

/// Rust SSE 解析器 Swift 回归测试。
/// 注意：本测试需要 aether_core.xcframework 已构建（macOS 环境）。
/// Linux/CI 无 xcframework 时本测试会因链接失败而跳过编译，故放在 iOS/macOS 测试 target。
final class SSEParserRustTests: XCTestCase {

    func testExtractContent() {
        let p = AetherRustSSEParser()
        let line = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
        XCTAssertEqual(p.extractContent(line), "Hi")
    }

    func testDoneReturnsNilContent() {
        let p = AetherRustSSEParser()
        // [DONE] 在 parseChunk 语义里是 Some(None)，Swift wrapper 转为 nil content
        XCTAssertNil(p.parseChunk("data: [DONE]"))
    }

    func testNonDataLineReturnsNil() {
        let p = AetherRustSSEParser()
        XCTAssertNil(p.parseChunk(": keepalive"))
        XCTAssertNil(p.parseChunk("event: ping"))
    }

    func testToolCallAccumulation() {
        let p = AetherRustSSEParser()
        let first = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}"#
        let r1 = p.parseWithTools(first)
        XCTAssertNotNil(r1)
        XCTAssertEqual(r1?.toolCalls?.first?.name, "get_weather")
        XCTAssertEqual(r1?.toolCalls?.first?.type, "function")
        // 第二片只追加 arguments
        let second = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":\"BJ\"}"}}]}}]}"#
        let r2 = p.parseWithTools(second)
        XCTAssertEqual(r2?.toolCalls?.first?.arguments, #"{"city":"BJ"}"#)
    }

    // MARK: - SSEParser 转发层回归（验证 Rust 路径与旧 Swift 行为一致）

    func testSSEParserForwardsContent() {
        let parser = SSEParser()
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        let chunk = parser.parseChunk(from: line)
        XCTAssertEqual(chunk?.choices?.first?.delta?.content, "Hello")
    }

    func testSSEParserForwardsToolAccumulation() {
        let parser = SSEParser()
        var acc: [Int: AccumulatedToolCall] = [:]
        let first = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}"#
        let second = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":\"BJ\"}"}}]}}]}"#
        _ = parser.parseWithToolAccumulation(from: first, accumulated: &acc)
        let result = parser.parseWithToolAccumulation(from: second, accumulated: &acc)
        XCTAssertEqual(result?.toolCalls?.first?.arguments, #"{"city":"BJ"}"#)
        XCTAssertEqual(result?.toolCalls?.first?.name, "get_weather")
    }
}
