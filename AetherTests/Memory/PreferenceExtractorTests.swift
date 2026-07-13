import XCTest
import SwiftData
@testable import Aether

/// Task 6: PreferenceExtractor 与 UserPreference 新字段单元测试。
///
/// 覆盖范围：
/// - UserPreference 新字段默认值与全参数初始化（aiPersona/aiPersonaDescription/avatarData/themeName/bubbleStyle/fontSize/lineHeight）
/// - PreferenceExtraction Codable round-trip 与 Hashable
/// - PreferenceExtractor.buildExtractionPrompt 生成的 prompt 含对话历史与字段约定
/// - PreferenceExtractor.parsePreferences 解析能力（含 markdown fence、纯 JSON、前后额外文本、无效 JSON）
/// - PreferenceExtractor.extract 端到端流程（mock LLMProvider，含多 chunk 累积、空响应、无效 JSON）
@MainActor
final class PreferenceExtractorTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 可配置返回内容的 Mock LLMProvider，用于测试 PreferenceExtractor.extract。
    /// chat 流将依次 yield `chatContents` 中的内容片段；记录调用次数与最后一次 user 消息。
    final class MockLLMProvider: LLMProvider {
        /// chat 流将依次 yield 的内容片段
        var chatContents: [String] = []
        /// 记录 chat 被调用次数
        private(set) var chatCallCount = 0
        /// 记录最后一次 chat 收到的 user 消息内容
        private(set) var lastUserMessage: String?
        /// embed 调用返回值（测试中未使用）
        var embedResult: [[Float]] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                if let userMsg = messages.first(where: { $0.role == "user" }) {
                    self.lastUserMessage = userMsg.content
                }
                for content in self.chatContents {
                    continuation.yield(content)
                }
                continuation.finish()
            }
        }

        func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                for content in self.chatContents {
                    continuation.yield(ParsedChunk(content: content, toolCalls: nil))
                }
                continuation.finish()
            }
        }

        func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            embedResult
        }
    }

    // MARK: - 测试夹具

    /// 带 markdown fence 的偏好 JSON 响应（含 3 条偏好：tone/tool/fact）
    private let sampleJSONWithFence = """
    ```json
    [
      {"category": "tone", "value": "正式", "confidence": 0.9},
      {"category": "tool", "value": "calculate", "confidence": 0.8},
      {"category": "fact", "value": "我是素食者", "confidence": 1.0}
    ]
    ```
    """

    /// 无 fence 的纯 JSON 响应（含 persona 偏好）
    private let samplePureJSON = """
    [
      {"category": "persona", "value": "温柔的姐姐", "confidence": 0.7}
    ]
    """

    /// 空数组 JSON 响应
    private let sampleEmptyArrayJSON = "[]"

    // MARK: - UserPreference 新字段默认值

    /// UserPreference 默认初始化：新增字段应正确设置默认值
    func testUserPreferenceDefaultValues() {
        let pref = UserPreference()

        // 原有字段
        XCTAssertEqual(pref.preferredTone, "默认", "默认 preferredTone 应为「默认」")
        XCTAssertEqual(pref.preferredTools, [], "默认 preferredTools 应为空数组")
        XCTAssertEqual(pref.customFact, "", "默认 customFact 应为空字符串")

        // Task 6 新增字段
        XCTAssertEqual(pref.aiPersona, "", "默认 aiPersona 应为空字符串")
        XCTAssertEqual(pref.aiPersonaDescription, "", "默认 aiPersonaDescription 应为空字符串")
        XCTAssertNil(pref.avatarData, "默认 avatarData 应为 nil")
        XCTAssertEqual(pref.themeName, "deepSpace", "默认 themeName 应为 deepSpace")
        XCTAssertEqual(pref.bubbleStyle, "liquidGlass", "默认 bubbleStyle 应为 liquidGlass")
        XCTAssertEqual(pref.fontSize, 16.0, accuracy: 0.001, "默认 fontSize 应为 16.0")
        XCTAssertEqual(pref.lineHeight, 1.5, accuracy: 0.001, "默认 lineHeight 应为 1.5")
    }

    /// UserPreference 全参数初始化：应正确设置所有字段
    func testUserPreferenceFullInit() {
        let avatarBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let pref = UserPreference(
            preferredTone: "轻松",
            preferredTools: ["calculate", "web_search"],
            customFact: "我在北京工作",
            aiPersona: "小以太",
            aiPersonaDescription: "温柔且专业的助手",
            avatarData: avatarBytes,
            themeName: "aurora",
            bubbleStyle: "minimal",
            fontSize: 18.0,
            lineHeight: 1.8
        )

        XCTAssertEqual(pref.preferredTone, "轻松")
        XCTAssertEqual(pref.preferredTools, ["calculate", "web_search"])
        XCTAssertEqual(pref.customFact, "我在北京工作")
        XCTAssertEqual(pref.aiPersona, "小以太")
        XCTAssertEqual(pref.aiPersonaDescription, "温柔且专业的助手")
        XCTAssertEqual(pref.avatarData, avatarBytes, "avatarData 应为传入的 Data")
        XCTAssertEqual(pref.themeName, "aurora")
        XCTAssertEqual(pref.bubbleStyle, "minimal")
        XCTAssertEqual(pref.fontSize, 18.0, accuracy: 0.001)
        XCTAssertEqual(pref.lineHeight, 1.8, accuracy: 0.001)
    }

    /// UserPreference 部分初始化：仅传入新增字段，原有字段使用默认值
    func testUserPreferencePartialInitNewFieldsOnly() {
        let pref = UserPreference(
            aiPersona: "小以太",
            themeName: "dawn",
            bubbleStyle: "card",
            fontSize: 14.0
        )

        XCTAssertEqual(pref.preferredTone, "默认", "未传入 preferredTone 应为默认值")
        XCTAssertEqual(pref.preferredTools, [], "未传入 preferredTools 应为默认值")
        XCTAssertEqual(pref.customFact, "", "未传入 customFact 应为默认值")
        XCTAssertEqual(pref.aiPersona, "小以太")
        XCTAssertNil(pref.avatarData)
        XCTAssertEqual(pref.themeName, "dawn")
        XCTAssertEqual(pref.bubbleStyle, "card")
        XCTAssertEqual(pref.fontSize, 14.0, accuracy: 0.001)
        XCTAssertEqual(pref.lineHeight, 1.5, accuracy: 0.001, "未传入 lineHeight 应为默认值 1.5")
    }

    // MARK: - PreferenceExtraction Codable

    /// PreferenceExtraction Codable round-trip：编码后解码应保持一致
    func testPreferenceExtractionCodableRoundTrip() throws {
        let extraction = PreferenceExtraction(category: "tone", value: "正式", confidence: 0.9)
        let encoded = try JSONEncoder().encode(extraction)
        let decoded = try JSONDecoder().decode(PreferenceExtraction.self, from: encoded)

        XCTAssertEqual(decoded.category, "tone")
        XCTAssertEqual(decoded.value, "正式")
        XCTAssertEqual(decoded.confidence, 0.9, accuracy: 0.001)
    }

    /// PreferenceExtraction 数组 Codable round-trip
    func testPreferenceExtractionArrayCodableRoundTrip() throws {
        let extractions = [
            PreferenceExtraction(category: "tone", value: "轻松", confidence: 0.8),
            PreferenceExtraction(category: "fact", value: "我是素食者", confidence: 1.0),
            PreferenceExtraction(category: "persona", value: "严谨的学者", confidence: 0.6)
        ]
        let encoded = try JSONEncoder().encode(extractions)
        let decoded = try JSONDecoder().decode([PreferenceExtraction].self, from: encoded)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].category, "tone")
        XCTAssertEqual(decoded[0].value, "轻松")
        XCTAssertEqual(decoded[0].confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(decoded[1].category, "fact")
        XCTAssertEqual(decoded[1].value, "我是素食者")
        XCTAssertEqual(decoded[2].category, "persona")
        XCTAssertEqual(decoded[2].value, "严谨的学者")
    }

    /// PreferenceExtraction Hashable：可放入 Set
    func testPreferenceExtractionHashable() {
        let a = PreferenceExtraction(category: "tone", value: "正式", confidence: 0.9)
        let b = PreferenceExtraction(category: "tone", value: "正式", confidence: 0.9)
        let c = PreferenceExtraction(category: "tone", value: "正式", confidence: 0.5)

        XCTAssertEqual(a, b, "字段全等的两个实例应相等")
        XCTAssertNotEqual(a, c, "confidence 不同应不相等")

        let set: Set<PreferenceExtraction> = [a, b, c]
        XCTAssertEqual(set.count, 2, "a 与 b 相同应去重，c 不同应保留")
    }

    /// PreferenceExtraction 从 JSON 字符串解码
    func testPreferenceExtractionDecodeFromJSONString() throws {
        let jsonString = """
        {"category": "tool", "value": "calculate", "confidence": 0.85}
        """
        let data = jsonString.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PreferenceExtraction.self, from: data)

        XCTAssertEqual(decoded.category, "tool")
        XCTAssertEqual(decoded.value, "calculate")
        XCTAssertEqual(decoded.confidence, 0.85, accuracy: 0.001)
    }

    // MARK: - PreferenceExtractor.buildExtractionPrompt

    /// buildExtractionPrompt 应包含对话历史与字段约定
    func testBuildExtractionPromptContainsHistoryAndFields() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let messages = [
            ChatMessage(role: "user", content: "请用正式的语气回复"),
            ChatMessage(role: "assistant", content: "好的，我将使用正式语气")
        ]
        let prompt = extractor.buildExtractionPrompt(messages: messages)

        XCTAssertTrue(prompt.contains("请用正式的语气回复"), "prompt 应包含 user 消息内容")
        XCTAssertTrue(prompt.contains("好的，我将使用正式语气"), "prompt 应包含 assistant 消息内容")
        XCTAssertTrue(prompt.contains("用户"), "prompt 应包含「用户」角色标签")
        XCTAssertTrue(prompt.contains("助手"), "prompt 应包含「助手」角色标签")
        XCTAssertTrue(prompt.contains("category"), "prompt 应包含 category 字段约定")
        XCTAssertTrue(prompt.contains("value"), "prompt 应包含 value 字段约定")
        XCTAssertTrue(prompt.contains("confidence"), "prompt 应包含 confidence 字段约定")
        XCTAssertTrue(prompt.contains("tone"), "prompt 应包含 tone 类别说明")
        XCTAssertTrue(prompt.contains("tool"), "prompt 应包含 tool 类别说明")
        XCTAssertTrue(prompt.contains("fact"), "prompt 应包含 fact 类别说明")
        XCTAssertTrue(prompt.contains("persona"), "prompt 应包含 persona 类别说明")
    }

    /// buildExtractionPrompt 不同对话历史应生成不同 prompt
    func testBuildExtractionPromptDifferentMessages() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let messagesA = [ChatMessage(role: "user", content: "对话 A")]
        let messagesB = [ChatMessage(role: "user", content: "对话 B")]

        let promptA = extractor.buildExtractionPrompt(messages: messagesA)
        let promptB = extractor.buildExtractionPrompt(messages: messagesB)

        XCTAssertNotEqual(promptA, promptB, "不同对话应生成不同 prompt")
        XCTAssertTrue(promptA.contains("对话 A"))
        XCTAssertTrue(promptB.contains("对话 B"))
    }

    /// buildExtractionPrompt 应仅包含 user / assistant 消息，跳过 system / tool
    func testBuildExtractionPromptFiltersRoles() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let messages = [
            ChatMessage(role: "system", content: "系统提示词"),
            ChatMessage(role: "user", content: "用户消息"),
            ChatMessage(role: "assistant", content: "助手消息"),
            ChatMessage(role: "tool", content: "工具结果")
        ]
        let prompt = extractor.buildExtractionPrompt(messages: messages)

        XCTAssertTrue(prompt.contains("用户消息"), "应包含 user 消息")
        XCTAssertTrue(prompt.contains("助手消息"), "应包含 assistant 消息")
        XCTAssertFalse(prompt.contains("系统提示词"), "不应包含 system 消息")
        XCTAssertFalse(prompt.contains("工具结果"), "不应包含 tool 消息")
    }

    /// buildExtractionPrompt 应跳过空内容的消息
    func testBuildExtractionPromptSkipsEmptyContent() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let messages = [
            ChatMessage(role: "user", content: ""),
            ChatMessage(role: "user", content: "   "),
            ChatMessage(role: "assistant", content: "有效内容")
        ]
        let prompt = extractor.buildExtractionPrompt(messages: messages)

        XCTAssertTrue(prompt.contains("有效内容"), "应包含非空消息")
        // 验证对话历史部分仅含一条「助手：有效内容」
        let historyStart = prompt.range(of: "对话历史：")
        XCTAssertNotNil(historyStart, "prompt 应包含「对话历史：」标记")
        let historySection = prompt[historyStart!.upperBound...]
        XCTAssertFalse(historySection.contains("用户："), "空内容的 user 消息应被跳过")
    }

    /// buildExtractionPrompt 空对话应生成包含空历史的 prompt
    func testBuildExtractionPromptEmptyMessages() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let prompt = extractor.buildExtractionPrompt(messages: [])

        XCTAssertTrue(prompt.contains("对话历史："), "空对话 prompt 仍应包含「对话历史：」标记")
        XCTAssertTrue(prompt.contains("category"), "空对话 prompt 仍应包含字段约定")
    }

    // MARK: - PreferenceExtractor.parsePreferences

    /// parsePreferences 解析带 markdown fence 的 JSON
    func testParsePreferencesWithFence() throws {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let preferences = try extractor.parsePreferences(from: sampleJSONWithFence)

        XCTAssertEqual(preferences.count, 3, "应解析出 3 条偏好")
        XCTAssertEqual(preferences[0].category, "tone")
        XCTAssertEqual(preferences[0].value, "正式")
        XCTAssertEqual(preferences[0].confidence, 0.9, accuracy: 0.001)
        XCTAssertEqual(preferences[1].category, "tool")
        XCTAssertEqual(preferences[1].value, "calculate")
        XCTAssertEqual(preferences[2].category, "fact")
        XCTAssertEqual(preferences[2].value, "我是素食者")
    }

    /// parsePreferences 解析无 fence 的纯 JSON
    func testParsePreferencesPureJSON() throws {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let preferences = try extractor.parsePreferences(from: samplePureJSON)

        XCTAssertEqual(preferences.count, 1)
        XCTAssertEqual(preferences[0].category, "persona")
        XCTAssertEqual(preferences[0].value, "温柔的姐姐")
        XCTAssertEqual(preferences[0].confidence, 0.7, accuracy: 0.001)
    }

    /// parsePreferences 解析空数组 JSON
    func testParsePreferencesEmptyArray() throws {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let preferences = try extractor.parsePreferences(from: sampleEmptyArrayJSON)

        XCTAssertEqual(preferences.count, 0, "空数组应解析为 0 条偏好")
    }

    /// parsePreferences 解析 LLM 在 JSON 前后添加额外文本的场景
    func testParsePreferencesWithSurroundingText() throws {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let response = """
        好的，以下是提取的偏好：

        [{"category": "tone", "value": "幽默", "confidence": 0.6}]

        希望对您有帮助！
        """
        let preferences = try extractor.parsePreferences(from: response)

        XCTAssertEqual(preferences.count, 1)
        XCTAssertEqual(preferences[0].category, "tone")
        XCTAssertEqual(preferences[0].value, "幽默")
    }

    /// parsePreferences 解析多行格式化的 JSON
    func testParsePreferencesMultilineJSON() throws {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let response = """
        [
          {
            "category": "fact",
            "value": "我在北京工作",
            "confidence": 1.0
          },
          {
            "category": "tone",
            "value": "轻松",
            "confidence": 0.8
          }
        ]
        """
        let preferences = try extractor.parsePreferences(from: response)

        XCTAssertEqual(preferences.count, 2)
        XCTAssertEqual(preferences[0].category, "fact")
        XCTAssertEqual(preferences[0].value, "我在北京工作")
        XCTAssertEqual(preferences[1].category, "tone")
        XCTAssertEqual(preferences[1].value, "轻松")
    }

    /// parsePreferences 无 JSON 数组时抛 invalidJSON
    func testParsePreferencesNoArray() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        XCTAssertThrowsError(try extractor.parsePreferences(from: "没有 JSON 数组的内容")) { error in
            guard let err = error as? PreferenceExtractor.PreferenceExtractionError else {
                XCTFail("应抛出 PreferenceExtractionError")
                return
            }
            if case .invalidJSON = err {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON，实际：\(err)")
            }
        }
    }

    /// parsePreferences 解析无效 JSON 抛 invalidJSON
    func testParsePreferencesInvalidJSON() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let badJSON = "[{\"category\": \"缺右括号\""
        XCTAssertThrowsError(try extractor.parsePreferences(from: badJSON)) { error in
            guard let err = error as? PreferenceExtractor.PreferenceExtractionError else {
                XCTFail("应抛出 PreferenceExtractionError")
                return
            }
            if case .invalidJSON = err {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON，实际：\(err)")
            }
        }
    }

    /// parsePreferences 字段类型不匹配时抛 invalidJSON
    func testParsePreferencesTypeMismatch() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let badJSON = "[{\"category\": \"tone\", \"value\": \"正式\", \"confidence\": \"不是数字\"}]"
        XCTAssertThrowsError(try extractor.parsePreferences(from: badJSON)) { error in
            guard let err = error as? PreferenceExtractor.PreferenceExtractionError else {
                XCTFail("应抛出 PreferenceExtractionError")
                return
            }
            if case .invalidJSON = err {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON，实际：\(err)")
            }
        }
    }

    /// parsePreferences 缺失字段时抛 invalidJSON（category/value 必填）
    func testParsePreferencesMissingRequiredFields() {
        let extractor = PreferenceExtractor(llmProvider: MockLLMProvider())
        let incompleteJSON = "[{\"category\": \"tone\"}]"
        XCTAssertThrowsError(try extractor.parsePreferences(from: incompleteJSON)) { error in
            guard let err = error as? PreferenceExtractor.PreferenceExtractionError else {
                XCTFail("应抛出 PreferenceExtractionError")
                return
            }
            if case .invalidJSON = err {
                // 预期路径：缺失 value 与 confidence 应解码失败
            } else {
                XCTFail("应抛出 .invalidJSON，实际：\(err)")
            }
        }
    }

    // MARK: - PreferenceExtractor.extract 端到端

    /// extract 正常流程：mock 返回带 fence 的 JSON，验证返回偏好列表
    func testExtractSuccess() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = [sampleJSONWithFence]
        let extractor = PreferenceExtractor(llmProvider: mock)

        let messages = [
            ChatMessage(role: "user", content: "请用正式的语气回复"),
            ChatMessage(role: "assistant", content: "好的")
        ]
        let preferences = try await extractor.extract(from: messages)

        XCTAssertEqual(preferences.count, 3, "应返回 3 条偏好")
        XCTAssertEqual(preferences[0].category, "tone")
        XCTAssertEqual(preferences[0].value, "正式")
        XCTAssertEqual(preferences[1].category, "tool")
        XCTAssertEqual(preferences[2].category, "fact")
        XCTAssertEqual(mock.chatCallCount, 1, "应调用 LLMProvider.chat 一次")
        XCTAssertNotNil(mock.lastUserMessage, "应记录最后一次 user 消息")
        XCTAssertTrue(mock.lastUserMessage?.contains("请用正式的语气回复") ?? false, "user 消息应包含对话历史")
    }

    /// extract 多 chunk 累积：mock 分多次返回 JSON 片段
    func testExtractMultipleChunksAccumulated() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = [
            "[{\"category\": \"tone\",",
            "\"value\": \"轻松\",",
            "\"confidence\": 0.8}]"
        ]
        let extractor = PreferenceExtractor(llmProvider: mock)

        let preferences = try await extractor.extract(from: [ChatMessage(role: "user", content: "用轻松的语气")])

        XCTAssertEqual(preferences.count, 1)
        XCTAssertEqual(preferences[0].category, "tone")
        XCTAssertEqual(preferences[0].value, "轻松")
        XCTAssertEqual(preferences[0].confidence, 0.8, accuracy: 0.001)
    }

    /// extract 返回空数组 JSON 时应返回空偏好列表
    func testExtractEmptyArrayReturnsEmpty() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["[]"]
        let extractor = PreferenceExtractor(llmProvider: mock)

        let preferences = try await extractor.extract(from: [ChatMessage(role: "user", content: "你好")])

        XCTAssertEqual(preferences.count, 0, "空数组 JSON 应返回空偏好列表")
    }

    /// extract LLM 返回空内容时抛 emptyResponse
    func testExtractEmptyResponseThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = []
        let extractor = PreferenceExtractor(llmProvider: mock)

        do {
            _ = try await extractor.extract(from: [ChatMessage(role: "user", content: "你好")])
            XCTFail("空响应应抛出错误")
        } catch let error as PreferenceExtractor.PreferenceExtractionError {
            if case .emptyResponse = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .emptyResponse，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 PreferenceExtractionError，实际：\(error)")
        }
    }

    /// extract LLM 返回仅空白字符时抛 emptyResponse
    func testExtractWhitespaceOnlyThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = ["   \n  \t  \n"]
        let extractor = PreferenceExtractor(llmProvider: mock)

        do {
            _ = try await extractor.extract(from: [ChatMessage(role: "user", content: "你好")])
            XCTFail("空白响应应抛出错误")
        } catch let error as PreferenceExtractor.PreferenceExtractionError {
            if case .emptyResponse = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .emptyResponse，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 PreferenceExtractionError")
        }
    }

    /// extract LLM 返回无效 JSON 时抛 invalidJSON
    func testExtractInvalidJSONThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = ["这不是 JSON"]
        let extractor = PreferenceExtractor(llmProvider: mock)

        do {
            _ = try await extractor.extract(from: [ChatMessage(role: "user", content: "你好")])
            XCTFail("无效 JSON 应抛出错误")
        } catch let error as PreferenceExtractor.PreferenceExtractionError {
            if case .invalidJSON = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 PreferenceExtractionError")
        }
    }

    /// extract 空对话列表也应能正常调用（prompt 中历史为空）
    func testExtractEmptyMessages() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["[]"]
        let extractor = PreferenceExtractor(llmProvider: mock)

        let preferences = try await extractor.extract(from: [])

        XCTAssertEqual(preferences.count, 0)
        XCTAssertEqual(mock.chatCallCount, 1, "应调用 chat 一次")
    }

    /// extract 应将 prompt 作为 user 消息传递给 LLMProvider
    func testExtractPassesPromptAsUserMessage() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = ["[]"]
        let extractor = PreferenceExtractor(llmProvider: mock)

        let messages = [ChatMessage(role: "user", content: "我是素食者")]
        _ = try await extractor.extract(from: messages)

        XCTAssertNotNil(mock.lastUserMessage, "应记录 user 消息")
        XCTAssertTrue(mock.lastUserMessage?.contains("我是素食者") ?? false, "user 消息应包含对话历史")
        XCTAssertTrue(mock.lastUserMessage?.contains("category") ?? false, "user 消息应包含字段约定")
    }
}
