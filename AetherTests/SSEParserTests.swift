import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Day 11: SSEParser 单元测试
final class SSEParserTests: XCTestCase {
    private let parser = SSEParser()

    func testParseChunkNormalContent() {
        // 模拟一个含 content 的 SSE 行
        let json = #"data: {"id":"chatcmpl-1","choices":[{"delta":{"content":"你好"},"finish_reason":null}]}"#
        let chunk = parser.parseChunk(from: json)
        XCTAssertNotNil(chunk, "正常 chunk 应解析成功")
        XCTAssertEqual(chunk?.choices?.first?.delta?.content, "你好")
    }

    func testParseChunkDone() {
        // [DONE] 应返回 nil
        let chunk = parser.parseChunk(from: "data: [DONE]")
        XCTAssertNil(chunk, "[DONE] 应返回 nil")
    }

    func testParseChunkEmptyLine() {
        // 非 data: 前缀的行应返回 nil
        let chunk = parser.parseChunk(from: ": comment line")
        XCTAssertNil(chunk, "注释行应返回 nil")
    }

    func testParseChunkInvalidJson() {
        // 非法 JSON 应返回 nil
        let chunk = parser.parseChunk(from: "data: {invalid json}")
        XCTAssertNil(chunk, "非法 JSON 应返回 nil")
    }

    @MainActor
    func testParseWithToolAccumulation() {
        // 模拟 tool_calls 增量：第一片带 id+name，第二片带 arguments 片段
        var accum: [Int: AccumulatedToolCall] = [:]
        let line1 = #"data: {"id":"1","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"calculate","arguments":""}}]}}]}"#
        let line2 = #"data: {"id":"1","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"expression\":"}}]}}]}"#
        let line3 = #"data: {"id":"1","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"1+2\"}"}}]}}]}"#
        _ = parser.parseWithToolAccumulation(from: line1, accumulated: &accum)
        _ = parser.parseWithToolAccumulation(from: line2, accumulated: &accum)
        let final = parser.parseWithToolAccumulation(from: line3, accumulated: &accum)

        XCTAssertNotNil(final, "第三片应返回 ParsedChunk")
        XCTAssertEqual(final?.toolCalls?.first?.id, "call_1")
        XCTAssertEqual(final?.toolCalls?.first?.name, "calculate")
        XCTAssertEqual(final?.toolCalls?.first?.arguments, #"{"expression":"1+2"}"#)
    }

    // MARK: - parse(data:) 方法测试

    /// parse(data:) 应正确将 Data 转为 String
    func testParseDataReturnsString() {
        let data = "Hello World".data(using: .utf8)!
        let result = parser.parse(data: data)
        XCTAssertEqual(result, "Hello World", "应将 Data 正确转为 String")
    }

    // MARK: - parseWithToolAccumulation 边界测试

    /// tool_call 缺少 id 或 name 时应 continue（跳过）
    @MainActor
    func testParseWithToolAccumulationMissingIdOrNameSkips() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"partial"}}]}}]}"#
        let result = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertNotNil(result, "应返回 ParsedChunk")
        XCTAssertTrue(accum.isEmpty, "缺少 id+name 的 tool_call 不应累积")
    }

    /// tool_call index 为 nil 时默认使用 0
    @MainActor
    func testParseWithToolAccumulationNilIndexDefaultsToZero() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"choices":[{"delta":{"tool_calls":[{"id":"call_1","type":"function","function":{"name":"test","arguments":""}}]}}]}"#
        _ = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertNotNil(accum[0], "index 为 nil 时应默认为 0")
        XCTAssertEqual(accum[0]?.id, "call_1")
    }

    /// tool_call type 为 nil 时默认使用 "function"
    @MainActor
    func testParseWithToolAccumulationNilTypeDefaultsToFunction() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"test","arguments":""}}]}}]}"#
        _ = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertEqual(accum[0]?.type, "function", "type 为 nil 时应默认为 function")
    }

    /// chunk 无 choices 时返回 nil
    @MainActor
    func testParseWithToolAccumulationNoChoicesReturnsNil() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"id":"1","choices":[]}"#
        let result = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertNil(result, "choices 为空数组时应返回 nil")
    }

    /// content-only chunk（无 tool_calls）应返回 ParsedChunk
    @MainActor
    func testParseWithToolAccumulationContentOnlyChunk() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"choices":[{"delta":{"content":"hello"}}]}"#
        let result = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertNotNil(result, "content-only chunk 应返回 ParsedChunk")
        XCTAssertEqual(result?.content, "hello")
        XCTAssertNil(result?.toolCalls, "无 tool_calls 时 toolCalls 应为 nil")
    }

    /// accumulated 为空时 toolCalls 应为 nil
    @MainActor
    func testParseWithToolAccumulationEmptyAccumulatedReturnsNilToolCalls() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"choices":[{"delta":{"content":"text"}}]}"#
        let result = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertNil(result?.toolCalls, "accumulated 为空时 toolCalls 应为 nil")
    }

    /// 同一 chunk 含多个 tool_calls（不同 index）
    @MainActor
    func testParseWithToolAccumulationMultipleToolCallsInOneChunk() {
        var accum: [Int: AccumulatedToolCall] = [:]
        let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_0","type":"function","function":{"name":"func_a","arguments":""}},{"index":1,"id":"call_1","type":"function","function":{"name":"func_b","arguments":""}}]}}]}"#
        let result = parser.parseWithToolAccumulation(from: line, accumulated: &accum)
        XCTAssertNotNil(result, "应返回 ParsedChunk")
        XCTAssertEqual(result?.toolCalls?.count, 2, "应累积 2 个 toolCalls")
        XCTAssertEqual(accum.count, 2, "accumulated 应有 2 个条目")
    }
}
