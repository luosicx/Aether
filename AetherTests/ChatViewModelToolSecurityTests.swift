import XCTest
import SwiftData
@testable import Aether

/// ChatViewModel 工具安全集成测试：验证未启用/未授权工具不会被真实执行，并向 LLM 返回错误。
@MainActor
final class ChatViewModelToolSecurityTests: XCTestCase {
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

    // MARK: - 高危工具未启用

    /// terminal 工具未启用时，processMessage 不会执行该工具，并向 LLM 返回错误。
    func testTerminalToolDisabledDoesNotExecute() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "call-terminal", type: "function",
                name: "run_terminal_command",
                arguments: "{\"command\": \"echo pwned\"}"
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

    // MARK: - 敏感工具未授权

    /// read_clipboard 未授权时，processMessage 不会调用 ClipboardTool，并向 LLM 返回错误。
    func testReadClipboardUnauthorizedDoesNotExecute() async throws {
        // 确保工具已启用但未被授权
        ToolRegistry.shared.setEnabled(name: "read_clipboard", value: true)
        ToolAuthorization.shared.revokeAuthorization(toolName: "read_clipboard")

        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "call-clipboard", type: "function",
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

    // MARK: - 审计日志

    /// 工具调用失败时，ToolAuditLogger 应被调用并记录工具名。
    func testToolFailureIsAudited() async throws {
        let mock = MockLLMProvider()
        mock.toolCalls = [
            AccumulatedToolCall(
                id: "call-audit", type: "function",
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
