import XCTest
import AetherFoundation
@testable import Aether

/// v1.1 Phase B: AgentInstance 单元测试。
///
/// 覆盖：
/// - 各角色 AgentInstance 的 systemPrompt 正确性
/// - execute 方法使用角色 systemPrompt 调用 LLMProvider
/// - 对话历史累积
/// - 状态变更（idle → executing → idle）
/// - 空响应错误
/// - reset 方法
@MainActor
final class AgentInstanceTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 记录调用参数并返回预设响应的 Mock LLMProvider
    final class MockLLMProvider: LLMProvider {
        var responses: [String] = ["默认响应"]
        private(set) var chatCallCount = 0
        private(set) var callMessages: [[APIMessage]] = []
        private(set) var callSystemPrompts: [String] = []
        private(set) var callConfigs: [ChatConfig] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                self.callMessages.append(messages)
                self.callSystemPrompts.append(config.systemPrompt)
                self.callConfigs.append(config)
                let index = self.chatCallCount - 1
                if index < self.responses.count {
                    continuation.yield(self.responses[index])
                }
                continuation.finish()
            }
        }

        func chat(messages: [APIMessage], config: ChatConfig, tools: [ToolDef], apiKey: String) -> AsyncStream<ParsedChunk> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                self.callMessages.append(messages)
                self.callSystemPrompts.append(config.systemPrompt)
                self.callConfigs.append(config)
                let index = self.chatCallCount - 1
                if index < self.responses.count {
                    continuation.yield(ParsedChunk(content: self.responses[index], toolCalls: nil))
                }
                continuation.finish()
            }
        }

        func embed(texts: [String], apiKey: String) async throws -> [[Float]] {
            []
        }
    }

    // MARK: - 测试夹具

    private var mockLLM: MockLLMProvider!

    override func setUpWithError() throws {
        mockLLM = MockLLMProvider()
    }

    override func tearDownWithError() throws {
        mockLLM = nil
    }

    /// 创建测试用 SubTask
    private func makeSubTask(title: String = "测试任务", description: String = "测试描述") -> SubTask {
        SubTask(title: title, description: description)
    }

    // MARK: - 初始化与角色 systemPrompt

    /// executor 角色 AgentInstance 的 role 应为 executor
    func testInitExecutorRole() {
        let instance = AgentInstance(role: .executor)
        XCTAssertEqual(instance.role, .executor)
        XCTAssertEqual(instance.status, .idle)
        XCTAssertTrue(instance.conversationHistory.isEmpty)
    }

    /// researcher 角色 AgentInstance 的 role 应为 researcher
    func testInitResearcherRole() {
        let instance = AgentInstance(role: .researcher)
        XCTAssertEqual(instance.role, .researcher)
    }

    /// critic 角色 AgentInstance 的 role 应为 critic
    func testInitCriticRole() {
        let instance = AgentInstance(role: .critic)
        XCTAssertEqual(instance.role, .critic)
    }

    /// coordinator 角色 AgentInstance 的 role 应为 coordinator
    func testInitCoordinatorRole() {
        let instance = AgentInstance(role: .coordinator)
        XCTAssertEqual(instance.role, .coordinator)
    }

    /// 自定义 ID 应正确赋值
    func testInitWithCustomID() {
        let id = UUID()
        let instance = AgentInstance(id: id, role: .planner)
        XCTAssertEqual(instance.id, id)
    }

    /// 默认 config 应使用角色对应的配置
    func testDefaultConfigMatchesRole() {
        let instance = AgentInstance(role: .researcher)
        XCTAssertEqual(instance.config.role, .researcher)
        XCTAssertNil(instance.config.model, "默认 config 的 model 应为 nil")
    }

    // MARK: - execute 方法

    /// execute 应使用角色对应的 systemPrompt 调用 LLM
    func testExecuteUsesRoleSystemPrompt() async throws {
        mockLLM.responses = ["研究完成"]
        let instance = AgentInstance(role: .researcher)
        let subTask = makeSubTask()

        _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)

        XCTAssertEqual(mockLLM.chatCallCount, 1, "应调用 LLM 一次")
        XCTAssertEqual(mockLLM.callSystemPrompts.first, AgentRole.researcher.systemPrompt,
                       "应使用 researcher 的 systemPrompt")
    }

    /// executor 角色 execute 应使用 executor systemPrompt
    func testExecuteExecutorRoleSystemPrompt() async throws {
        mockLLM.responses = ["执行完成"]
        let instance = AgentInstance(role: .executor)
        let subTask = makeSubTask()

        _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)

        XCTAssertEqual(mockLLM.callSystemPrompts.first, AgentRole.executor.systemPrompt)
    }

    /// coordinator 角色 execute 应使用 coordinator systemPrompt
    func testExecuteCoordinatorRoleSystemPrompt() async throws {
        mockLLM.responses = ["汇总完成"]
        let instance = AgentInstance(role: .coordinator)
        let subTask = makeSubTask()

        _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)

        XCTAssertEqual(mockLLM.callSystemPrompts.first, AgentRole.coordinator.systemPrompt)
    }

    /// execute 应返回 LLM 的响应内容
    func testExecuteReturnsLLMResponse() async throws {
        let expected = "这是执行结果"
        mockLLM.responses = [expected]
        let instance = AgentInstance(role: .executor)
        let subTask = makeSubTask()

        let result = try await instance.execute(subTask: subTask, llmProvider: mockLLM)

        XCTAssertEqual(result, expected)
    }

    /// execute 后对话历史应包含 system + user + assistant 三条消息
    func testExecuteAccumulatesConversationHistory() async throws {
        mockLLM.responses = ["第一次响应"]
        let instance = AgentInstance(role: .planner)
        let subTask = makeSubTask()

        _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)

        XCTAssertEqual(instance.conversationHistory.count, 3,
                       "对话历史应有 system + user + assistant 三条")
        XCTAssertEqual(instance.conversationHistory[0].role, "system")
        XCTAssertEqual(instance.conversationHistory[1].role, "user")
        XCTAssertEqual(instance.conversationHistory[2].role, "assistant")
        XCTAssertEqual(instance.conversationHistory[2].content, "第一次响应")
    }

    /// 多次 execute 应累积对话历史
    func testMultipleExecutesAccumulateHistory() async throws {
        mockLLM.responses = ["响应1", "响应2"]
        let instance = AgentInstance(role: .executor)
        let subTask1 = makeSubTask(title: "任务1")
        let subTask2 = makeSubTask(title: "任务2")

        _ = try await instance.execute(subTask: subTask1, llmProvider: mockLLM)
        _ = try await instance.execute(subTask: subTask2, llmProvider: mockLLM)

        XCTAssertEqual(instance.conversationHistory.count, 6,
                       "两次执行后应有 6 条对话历史")
        XCTAssertEqual(mockLLM.chatCallCount, 2)
    }

    // MARK: - 状态变更

    /// execute 后状态应回到 idle
    func testStatusReturnsToIdleAfterExecute() async throws {
        mockLLM.responses = ["结果"]
        let instance = AgentInstance(role: .executor)

        XCTAssertEqual(instance.status, .idle)

        _ = try await instance.execute(subTask: makeSubTask(), llmProvider: mockLLM)

        XCTAssertEqual(instance.status, .idle, "执行完成后状态应回到 idle")
    }

    // MARK: - 空响应错误

    /// LLM 返回空字符串时应抛出 emptyResponse 错误
    func testEmptyResponseThrowsError() async {
        mockLLM.responses = [""]
        let instance = AgentInstance(role: .executor)
        let subTask = makeSubTask()

        do {
            _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)
            XCTFail("空响应应抛出错误")
        } catch AgentInstance.AgentInstanceError.emptyResponse {
            // 预期错误
        } catch {
            XCTFail("应抛出 emptyResponse 错误，实际：\(error)")
        }
    }

    /// LLM 返回纯空白字符串时应抛出 emptyResponse 错误
    func testWhitespaceOnlyResponseThrowsError() async {
        mockLLM.responses = ["   \n\t  "]
        let instance = AgentInstance(role: .executor)
        let subTask = makeSubTask()

        do {
            _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)
            XCTFail("纯空白响应应抛出错误")
        } catch AgentInstance.AgentInstanceError.emptyResponse {
            // 预期错误
        } catch {
            XCTFail("应抛出 emptyResponse 错误，实际：\(error)")
        }
    }

    // MARK: - reset 方法

    /// reset 应清空对话历史并重置状态
    func testResetClearsHistoryAndStatus() async throws {
        mockLLM.responses = ["响应"]
        let instance = AgentInstance(role: .executor)
        _ = try await instance.execute(subTask: makeSubTask(), llmProvider: mockLLM)

        XCTAssertFalse(instance.conversationHistory.isEmpty, "执行后应有历史")

        instance.reset()

        XCTAssertTrue(instance.conversationHistory.isEmpty, "reset 后历史应清空")
        XCTAssertEqual(instance.status, .idle)
    }

    /// reset 不影响 id 和 role
    func testResetPreservesIDAndRole() {
        let id = UUID()
        let instance = AgentInstance(id: id, role: .critic)
        instance.reset()

        XCTAssertEqual(instance.id, id)
        XCTAssertEqual(instance.role, .critic)
    }

    // MARK: - AgentStatus

    /// AgentStatus 所有 case 应可编解码
    func testAgentStatusCodableRoundTrip() throws {
        for status in [AgentStatus.idle, .executing, .waitingForDelegation, .stopped] {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(AgentStatus.self, from: encoded)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - 自定义 config.model 传递

    /// 自定义 config.model 应传入 ChatConfig（通过 Mock 记录验证）
    func testCustomConfigModelPassedToLLMProvider() async throws {
        mockLLM.responses = ["结果"]
        let customConfig = AgentConfig(role: .executor, model: "custom-model-x")
        let instance = AgentInstance(role: .executor, config: customConfig)

        _ = try await instance.execute(subTask: makeSubTask(), llmProvider: mockLLM)

        XCTAssertEqual(mockLLM.chatCallCount, 1)
        XCTAssertEqual(mockLLM.callConfigs.first?.model, "custom-model-x",
                       "config.model 应传入 ChatConfig")
    }

    // MARK: - AgentStatus 枚举边界
    //
    // 注意：AgentInstance.status 为 private(set)，execute 仅在 idle/executing 间切换。
    // waitingForDelegation / stopped 由 AgentOrchestrator 外部管理，此处验证枚举值可用（回归保护）。

    /// AgentStatus.waitingForDelegation 应为有效且独立的枚举值
    func testWaitingForDelegationStatus() {
        let status: AgentStatus = .waitingForDelegation
        XCTAssertEqual(status, .waitingForDelegation)
        XCTAssertEqual(status.rawValue, "waitingForDelegation")
        XCTAssertNotEqual(status, .idle)
        XCTAssertNotEqual(status, .executing)
        XCTAssertNotEqual(status, .stopped)
    }

    /// AgentStatus.stopped 应为有效且独立的枚举值
    func testStoppedStatus() {
        let status: AgentStatus = .stopped
        XCTAssertEqual(status, .stopped)
        XCTAssertEqual(status.rawValue, "stopped")
        XCTAssertNotEqual(status, .idle)
        XCTAssertNotEqual(status, .executing)
        XCTAssertNotEqual(status, .waitingForDelegation)
    }

    // MARK: - LLM Provider 错误传播

    /// LLM Provider 失败（空流）时异常应传播到 execute 调用方。
    ///
    /// 注意：LLMProvider.chat 返回 AsyncStream（非 throwing），无法直接抛错。
    /// LLM 失败表现为空流（无 chunk），execute 检测到空响应后抛出 emptyResponse。
    func testLLMProviderErrorPropagates() async {
        mockLLM.responses = []  // LLM 无响应（模拟失败）
        let instance = AgentInstance(role: .executor)
        let subTask = makeSubTask()

        do {
            _ = try await instance.execute(subTask: subTask, llmProvider: mockLLM)
            XCTFail("LLM 返回空流时应抛出错误")
        } catch AgentInstance.AgentInstanceError.emptyResponse {
            // 预期：LLM 失败（空流）传播为 emptyResponse
        } catch {
            XCTFail("应抛出 emptyResponse 错误，实际：\(error)")
        }
    }
}
