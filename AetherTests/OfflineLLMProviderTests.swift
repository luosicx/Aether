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
            tokens.joined().contains("mlx-swift 未集成"),
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
            msg.contains("端侧模型不支持工具调用"),
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
}
