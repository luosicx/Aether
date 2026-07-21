import XCTest
import SwiftData
import AetherFoundation
import AetherServices
@testable import Aether

/// P2-6 Task 10: ToolExecutionCoordinator 单元测试。
///
/// 验证 ChatViewModel ReAct 工具执行循环拆分到 ToolExecutionCoordinator 后的行为零回归。
/// 测试通过 ChatViewModel.processMessage 入口驱动 ReAct 流程（与 ChatViewModelTests 同模式），
/// 聚焦于 ToolExecutionCoordinator 应承担的职责：
/// - ToolStep / ToolStepStatus 状态迁移（running → completed / failed）
/// - 工具调用参数解析与传递
/// - 工具结果消息（role / toolCallId / toolName）字段正确性
/// - ReAct 循环上下文（assistant 消息携带 toolCalls 进入下一轮）
/// - 工具安全（未启用 / 未授权不执行）
/// - 工具审计日志（成功 / 失败均记录）
/// - ReAct 循环上限保护与超限 errorMessage
///
/// 与 ChatViewModelTests 中同名测试的关系：
/// 本测试类复用同名测试方法（不同测试类不冲突），提供 ToolExecutionCoordinator 拆分后的双重回归保护。
/// 测试数据使用不同的 call ID / 表达式，避免与 ChatViewModelTests 完全重复。
@MainActor
final class ToolExecutionCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var originalClipboardEnabled: Bool = false
    private let auditLogURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("aether.tool.audit.log")

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
        // 隔离 Keychain：使用内存后端，避免依赖真实系统 Keychain
        KeychainManager.shared.backend = InMemoryKeychainBackend()
        // 保存 read_clipboard 原始启用状态，便于恢复
        originalClipboardEnabled = ToolRegistry.shared.isEnabled(name: "read_clipboard")
        // 确保 read_clipboard 处于未授权状态
        ToolAuthorization.shared.revokeAuthorization(toolName: "read_clipboard")
        // 清理审计日志，避免历史记录干扰断言
        if let url = auditLogURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    override func tearDownWithError() throws {
        ToolRegistry.shared.setEnabled(name: "read_clipboard", value: originalClipboardEnabled)
        ToolAuthorization.shared.revokeAuthorization(toolName: "read_clipboard")
        context = nil
        container = nil
        KeychainManager.shared.backend = SystemKeychainBackend()
        if let url = auditLogURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - ReAct 循环边界

    /// ReAct 循环达到最大轮次（5 轮）且无文本产出时设置超限 errorMessage。
    /// 验证 ToolExecutionCoordinator 与 ChatViewModel.handleFinishing 协作的循环上限保护。
    func testReActLoopMaxIterationsSetsError() async throws {
        let mock = MockLLMProvider()
        mock.repeatToolCalls = true  // 每轮都 yield toolCalls，使循环达到上限
        mock.toolCalls = [
            AccumulatedToolCall(id: "loop-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"1 + 1\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "循环测试")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("循环测试", conversation: conv, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "超过最大轮次应设置 errorMessage")
        XCTAssertTrue(vm.errorMessage?.contains("5") == true,
                       "错误消息应包含最大轮次数 5")
        XCTAssertFalse(vm.isLoading, "超限后 isLoading 应为 false")
    }

    /// 一次响应包含多个工具调用：均执行成功并追加对应 tool 消息。
    /// 验证 ToolExecutionCoordinator 在单轮内串行执行多个工具的能力。
    func testMultipleToolCallsInOneResponse() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "multi-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"5 + 5\"}"),
            AccumulatedToolCall(id: "multi-2", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"6 + 6\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 5+5 和 6+6")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 5+5 和 6+6", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 2, "应创建 2 个 ToolStep")
        XCTAssertEqual(vm.currentToolSteps[0].toolName, "calculate")
        XCTAssertEqual(vm.currentToolSteps[0].status, .completed)
        XCTAssertEqual(vm.currentToolSteps[0].result, "10")
        XCTAssertEqual(vm.currentToolSteps[1].toolName, "calculate")
        XCTAssertEqual(vm.currentToolSteps[1].status, .completed)
        XCTAssertEqual(vm.currentToolSteps[1].result, "12")
        let toolMsgs = conv.messages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMsgs.count, 2, "应追加 2 条 tool 消息")
    }

    /// 工具调用带 thought 文本：chunkContent 非空时 ToolStep.thought 应记录决策文本。
    /// 验证 ToolExecutionCoordinator 正确捕获 LLM 决策文本。
    func testToolCallWithThoughtText() async throws {
        let mock = MockLLMProvider()
        mock.toolChatResponse = "需要思考一下"
        mock.toolCalls = [
            AccumulatedToolCall(id: "thought-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"3 + 3\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 3+3")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 3+3", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1)
        XCTAssertEqual(vm.currentToolSteps[0].thought, "需要思考一下",
                       "chunkContent 非空时 thought 应记录决策文本")
    }

    /// 工具调用带无效 JSON 参数：args 解析为空字典，工具返回错误字符串而非抛错。
    /// 验证 ToolExecutionCoordinator 的 JSON 容错解析。
    func testToolCallWithInvalidJSONArguments() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "invalid-json", type: "function", name: "calculate",
                                arguments: "{invalid json}")  // 无效 JSON
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        // 无效 JSON → args 为空字典 → calculate 缺少 expression，工具返回错误字符串而非抛错
        XCTAssertEqual(vm.currentToolSteps.count, 1)
        XCTAssertEqual(vm.currentToolSteps[0].status, .completed,
                       "无效 JSON 参数导致 calculate 缺少 expression，工具返回错误字符串，状态为 .completed")
    }

    /// 工具调用带空字符串参数：JSONSerialization 失败 → args 为 [:] → calculate 缺少 expression 返回错误字符串。
    /// 验证 ToolExecutionCoordinator 对空字符串参数的容错。
    func testToolCallWithEmptyStringArguments() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "empty-args", type: "function", name: "calculate",
                                arguments: "")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1)
        XCTAssertEqual(vm.currentToolSteps[0].status, .completed)
    }

    /// 工具调用参数为合法 JSON 字典时应被正确传递给工具执行。
    /// 验证 ToolExecutionCoordinator 的参数传递正确性。
    func testToolCallArgumentsPassedToExecution() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "args-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"(15 - 5) * 2\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.first?.result, "20",
                       "复杂表达式应被正确计算")
    }

    /// 工具调用成功后，下一轮 chat 的 messages 应包含 tool 角色的结果消息。
    /// 验证 ToolExecutionCoordinator 追加 tool 消息后，ReAct 循环重置 apiMessages 的行为。
    func testToolResultIncludedInNextLoopMessages() async throws {
        let mock = MockLLMProvider()
        mock.toolChatResponse = "总结中"
        mock.toolCalls = [
            AccumulatedToolCall(id: "next-loop", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"7 + 7\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算 7+7")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算 7+7", conversation: conv, modelContext: context)

        XCTAssertGreaterThanOrEqual(mock.capturedMessagesHistory.count, 2,
                                    "ReAct 应至少调用 2 次 chat：工具决策 + 结果总结")
        let secondCallMessages = mock.capturedMessagesHistory[1]
        let toolMessages = secondCallMessages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMessages.count, 1, "第二轮 chat 应包含 1 条 tool 结果消息")
        XCTAssertEqual(toolMessages.first?.content, "14", "tool 结果内容应为 14")
        XCTAssertEqual(toolMessages.first?.toolCallId, "next-loop")
        XCTAssertEqual(toolMessages.first?.toolName, "calculate")
    }

    /// 工具结果追加到 conversation 的消息应具有正确的 role / toolCallId / toolName。
    /// 验证 ToolExecutionCoordinator 构造的 ChatMessage(role: "tool", ...) 字段完整性。
    func testToolResultMessageHasCorrectRoleAndFields() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "fields-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"9 * 9\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        let toolMsgs = conv.messages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMsgs.count, 1)
        XCTAssertEqual(toolMsgs.first?.content, "81")
        XCTAssertEqual(toolMsgs.first?.toolCallId, "fields-call")
        XCTAssertEqual(toolMsgs.first?.toolName, "calculate")
    }

    /// ReAct 工具结果返回后若 LLM 不再输出 toolCalls，循环应结束并返回文本回复。
    /// 验证 ToolExecutionCoordinator 与 ReAct 循环退出条件的协作。
    func testReActLoopBreaksWhenNoToolCallsAfterResult() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "break-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"8 + 8\"}")
        ]
        mock.toolChatResponse = "结果是16"
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        let assistantMsgs = conv.messages.filter { $0.role == "assistant" }
        // 第一轮 LLM 输出 toolCalls 时会先追加一条 assistant（含 toolCallData），
        // 工具结果总结后再追加一条最终 assistant，因此总数为 2；断言最后一条非空即可。
        XCTAssertGreaterThanOrEqual(assistantMsgs.count, 1, "应至少产生 1 条 assistant 消息")
        XCTAssertFalse(assistantMsgs.last?.content.isEmpty ?? true,
                       "最后一条 assistant 消息内容不应为空")
        XCTAssertFalse(vm.isLoading)
    }

    /// 工具调用成功不应设置 errorMessage。
    /// 验证 ToolExecutionCoordinator 成功路径不污染错误状态。
    func testToolSuccessDoesNotSetErrorMessage() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "success-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"4 + 4\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        XCTAssertNil(vm.errorMessage, "工具成功执行后不应设置 errorMessage")
    }

    /// 注册一个会抛错的自定义工具，验证 ToolExecutionCoordinator catch 分支正确标记 failed。
    /// 验证 ToolExecutionCoordinator 对工具执行抛错的容错处理。
    func testCustomToolExecutionFailureMarksStepFailed() async throws {
        final class ThrowingTool: ToolProtocol, @unchecked Sendable {
            var definition: ToolDefinition {
                ToolDefinition(
                    name: "throwing_tool",
                    description: "测试用抛错工具",
                    parameters: ["type": "object", "properties": [:], "required": []]
                )
            }
            func execute(arguments: [String: Any]) async throws -> String {
                throw NSError(domain: "Test", code: 42,
                              userInfo: [NSLocalizedDescriptionKey: "工具抛错"])
            }
        }
        ToolRegistry.shared.register(tool: ThrowingTool())
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "throw-call", type: "function",
                                name: "throwing_tool", arguments: "{}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "调用")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("调用", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1)
        XCTAssertEqual(vm.currentToolSteps[0].status, .failed,
                       "自定义工具抛错时应标记 .failed")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("throwing_tool") == true,
                      "errorMessage 应包含失败工具名")
    }

    /// multiple tool calls 混合成功与失败：成功标记 completed，失败标记 failed。
    /// 验证 ToolExecutionCoordinator 在单轮内独立处理每个工具的成功/失败状态。
    func testMultipleToolCallsMixedSuccessAndFailure() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "mix-1", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"10 + 10\"}"),  // 成功
            AccumulatedToolCall(id: "mix-2", type: "function", name: "nonexistent_tool",
                                arguments: "{}")  // 失败
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "混合测试")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("混合测试", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 2, "应创建 2 个 ToolStep")
        XCTAssertEqual(vm.currentToolSteps[0].status, .completed, "calculate 应成功")
        XCTAssertEqual(vm.currentToolSteps[1].status, .failed, "nonexistent_tool 应失败")
    }

    /// 工具调用后，第二轮 chat 的 assistant 消息应携带 toolCalls（验证 ChatMessage.toAPIMessage 转换）。
    /// 验证 ToolExecutionCoordinator 持久化的 toolCallData 在下一轮被正确反序列化。
    func testToolCallAssistantMessageIncludesToolCallsInNextLoop() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(id: "assistant-call", type: "function", name: "calculate",
                                arguments: "{\"expression\": \"11 + 11\"}")
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true
        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "计算")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("计算", conversation: conv, modelContext: context)

        XCTAssertGreaterThanOrEqual(mock.capturedMessagesHistory.count, 2,
                                    "ReAct 应至少调用 2 次 chat")
        let secondCall = mock.capturedMessagesHistory[1]
        let assistantMsgs = secondCall.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1,
                       "第二轮 messages 应包含 1 条 assistant 消息")
        XCTAssertEqual(assistantMsgs.first?.toolCalls?.count, 1,
                       "assistant 消息应携带 toolCalls")
        XCTAssertEqual(assistantMsgs.first?.toolCalls?.first?.function.name, "calculate")
    }

    // MARK: - 工具安全（与 ChatViewModelToolSecurityTests 同模式，独立验证 ToolExecutionCoordinator 安全边界）

    /// terminal 工具未启用时，processMessage 不会执行该工具，并向 LLM 返回错误。
    /// 验证 ToolExecutionCoordinator 调用前 isEnabled 检查生效。
    func testTerminalToolDisabledDoesNotExecute() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "terminal-disabled", type: "function",
                name: "run_terminal_command",
                arguments: "{\"command\": \"echo blocked\"}"
            )
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "执行命令")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("执行命令", conversation: conv, modelContext: context)

        // 应创建 ToolStep 并标记为失败
        XCTAssertEqual(vm.currentToolSteps.count, 1, "应创建 1 个 ToolStep")
        let step = vm.currentToolSteps.first!
        XCTAssertEqual(step.toolName, "run_terminal_command")
        XCTAssertEqual(step.status, .failed, "未启用工具应标记为失败")
        XCTAssertNotNil(step.result, "失败结果不应为空")

        // 应向 LLM 返回包含错误描述的 tool 消息
        let toolMsgs = conv.messages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMsgs.count, 1, "应向 LLM 返回 1 条 tool 错误消息")
        let errorContent = toolMsgs.first?.content ?? ""
        XCTAssertTrue(
            errorContent.contains("失败") || errorContent.contains("未启用") || errorContent.contains("未注册"),
            "tool 错误消息应说明失败原因"
        )
        XCTAssertNotNil(vm.errorMessage, "应设置 errorMessage")
    }

    /// read_clipboard 未授权时，processMessage 不会调用 ClipboardTool，并向 LLM 返回错误。
    /// 验证 ToolExecutionCoordinator 调用前 requiresAuthorization + presentConfirmation 检查生效。
    func testReadClipboardUnauthorizedDoesNotExecute() async throws {
        // 确保工具已启用但未被授权
        ToolRegistry.shared.setEnabled(name: "read_clipboard", value: true)
        ToolAuthorization.shared.revokeAuthorization(toolName: "read_clipboard")

        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "clipboard-unauthorized", type: "function",
                name: "read_clipboard",
                arguments: "{}"
            )
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "读取剪贴板")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("读取剪贴板", conversation: conv, modelContext: context)

        XCTAssertEqual(vm.currentToolSteps.count, 1)
        let step = vm.currentToolSteps.first!
        XCTAssertEqual(step.toolName, "read_clipboard")
        XCTAssertEqual(step.status, .failed, "未授权时应标记为失败")

        let toolMsgs = conv.messages.filter { $0.role == "tool" }
        XCTAssertEqual(toolMsgs.count, 1)
        let errorContent = toolMsgs.first?.content ?? ""
        XCTAssertTrue(
            errorContent.contains("拒绝") || errorContent.contains("失败") || errorContent.contains("未授权"),
            "tool 错误消息应说明授权失败"
        )
    }

    /// 工具调用失败时，ToolAuditLogger 应被调用并记录工具名 + authorized=false。
    /// 验证 ToolExecutionCoordinator 失败路径的审计日志写入。
    func testToolFailureIsAudited() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "audit-call", type: "function",
                name: "run_terminal_command",
                arguments: "{}"
            )
        ]
        let vm = ChatViewModel(client: mock)
        vm.selectedProvider = .onDevice
        vm.toolsEnabled = true

        let conv = Conversation(title: "测试", systemPrompt: "你是助手")
        context.insert(conv)
        let userMsg = ChatMessage(role: "user", content: "审计测试")
        userMsg.conversation = conv
        conv.messages.append(userMsg)

        await vm.processMessage("审计测试", conversation: conv, modelContext: context)

        // 异步等待审计日志写入文件
        guard let url = auditLogURL else {
            XCTFail("无法获取审计日志文件路径")
            return
        }
        let expectation = XCTestExpectation(description: "审计日志写入文件")
        var logContent = ""
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               text.contains("run_terminal_command") {
                logContent = text
                expectation.fulfill()
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertTrue(logContent.contains("run_terminal_command"), "审计日志应包含工具名")
        XCTAssertTrue(logContent.contains("authorized=false"), "审计日志应记录未授权/失败状态")
    }
}
