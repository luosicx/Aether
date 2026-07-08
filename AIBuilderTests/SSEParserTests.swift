import XCTest
@testable import AIBuilder

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
}
