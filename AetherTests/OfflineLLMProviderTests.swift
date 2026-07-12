import XCTest
@testable import Aether

/// Day 16: 端侧离线 LLM Provider 单元测试。
/// OfflineLLMProvider 为 nonisolated class，将请求转发给 MLXInferenceEngine（actor）。
/// 模拟器环境 mlx-swift 未集成，走占位分支：chat 返回提示流、loadModel 抛 loadFailed。
final class OfflineLLMProviderTests: XCTestCase {

    /// 构造一条 user 消息，供 chat 调用使用。
    private func makeMessages() -> [APIMessage] {
        [APIMessage(role: "user", content: "你好", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)]
    }

    // MARK: - 1. chat 流式返回占位 token

    func testChatStreamsTokens() async {
        let provider = OfflineLLMProvider()
        let stream = provider.chat(messages: makeMessages(), config: .default, apiKey: "")

        var tokens: [String] = []
        for await chunk in stream {
            tokens.append(chunk)
        }

        XCTAssertFalse(tokens.isEmpty, "占位模式应至少收到一个 token")
        XCTAssertTrue(
            tokens.joined().contains(NSLocalizedString("[端侧推理不可用：mlx-swift 未集成]", comment: "")),
            "占位模式应返回 mlx-swift 未集成提示，实际：\(tokens.joined())"
        )
    }

    // MARK: - 2. tools 非空 → 发 .llmErrorOccurred 通知（"端侧模型不支持工具调用"）

    func testChatWithToolsThrowsUnsupported() async {
        let provider = OfflineLLMProvider()
        let tool = ToolDef(
            type: "function",
            function: ToolDef.FunctionDef(name: "noop", description: "无操作", parameters: [:])
        )

        // 通知 expectation：捕获 .llmErrorOccurred 通知中的 LLMError
        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        // 消费流：tools 非空时流应立即 finish，不 yield 任何 chunk
        let stream = provider.chat(messages: makeMessages(), config: .default, tools: [tool], apiKey: "")
        var chunks: [ParsedChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        XCTAssertTrue(chunks.isEmpty, "tools 非空时不应 yield 任何 chunk")

        // 等待通知（实现中通过 Task { @MainActor in ... } 异步 post）
        await fulfillment(of: [expectation], timeout: 2.0)

        guard case .llmErrorOccurred(let msg) = capturedError else {
            XCTFail("期望 .llmErrorOccurred，实际：\(String(describing: capturedError))")
            return
        }
        XCTAssertTrue(
            msg.contains(NSLocalizedString("端侧模型不支持工具调用，已自动切换到云端", comment: "")),
            "通知消息应含 '端侧模型不支持工具调用'，实际：\(msg)"
        )
    }

    // MARK: - 3. embed 返回非空占位向量

    func testEmbedReturnsPlaceholderVectors() async throws {
        let provider = OfflineLLMProvider()
        let vectors = try await provider.embed(texts: ["你好", "世界"], apiKey: "")

        XCTAssertEqual(vectors.count, 2, "应返回 2 个向量（对应 2 条文本）")
        for vec in vectors {
            XCTAssertEqual(vec.count, 384, "占位向量应为 384 维")
        }
        // 相同输入应产生确定性输出（hash 占位语义）
        let again = try await provider.embed(texts: ["你好"], apiKey: "")
        XCTAssertEqual(again.first?.count, 384)
    }

    // MARK: - 4. MLXInferenceEngine.loadModel 抛 loadFailed（模拟器 mlx-swift 不可用）

    func testLoadModelThrowsWhenMLXUnavailable() async {
        // 重置引擎状态，避免上次加载结果干扰
        await MLXInferenceEngine.shared.unloadModel()

        // 创建临时文件作为模型路径，绕过 modelNotFound 检查，直达 mlx-swift 占位分支
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model-\(UUID().uuidString).mlpackage")
        try? Data("placeholder".utf8).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        do {
            // expectedSHA256 为空跳过校验，模拟器无 mlx-swift → loadFailed 占位分支
            try await MLXInferenceEngine.shared.loadModel(path: tmpURL)
            XCTFail("模拟器环境（mlx-swift 不可用）应抛 OnDeviceError.loadFailed")
        } catch let error as OnDeviceError {
            if case .loadFailed = error {
                // 期望命中
            } else {
                XCTFail("期望 .loadFailed，实际 OnDeviceError：\(error)")
            }
            // lastLoadError 应被同步设置
            let lastErr = await MLXInferenceEngine.shared.lastLoadError
            if case .loadFailed = lastErr {
                // 期望命中
            } else {
                XCTFail("期望 lastLoadError 为 .loadFailed，实际：\(String(describing: lastErr))")
            }
        } catch {
            XCTFail("应抛 OnDeviceError，实际：\(error)")
        }
    }

    // MARK: - 5. embed 空入参短路返回空数组

    func testEmbedEmptyInputReturnsEmptyArray() async throws {
        let provider = OfflineLLMProvider()
        let result = try await provider.embed(texts: [], apiKey: "")
        XCTAssertEqual(result, [], "空入参应返回空数组")
    }

    // MARK: - 6. embed 单条文本返回 384 维向量

    func testEmbedSingleTextReturns384Dims() async throws {
        let provider = OfflineLLMProvider()
        let result = try await provider.embed(texts: ["test"], apiKey: "")
        XCTAssertEqual(result.count, 1, "应返回 1 个向量")
        XCTAssertEqual(result[0].count, 384, "向量应为 384 维")
    }

    // MARK: - 7. embed 确定性输出（相同输入 → 相同输出）

    func testEmbedDeterministicOutput() async throws {
        let provider = OfflineLLMProvider()
        let v1 = try await provider.embed(texts: ["确定性测试"], apiKey: "")
        let v2 = try await provider.embed(texts: ["确定性测试"], apiKey: "")
        XCTAssertEqual(v1.first?.count, 384)
        XCTAssertEqual(v2.first?.count, 384)
        // 逐元素比较
        if let a = v1.first, let b = v2.first {
            for i in 0..<384 {
                XCTAssertEqual(a[i], b[i], accuracy: 1e-6, "相同输入应产生相同向量（index=\(i)）")
            }
        }
    }

    // MARK: - 8. embed 不同文本产生不同向量

    func testEmbedDifferentTextsProduceDifferentVectors() async throws {
        let provider = OfflineLLMProvider()
        let vectors = try await provider.embed(texts: ["苹果", "香蕉"], apiKey: "")
        XCTAssertEqual(vectors.count, 2)
        var diffCount = 0
        for i in 0..<384 {
            if abs(vectors[0][i] - vectors[1][i]) > 1e-6 {
                diffCount += 1
            }
        }
        XCTAssertGreaterThan(diffCount, 0, "不同文本应产生不同向量")
    }

    // MARK: - 9. embed L2 归一化（非空文本的向量范数应 ≈ 1.0）

    func testEmbedL2NormApproximatelyOne() async throws {
        let provider = OfflineLLMProvider()
        let vectors = try await provider.embed(texts: ["归一化测试文本"], apiKey: "")
        guard let vec = vectors.first else {
            XCTFail("应返回至少一个向量")
            return
        }
        let norm = sqrt(vec.reduce(Float(0)) { $0 + $1 * $1 })
        XCTAssertEqual(norm, Float(1.0), accuracy: Float(1e-4),
                       "非空文本的 L2 范数应 ≈ 1.0，实际：\(norm)")
    }

    // MARK: - 10. embed 多条文本向量数量匹配

    func testEmbedMultipleTextsCountMatches() async throws {
        let provider = OfflineLLMProvider()
        let texts = ["文本一", "文本二", "文本三", "文本四", "文本五"]
        let vectors = try await provider.embed(texts: texts, apiKey: "")
        XCTAssertEqual(vectors.count, texts.count, "向量数量应与文本数量匹配")
        for vec in vectors {
            XCTAssertEqual(vec.count, 384, "每个向量应为 384 维")
        }
    }

    // MARK: - 11. embed 纯 ASCII 文本也能正确生成向量

    func testEmbedASCIIText() async throws {
        let provider = OfflineLLMProvider()
        let vectors = try await provider.embed(texts: ["hello world 123"], apiKey: "")
        XCTAssertEqual(vectors.count, 1)
        XCTAssertEqual(vectors[0].count, 384)
        // 纯 ASCII 文本也应被归一化
        let norm = sqrt(vectors[0].reduce(Float(0)) { $0 + $1 * $1 })
        XCTAssertEqual(norm, Float(1.0), accuracy: Float(1e-4),
                       "ASCII 文本向量也应归一化")
    }

    // MARK: - 12. chat 空工具数组 → 退化为纯文本 chat（yield ParsedChunk）

    func testChatWithEmptyToolsDegradesToTextChat() async {
        let provider = OfflineLLMProvider()
        let stream = provider.chat(
            messages: makeMessages(),
            config: .default,
            tools: [],
            apiKey: ""
        )
        var chunks: [ParsedChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        // 空工具数组应走纯文本 chat 分支，至少 yield 一个 chunk
        XCTAssertFalse(chunks.isEmpty, "空工具数组应退化为纯文本 chat，至少 yield 一个 chunk")
    }

    // MARK: - 13. chat 含 system 消息时不重复前置 systemPrompt

    func testChatWithSystemMessageInMessages() async {
        let provider = OfflineLLMProvider()
        let messages = [
            APIMessage(role: "system", content: "你是助手", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: "你好", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]
        let stream = provider.chat(messages: messages, config: .default, apiKey: "")
        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }
        // 含 system 消息时应正常生成（不崩溃、有输出）
        XCTAssertFalse(tokens.isEmpty, "含 system 消息的 chat 应正常生成 token")
    }

    // MARK: - 14. chat 多角色消息拼接（user + assistant + user）

    func testChatWithMultiTurnMessages() async {
        let provider = OfflineLLMProvider()
        let messages = [
            APIMessage(role: "user", content: "你好", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "assistant", content: "你好！有什么可以帮你的？", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil),
            APIMessage(role: "user", content: "今天天气如何", images: nil, toolCallId: nil, toolName: nil, toolCalls: nil)
        ]
        let stream = provider.chat(messages: messages, config: .default, apiKey: "")
        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }
        XCTAssertFalse(tokens.isEmpty, "多轮对话应正常生成 token")
    }
}
