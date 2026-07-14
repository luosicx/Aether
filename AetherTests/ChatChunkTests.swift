import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// ChatChunk 及相关模型 Codable / 行为单元测试
final class ChatChunkTests: XCTestCase {

    // MARK: - 辅助方法

    /// 将 Encodable 编码为 JSON 后解析回 [String: Any]，便于按键断言
    private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            XCTFail("编码结果应为 JSON 对象")
            return [:]
        }
        return dict
    }

    // MARK: - ChatChunk Codable

    /// 典型 DeepSeek SSE chunk：含 delta.content、finish_reason=null、usage=null
    func testDecodeTypicalContentChunk() throws {
        let json = #"{"id":"chatcmpl-1","object":"chat.completion.chunk","created":1700000000,"model":"deepseek-chat","choices":[{"index":0,"delta":{"role":"assistant","content":"你好"},"finish_reason":null}],"usage":null}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(json.utf8))

        XCTAssertEqual(chunk.id, "chatcmpl-1")
        XCTAssertEqual(chunk.choices?.count, 1)
        XCTAssertEqual(chunk.choices?.first?.delta?.role, "assistant")
        XCTAssertEqual(chunk.choices?.first?.delta?.content, "你好")
        XCTAssertNil(chunk.choices?.first?.finish_reason, "finish_reason=null 应解码为 nil")
        XCTAssertNil(chunk.usage, "usage=null 应解码为 nil")
        XCTAssertNil(chunk.choices?.first?.delta?.tool_calls, "无 tool_calls 时应为 nil")
    }

    /// 解码带 tool_calls 的 delta：index/id/type/function.name/function.arguments 正确
    func testDecodeDeltaWithToolCalls() throws {
        let json = #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"calculate","arguments":"{\"expression\":\"1+1\"}"}}]}}]}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(json.utf8))

        let toolCall = chunk.choices?.first?.delta?.tool_calls?.first
        XCTAssertNotNil(toolCall)
        XCTAssertEqual(toolCall?.index, 0)
        XCTAssertEqual(toolCall?.id, "call_abc")
        XCTAssertEqual(toolCall?.type, "function")
        XCTAssertEqual(toolCall?.function?.name, "calculate")
        XCTAssertEqual(toolCall?.function?.arguments, #"{"expression":"1+1"}"#)
    }

    /// 解码最后一个 chunk：finish_reason="stop"、usage 三字段齐全
    func testDecodeLastChunkWithStopAndUsage() throws {
        let json = #"{"id":"chatcmpl-2","choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(json.utf8))

        XCTAssertEqual(chunk.choices?.first?.finish_reason, "stop")
        XCTAssertNil(chunk.choices?.first?.delta?.content, "delta 为空对象时 content 应为 nil")
        XCTAssertEqual(chunk.usage?.prompt_tokens, 10)
        XCTAssertEqual(chunk.usage?.completion_tokens, 5)
        XCTAssertEqual(chunk.usage?.total_tokens, 15)
    }

    /// 解码缺字段 JSON：顶层无 usage、choices 为空数组，不抛错且属性为 nil / 空数组
    func testDecodeMissingFieldsDoesNotThrow() throws {
        // choices 为空数组 + 顶层无 usage
        let json = #"{"id":"x","choices":[]}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(json.utf8))

        XCTAssertEqual(chunk.id, "x")
        XCTAssertEqual(chunk.choices?.count, 0, "choices 为空数组")
        XCTAssertNil(chunk.usage, "无 usage 字段时为 nil")
    }

    /// 解码完全缺失 choices / usage 的极简 JSON：两者均为 nil
    func testDecodeMinimalJsonNilOptionals() throws {
        let json = #"{"id":"y"}"#
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(json.utf8))

        XCTAssertEqual(chunk.id, "y")
        XCTAssertNil(chunk.choices, "无 choices 字段时为 nil")
        XCTAssertNil(chunk.usage, "无 usage 字段时为 nil")
    }

    // MARK: - AccumulatedToolCall.toToolCallBody()

    /// 字段一一映射：id / type / function.name / function.arguments
    func testAccumulatedToolCallToToolCallBodyMapping() {
        let acc = AccumulatedToolCall(
            id: "call_1",
            type: "function",
            name: "calculate",
            arguments: #"{"expression":"1+1"}"#
        )
        let body = acc.toToolCallBody()

        XCTAssertEqual(body.id, "call_1")
        XCTAssertEqual(body.type, "function")
        XCTAssertEqual(body.function.name, "calculate")
        XCTAssertEqual(body.function.arguments, #"{"expression":"1+1"}"#)
    }

    // MARK: - ChatRequestBody.ChatMessageBody 自定义编解码

    /// encode：role 必出现；content/images/tool_call_id/tool_calls 为 nil 时不出现在 JSON 中
    func testEncodeChatMessageBodyOmitsNilOptionals() throws {
        let body = ChatRequestBody.ChatMessageBody(
            role: "user", content: nil, images: nil, tool_call_id: nil, tool_calls: nil
        )
        let dict = try encodeToDict(body)

        XCTAssertEqual(dict["role"] as? String, "user", "role 必出现")
        XCTAssertFalse(dict.keys.contains("content"), "content 为 nil 时不应出现")
        XCTAssertFalse(dict.keys.contains("images"), "images 为 nil 时不应出现")
        XCTAssertFalse(dict.keys.contains("tool_call_id"), "tool_call_id 为 nil 时不应出现")
        XCTAssertFalse(dict.keys.contains("tool_calls"), "tool_calls 为 nil 时不应出现")
    }

    /// encode：各可选字段非 nil 时均出现在 JSON 中
    func testEncodeChatMessageBodyIncludesAllOptionals() throws {
        let toolCall = ChatRequestBody.ToolCallBody(
            id: "call_1",
            type: "function",
            function: ChatRequestBody.FunctionBody(name: "calc", arguments: "{}")
        )
        let body = ChatRequestBody.ChatMessageBody(
            role: "assistant", content: "hi", images: ["img1"], tool_call_id: "call_1", tool_calls: [toolCall]
        )
        let dict = try encodeToDict(body)

        XCTAssertEqual(dict["role"] as? String, "assistant")
        XCTAssertEqual(dict["content"] as? String, "hi")
        XCTAssertEqual(dict["images"] as? [String], ["img1"])
        XCTAssertEqual(dict["tool_call_id"] as? String, "call_1")
        let toolCalls = dict["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?["id"] as? String, "call_1")
        let function = toolCalls?.first?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "calc")
        XCTAssertEqual(function?["arguments"] as? String, "{}")
    }

    /// decode：缺 content/images/tool_call_id/tool_calls 时为 nil
    func testDecodeChatMessageBodyMissingOptionalsAreNil() throws {
        let json = #"{"role":"user"}"#
        let body = try JSONDecoder().decode(ChatRequestBody.ChatMessageBody.self, from: Data(json.utf8))

        XCTAssertEqual(body.role, "user")
        XCTAssertNil(body.content)
        XCTAssertNil(body.images)
        XCTAssertNil(body.tool_call_id)
        XCTAssertNil(body.tool_calls)
    }

    /// decode：缺失 role 时抛错
    func testDecodeChatMessageBodyRoleMissingThrows() {
        let json = #"{"content":"hi"}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(ChatRequestBody.ChatMessageBody.self, from: Data(json.utf8)),
            "缺失 role 应抛错"
        )
    }

    /// round-trip：encode 后再 decode 字段一致
    func testRoundTripChatMessageBody() throws {
        let toolCall = ChatRequestBody.ToolCallBody(
            id: "call_2",
            type: "function",
            function: ChatRequestBody.FunctionBody(name: "calc", arguments: #"{"x":1}"#)
        )
        let original = ChatRequestBody.ChatMessageBody(
            role: "assistant", content: "ok", images: ["a", "b"], tool_call_id: "call_2", tool_calls: [toolCall]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatRequestBody.ChatMessageBody.self, from: data)

        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.images, original.images)
        XCTAssertEqual(decoded.tool_call_id, original.tool_call_id)
        XCTAssertEqual(decoded.tool_calls?.count, 1)
        XCTAssertEqual(decoded.tool_calls?.first?.id, "call_2")
        XCTAssertEqual(decoded.tool_calls?.first?.type, "function")
        XCTAssertEqual(decoded.tool_calls?.first?.function.name, "calc")
        XCTAssertEqual(decoded.tool_calls?.first?.function.arguments, #"{"x":1}"#)
    }

    // MARK: - AnyCodable 动态类型

    /// decode Int / Double / Bool / String 各返回对应类型与值
    func testAnyCodableDecodeScalarTypes() throws {
        func decode(_ json: String) throws -> AnyCodable {
            try JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
        }

        let intVal = try decode("42")
        XCTAssertEqual(intVal.value as? Int, 42)
        let doubleVal = try decode("1.5")
        XCTAssertEqual(doubleVal.value as? Double, 1.5)
        let boolVal = try decode("true")
        XCTAssertEqual(boolVal.value as? Bool, true)
        let strVal = try decode(#""hello""#)
        XCTAssertEqual(strVal.value as? String, "hello")
    }

    /// decode 嵌套 array 和 dict
    func testAnyCodableDecodeNestedArrayAndDict() throws {
        let arrVal = try JSONDecoder().decode(AnyCodable.self, from: Data(#"[1, "two", true]"#.utf8))
        let arr = arrVal.value as? [Any]
        XCTAssertNotNil(arr, "嵌套数组应解码为 [Any]")
        XCTAssertEqual(arr?.count, 3)
        XCTAssertEqual(arr?[0] as? Int, 1)
        XCTAssertEqual(arr?[1] as? String, "two")
        XCTAssertEqual(arr?[2] as? Bool, true)

        let dictVal = try JSONDecoder().decode(AnyCodable.self, from: Data(#"{"a":1,"b":"x"}"#.utf8))
        let dict = dictVal.value as? [String: Any]
        XCTAssertNotNil(dict, "嵌套 dict 应解码为 [String: Any]")
        XCTAssertEqual(dict?.count, 2)
        XCTAssertEqual(dict?["a"] as? Int, 1)
        XCTAssertEqual(dict?["b"] as? String, "x")
    }

    /// encode 各标量类型输出正确 JSON
    func testAnyCodableEncodeScalarTypesCorrectJSON() throws {
        func encodeString(_ val: AnyCodable) throws -> String {
            let data = try JSONEncoder().encode(val)
            return String(data: data, encoding: .utf8) ?? ""
        }

        XCTAssertEqual(try encodeString(AnyCodable(42)), "42")
        XCTAssertEqual(try encodeString(AnyCodable(1.5)), "1.5")
        XCTAssertEqual(try encodeString(AnyCodable(true)), "true")
        XCTAssertEqual(try encodeString(AnyCodable(false)), "false")
        XCTAssertEqual(try encodeString(AnyCodable("hello")), #""hello""#)
    }

    /// 当前实现对嵌套 array / dict 的 encode 落到 encodeNil 分支（记录实现行为）
    func testAnyCodableEncodeArrayAndDictCurrentBehavior() throws {
        func encodeString(_ val: AnyCodable) throws -> String {
            let data = try JSONEncoder().encode(val)
            return String(data: data, encoding: .utf8) ?? ""
        }

        // encode 未处理 [Any] / [String: Any]，落到 encodeNil()
        XCTAssertEqual(try encodeString(AnyCodable([1, 2, 3])), "null")
        XCTAssertEqual(try encodeString(AnyCodable(["a": 1])), "null")
    }

    /// round-trip：扁平 JSON Schema encode→decode→encode 一致
    func testAnyCodableRoundTripFlatSchema() throws {
        // 仅含标量值（String / Int）的扁平 schema，可正确 round-trip
        let schema: [String: AnyCodable] = [
            "type": AnyCodable("object"),
            "title": AnyCodable("Calculator"),
            "minProperties": AnyCodable(1)
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let decoder = JSONDecoder()

        let originalData = try encoder.encode(schema)
        let decoded = try decoder.decode([String: AnyCodable].self, from: originalData)
        let reencodedData = try encoder.encode(decoded)

        XCTAssertEqual(
            String(data: originalData, encoding: .utf8),
            String(data: reencodedData, encoding: .utf8),
            "扁平 schema encode→decode→encode 应一致"
        )
        // 验证解码后值类型保持
        XCTAssertEqual(decoded["type"]?.value as? String, "object")
        XCTAssertEqual(decoded["title"]?.value as? String, "Calculator")
        XCTAssertEqual(decoded["minProperties"]?.value as? Int, 1)
    }

    // MARK: - ToolDef / FunctionDef 编解码

    /// 完整 function 定义（含 parameters 嵌套 JSON Schema）解码不丢字段
    func testDecodeToolDefWithSchema() throws {
        let json = #"{"type":"function","function":{"name":"calculate","description":"计算表达式","parameters":{"type":"object","properties":{"expression":{"type":"string"}},"required":["expression"]}}}"#
        let def = try JSONDecoder().decode(ToolDef.self, from: Data(json.utf8))

        XCTAssertEqual(def.type, "function")
        XCTAssertEqual(def.function.name, "calculate")
        XCTAssertEqual(def.function.description, "计算表达式")

        let params = def.function.parameters
        XCTAssertEqual(params["type"]?.value as? String, "object")
        // 嵌套 properties 解码为字典，不丢字段
        let properties = params["properties"]?.value as? [String: Any]
        XCTAssertNotNil(properties)
        let expression = properties?["expression"] as? [String: Any]
        XCTAssertEqual(expression?["type"] as? String, "string")
        // required 解码为数组
        let required = params["required"]?.value as? [Any]
        XCTAssertEqual(required?.count, 1)
        XCTAssertEqual(required?[0] as? String, "expression")
    }

    /// ToolDef encode：标量 parameters 时顶层字段不丢
    func testEncodeToolDefPreservesFields() throws {
        let def = ToolDef(
            type: "function",
            function: ToolDef.FunctionDef(
                name: "calc",
                description: "计算",
                parameters: ["type": AnyCodable("object")]
            )
        )
        let dict = try encodeToDict(def)

        XCTAssertEqual(dict["type"] as? String, "function")
        let function = dict["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "calc")
        XCTAssertEqual(function?["description"] as? String, "计算")
        XCTAssertNotNil(function?["parameters"] as? [String: Any], "parameters 字段应出现")
    }

    // MARK: - EmbeddingResponse 解码

    /// data 数组含多条，embedding 为 Float 数组、index 正确；usage 可为 nil
    func testDecodeEmbeddingResponseMultipleData() throws {
        let json = #"{"data":[{"embedding":[0.5,0.25,1.0],"index":0},{"embedding":[0.75,0.125,2.0],"index":1}]}"#
        let resp = try JSONDecoder().decode(EmbeddingResponse.self, from: Data(json.utf8))

        XCTAssertEqual(resp.data.count, 2)
        XCTAssertEqual(resp.data[0].embedding, [0.5, 0.25, 1.0])
        XCTAssertEqual(resp.data[0].index, 0)
        XCTAssertEqual(resp.data[1].embedding, [0.75, 0.125, 2.0])
        XCTAssertEqual(resp.data[1].index, 1)
        XCTAssertNil(resp.usage, "无 usage 时为 nil")
    }

    /// usage 非空时三字段正确
    func testDecodeEmbeddingResponseWithUsage() throws {
        let json = #"{"data":[{"embedding":[1.0],"index":0}],"usage":{"prompt_tokens":3,"total_tokens":3}}"#
        let resp = try JSONDecoder().decode(EmbeddingResponse.self, from: Data(json.utf8))

        XCTAssertEqual(resp.data.count, 1)
        XCTAssertEqual(resp.data[0].embedding, [1.0])
        XCTAssertEqual(resp.usage?.prompt_tokens, 3)
        XCTAssertEqual(resp.usage?.total_tokens, 3)
    }

    /// data 为空数组时正常解码
    func testDecodeEmbeddingResponseEmptyData() throws {
        let json = #"{"data":[]}"#
        let resp = try JSONDecoder().decode(EmbeddingResponse.self, from: Data(json.utf8))

        XCTAssertEqual(resp.data.count, 0)
        XCTAssertNil(resp.usage)
    }

    // MARK: - LLMError

    /// userMessage：对每个 case 断言返回非空且符合语义
    /// 注：使用 NSLocalizedString，CI 英文环境下返回英文文案，不可断言中文关键词
    func testLLMErrorUserMessageForEachCase() {
        XCTAssertFalse(LLMError.networkError("conn").userMessage.isEmpty)

        XCTAssertFalse(LLMError.apiKeyMissing.userMessage.isEmpty)
        XCTAssertTrue(LLMError.apiKeyMissing.userMessage.contains("API Key"))

        XCTAssertFalse(LLMError.apiKeyInvalid.userMessage.isEmpty)
        XCTAssertTrue(LLMError.apiKeyInvalid.userMessage.contains("API Key"))

        XCTAssertFalse(LLMError.apiError(code: 400, message: "").userMessage.isEmpty)
        XCTAssertFalse(LLMError.apiError(code: 402, message: "").userMessage.isEmpty)
        XCTAssertFalse(LLMError.apiError(code: 429, message: "").userMessage.isEmpty)
        XCTAssertFalse(LLMError.apiError(code: 500, message: "").userMessage.isEmpty)
        XCTAssertTrue(LLMError.apiError(code: 600, message: "").userMessage.contains("600"))

        XCTAssertFalse(LLMError.timeout.userMessage.isEmpty)
        XCTAssertFalse(LLMError.unknown("e").userMessage.isEmpty)
        XCTAssertTrue(LLMError.rateLimited(retryAfter: 30).userMessage.contains("30"))
        XCTAssertEqual(LLMError.llmErrorOccurred("自定义消息").userMessage, "自定义消息")
    }

    /// errorDescription == userMessage（对所有 case）
    func testLLMErrorErrorDescriptionEqualsUserMessage() {
        let cases: [LLMError] = [
            .networkError("x"),
            .apiKeyMissing,
            .apiKeyInvalid,
            .apiError(code: 400, message: ""),
            .apiError(code: 402, message: ""),
            .apiError(code: 429, message: ""),
            .apiError(code: 500, message: ""),
            .apiError(code: 600, message: ""),
            .timeout,
            .unknown("x"),
            .rateLimited(retryAfter: 10),
            .llmErrorOccurred("msg")
        ]
        for err in cases {
            XCTAssertEqual(err.errorDescription, err.userMessage, "errorDescription 应等于 userMessage")
        }
    }

    /// fromHTTPStatus：401→apiKeyInvalid；429→apiError；500→apiError；200→apiError（默认分支）
    func testLLMErrorFromHTTPStatusMapping() {
        // 401 → apiKeyInvalid
        let err401 = LLMError.fromHTTPStatus(401, body: "")
        if case .apiKeyInvalid = err401 {
            // ok
        } else {
            XCTFail("401 应映射为 apiKeyInvalid，实际 \(err401)")
        }

        // 429 → apiError(code: 429)
        let err429 = LLMError.fromHTTPStatus(429, body: "rate")
        if case .apiError(let code, let msg) = err429 {
            XCTAssertEqual(code, 429)
            XCTAssertEqual(msg, "rate")
        } else {
            XCTFail("429 应映射为 apiError，实际 \(err429)")
        }

        // 500 → apiError(code: 500)
        let err500 = LLMError.fromHTTPStatus(500, body: "srv")
        if case .apiError(let code, _) = err500 {
            XCTAssertEqual(code, 500)
        } else {
            XCTFail("500 应映射为 apiError，实际 \(err500)")
        }

        // 200 → apiError（默认分支）
        let err200 = LLMError.fromHTTPStatus(200, body: "ok")
        if case .apiError(let code, _) = err200 {
            XCTAssertEqual(code, 200)
        } else {
            XCTFail("200 应走默认分支映射为 apiError，实际 \(err200)")
        }
    }

    // MARK: - ParsedChunk

    /// 四种组合：content=nil+toolCalls非空 / content非空+toolCalls=nil / 两者均nil / 两者均非空
    func testParsedChunkCombinations() {
        let toolCalls = [AccumulatedToolCall(id: "c1", type: "function", name: "calc", arguments: "{}")]

        // content=nil + toolCalls 非空
        let onlyTools = ParsedChunk(content: nil, toolCalls: toolCalls)
        XCTAssertNil(onlyTools.content)
        XCTAssertEqual(onlyTools.toolCalls?.count, 1)

        // content 非空 + toolCalls=nil
        let onlyContent = ParsedChunk(content: "hello", toolCalls: nil)
        XCTAssertEqual(onlyContent.content, "hello")
        XCTAssertNil(onlyContent.toolCalls)

        // 两者均 nil
        let bothNil = ParsedChunk(content: nil, toolCalls: nil)
        XCTAssertNil(bothNil.content)
        XCTAssertNil(bothNil.toolCalls)

        // 两者均非空
        let both = ParsedChunk(content: "hi", toolCalls: toolCalls)
        XCTAssertEqual(both.content, "hi")
        XCTAssertEqual(both.toolCalls?.count, 1)
    }
}
