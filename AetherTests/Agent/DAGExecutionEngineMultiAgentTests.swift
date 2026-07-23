import XCTest
import SwiftData
import AetherFoundation
@testable import Aether

/// v1.1 Phase B: DAGExecutionEngine 多 Agent 协作测试。
///
/// 覆盖：
/// - SubTask.assignedRole 角色路由到对应 AgentInstance
/// - SubTask.delegatedTo 跨 Agent 委派通过 MessageBus
/// - AgentOrchestrator.createAgent / routeToAgent
/// - 多 Agent 混合执行（角色路由 + 委派 + 默认 executor）
/// - 向后兼容：无 assignedRole/delegatedTo 时回退到默认流程
@MainActor
final class DAGExecutionEngineMultiAgentTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 按调用顺序返回预设响应的 Mock LLMProvider
    final class MockLLMProvider: LLMProvider {
        var responses: [String] = []
        private(set) var chatCallCount = 0
        private(set) var callSystemPrompts: [String] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                self.callSystemPrompts.append(config.systemPrompt)
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
                self.callSystemPrompts.append(config.systemPrompt)
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

    private var container: ModelContainer!
    private var context: ModelContext!
    private var mockLLM: MockLLMProvider!
    private var orchestrator: AgentOrchestrator!

    private let zeroDelayPolicy = RetryPolicy(maxAttempts: 1, initialDelay: 0, backoffMultiplier: 1.0)

    override func setUpWithError() throws {
        let schema = Schema([AgentTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        mockLLM = MockLLMProvider()
        orchestrator = AgentOrchestrator(modelContext: context, llmProvider: mockLLM)
    }

    override func tearDownWithError() throws {
        orchestrator = nil
        mockLLM = nil
        context = nil
        container = nil
    }

    /// 创建无依赖的子任务
    private func makeSubTask(title: String, assignedRole: AgentRole? = nil, delegatedTo: UUID? = nil) -> SubTask {
        SubTask(title: title, description: "\(title)描述", assignedRole: assignedRole, delegatedTo: delegatedTo)
    }

    // MARK: - SubTask 新字段默认值

    /// SubTask 默认创建时 assignedRole 和 delegatedTo 应为 nil
    func testSubTaskDefaultFieldsAreNil() {
        let sub = SubTask(title: "测试")
        XCTAssertNil(sub.assignedRole, "assignedRole 默认应为 nil")
        XCTAssertNil(sub.delegatedTo, "delegatedTo 默认应为 nil")
    }

    /// SubTask 自定义 assignedRole 应正确赋值
    func testSubTaskCustomAssignedRole() {
        let sub = SubTask(title: "研究任务", assignedRole: .researcher)
        XCTAssertEqual(sub.assignedRole, .researcher)
    }

    /// SubTask 自定义 delegatedTo 应正确赋值
    func testSubTaskCustomDelegatedTo() {
        let id = UUID()
        let sub = SubTask(title: "委派任务", delegatedTo: id)
        XCTAssertEqual(sub.delegatedTo, id)
    }

    /// SubTask Codable 往返应保持 assignedRole 和 delegatedTo
    func testSubTaskCodableRoundTripWithNewFields() throws {
        let original = SubTask(title: "测试", description: "描述", assignedRole: .coordinator, delegatedTo: UUID())

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubTask.self, from: data)

        XCTAssertEqual(decoded.assignedRole, .coordinator)
        XCTAssertEqual(decoded.delegatedTo, original.delegatedTo)
    }

    /// SubTask 解码时缺失 assignedRole/delegatedTo 应默认 nil（向后兼容）
    func testSubTaskDecodingMissingNewFields() throws {
        let json = """
        {"title": "旧任务", "description": "旧格式", "dependencies": [], "order": 0, "parallel": false, "depth": 1}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SubTask.self, from: json)
        XCTAssertNil(decoded.assignedRole, "缺失 assignedRole 应默认 nil")
        XCTAssertNil(decoded.delegatedTo, "缺失 delegatedTo 应默认 nil")
    }

    // MARK: - AgentOrchestrator 多 Agent 管理

    /// createAgent 应返回有效 UUID 并注册到 agentInstances
    func testCreateAgentReturnsValidUUID() {
        let id = orchestrator.createAgent(role: .researcher)
        XCTAssertNotNil(orchestrator.agentInstance(id: id), "创建后应能通过 ID 查找")
        XCTAssertEqual(orchestrator.agentInstance(id: id)?.role, .researcher)
    }

    /// createAgent 应更新角色索引
    func testCreateAgentUpdatesRoleIndex() {
        let id = orchestrator.createAgent(role: .critic)
        XCTAssertEqual(orchestrator.agentID(forRole: .critic), id, "角色索引应指向新创建的实例")
    }

    /// 同一角色创建多个 Agent 时，角色索引取首个
    func testCreateMultipleAgentsSameRole() {
        let id1 = orchestrator.createAgent(role: .researcher)
        let id2 = orchestrator.createAgent(role: .researcher)

        XCTAssertEqual(orchestrator.agentID(forRole: .researcher), id1, "角色索引应保持首个")
        XCTAssertNotNil(orchestrator.agentInstance(id: id2), "第二个实例也应注册")
    }

    /// removeAgent 应从 agentInstances 移除
    func testRemoveAgent() {
        let id = orchestrator.createAgent(role: .coordinator)
        XCTAssertNotNil(orchestrator.agentInstance(id: id))

        orchestrator.removeAgent(id: id)
        XCTAssertNil(orchestrator.agentInstance(id: id), "移除后应返回 nil")
        XCTAssertNil(orchestrator.agentID(forRole: .coordinator), "角色索引也应清除")
    }

    // MARK: - routeToAgent 路由

    /// routeToAgent 按 delegatedTo 路由
    func testRouteToAgentByDelegatedTo() {
        let id = orchestrator.createAgent(role: .researcher)
        let sub = makeSubTask(title: "委派任务", delegatedTo: id)

        let instance = orchestrator.routeToAgent(subTask: sub)
        XCTAssertNotNil(instance, "应路由到指定 Agent")
        XCTAssertEqual(instance?.id, id)
    }

    /// routeToAgent 按 assignedRole 路由
    func testRouteToAgentByAssignedRole() {
        let id = orchestrator.createAgent(role: .critic)
        let sub = makeSubTask(title: "角色任务", assignedRole: .critic)

        let instance = orchestrator.routeToAgent(subTask: sub)
        XCTAssertNotNil(instance, "应路由到 critic Agent")
        XCTAssertEqual(instance?.id, id)
    }

    /// routeToAgent 优先使用 delegatedTo（即使 assignedRole 也已设置）
    func testRouteToAgentDelegatedToTakesPrecedence() {
        let id1 = orchestrator.createAgent(role: .researcher)
        let id2 = orchestrator.createAgent(role: .critic)
        let sub = makeSubTask(title: "混合", assignedRole: .researcher, delegatedTo: id2)

        let instance = orchestrator.routeToAgent(subTask: sub)
        XCTAssertEqual(instance?.id, id2, "delegatedTo 应优先于 assignedRole")
    }

    /// routeToAgent 无匹配时返回 nil（向后兼容）
    func testRouteToAgentReturnsNilWhenNoMatch() {
        let sub = makeSubTask(title: "普通任务")
        XCTAssertNil(orchestrator.routeToAgent(subTask: sub), "无路由信息时应返回 nil")
    }

    /// routeToAgent 角色无对应 Agent 时返回 nil
    func testRouteToAgentReturnsNilWhenRoleNotRegistered() {
        let sub = makeSubTask(title: "角色任务", assignedRole: .coordinator)
        XCTAssertNil(orchestrator.routeToAgent(subTask: sub), "未注册 coordinator Agent 时应返回 nil")
    }

    // MARK: - 角色路由执行

    /// assignedRole 为 researcher 的子任务应使用 researcher 的 systemPrompt
    func testAssignedRoleRoutingUsesCorrectSystemPrompt() async throws {
        orchestrator.createAgent(role: .researcher)
        mockLLM.responses = ["研究结果"]

        let task = AgentTask(goal: "测试")
        let sub = makeSubTask(title: "调研任务", assignedRole: .researcher)
        task.updateSubTasks([sub])
        context.insert(task)

        try await orchestrator.resumeTask(task)
        try await orchestrator.executeAll()

        XCTAssertEqual(mockLLM.chatCallCount, 1)
        XCTAssertEqual(mockLLM.callSystemPrompts.first, AgentRole.researcher.systemPrompt,
                       "应使用 researcher 的 systemPrompt")
        XCTAssertEqual(sub.status, .completed)
    }

    /// 多个不同角色的子任务应路由到各自 AgentInstance 执行
    func testMultipleRoleRouting() async throws {
        orchestrator.createAgent(role: .researcher)
        orchestrator.createAgent(role: .critic)
        mockLLM.responses = ["研究结果", "批判结果"]

        let task = AgentTask(goal: "测试")
        let sub1 = makeSubTask(title: "研究", assignedRole: .researcher)
        var sub2 = makeSubTask(title: "批判", assignedRole: .critic)
        sub2.dependencies = [sub1.id]
        task.updateSubTasks([sub1, sub2])
        context.insert(task)

        try await orchestrator.resumeTask(task)
        try await orchestrator.executeAll()

        XCTAssertEqual(mockLLM.chatCallCount, 2)
        XCTAssertEqual(mockLLM.callSystemPrompts[0], AgentRole.researcher.systemPrompt)
        XCTAssertEqual(mockLLM.callSystemPrompts[1], AgentRole.critic.systemPrompt)
        XCTAssertTrue(task.isAllSubTasksCompleted)
    }

    // MARK: - 跨 Agent 委派

    /// delegatedTo 非空时通过 MessageBus 委派并等待结果
    func testCrossAgentDelegationViaMessageBus() async throws {
        let researcherID = orchestrator.createAgent(role: .researcher)
        mockLLM.responses = ["委派研究结果"]

        let task = AgentTask(goal: "测试委派")
        let sub = makeSubTask(title: "委派任务", delegatedTo: researcherID)
        task.updateSubTasks([sub])
        context.insert(task)

        try await orchestrator.resumeTask(task)
        try await orchestrator.executeAll()

        XCTAssertEqual(mockLLM.chatCallCount, 1, "应通过委派调用 LLM 一次")
        XCTAssertEqual(mockLLM.callSystemPrompts.first, AgentRole.researcher.systemPrompt,
                       "委派执行应使用 researcher 的 systemPrompt")
        XCTAssertEqual(sub.status, .completed, "委派任务应完成")
        XCTAssertEqual(sub.result, "委派研究结果")
    }

    /// 委派给不存在的 Agent 应导致任务失败
    func testDelegationToNonexistentAgentFails() async throws {
        let nonexistentID = UUID()
        mockLLM.responses = ["不应到达"]

        let task = AgentTask(goal: "测试失败委派")
        let sub = makeSubTask(title: "无效委派", delegatedTo: nonexistentID)
        task.updateSubTasks([sub])
        context.insert(task)

        try await orchestrator.resumeTask(task)

        // 委派失败应导致执行错误（超时或 ERROR 结果）
        do {
            try await orchestrator.executeAll()
            // 如果没抛错，检查任务状态
            // 任务可能标记为 failed（因为委派返回 ERROR）
            XCTAssertTrue(sub.status == .failed || task.status == .failed,
                          "委派给不存在的 Agent 应导致失败")
        } catch {
            // 抛错也是可接受的
            XCTAssertTrue(task.status == .failed || task.status == .inProgress)
        }
    }

    // MARK: - 混合执行

    /// 混合执行：角色路由 + 委派 + 默认 executor
    func testMixedExecution() async throws {
        orchestrator.createAgent(role: .researcher)
        let coordinatorID = orchestrator.createAgent(role: .coordinator)
        mockLLM.responses = [
            "默认执行结果",      // 默认 executor
            "研究结果",          // researcher 角色路由
            "协调结果"           // coordinator 委派
        ]

        let task = AgentTask(goal: "混合测试")
        let sub1 = makeSubTask(title: "默认任务")  // 默认 executor
        var sub2 = makeSubTask(title: "研究任务", assignedRole: .researcher)  // 角色路由
        var sub3 = makeSubTask(title: "协调任务", delegatedTo: coordinatorID)  // 委派
        sub2.dependencies = [sub1.id]
        sub3.dependencies = [sub2.id]
        task.updateSubTasks([sub1, sub2, sub3])
        context.insert(task)

        try await orchestrator.resumeTask(task)
        try await orchestrator.executeAll()

        XCTAssertEqual(mockLLM.chatCallCount, 3, "三个子任务各调用 LLM 一次")
        XCTAssertTrue(task.isAllSubTasksCompleted, "所有子任务应完成")

        // 验证结果
        XCTAssertEqual(sub1.result, "默认执行结果")
        XCTAssertEqual(sub2.result, "研究结果")
        XCTAssertEqual(sub3.result, "协调结果")
    }

    // MARK: - 向后兼容

    /// 无 assignedRole 和 delegatedTo 时回退到默认 executor 流程
    func testBackwardCompatibilityNoRoutingFields() async throws {
        mockLLM.responses = ["默认结果1", "默认结果2"]

        let task = AgentTask(goal: "兼容性测试")
        let sub1 = makeSubTask(title: "任务1")
        var sub2 = makeSubTask(title: "任务2")
        sub2.dependencies = [sub1.id]
        task.updateSubTasks([sub1, sub2])
        context.insert(task)

        try await orchestrator.resumeTask(task)
        try await orchestrator.executeAll()

        XCTAssertEqual(mockLLM.chatCallCount, 2)
        XCTAssertTrue(task.isAllSubTasksCompleted)
        // 应使用 executor 角色 systemPrompt（默认流程）
        XCTAssertEqual(mockLLM.callSystemPrompts[0], AgentRole.executor.systemPrompt)
        XCTAssertEqual(mockLLM.callSystemPrompts[1], AgentRole.executor.systemPrompt)
    }

    /// 即使创建了 Agent 实例，无路由字段的子任务仍走默认流程
    func testAgentInstancesExistButNoRoutingFieldsUsesDefault() async throws {
        orchestrator.createAgent(role: .researcher)
        orchestrator.createAgent(role: .critic)
        mockLLM.responses = ["默认结果"]

        let task = AgentTask(goal: "测试")
        let sub = makeSubTask(title: "无路由任务")  // 无 assignedRole/delegatedTo
        task.updateSubTasks([sub])
        context.insert(task)

        try await orchestrator.resumeTask(task)
        try await orchestrator.executeAll()

        XCTAssertEqual(mockLLM.callSystemPrompts.first, AgentRole.executor.systemPrompt,
                       "无路由字段时应使用 executor systemPrompt")
    }

    // MARK: - messageBus 回退与级联跳过

    /// 测试用错误类型（模拟委派/执行失败）
    private struct DelegationTestError: Error, Sendable {}

    /// messageBus 为 nil 时引擎应回退到单 Agent 流程正常执行（向后兼容）
    func testDAGEngineWithNilMessageBusFallsBackToSingleAgent() async throws {
        let engine = DAGExecutionEngine(messageBus: nil)
        XCTAssertNil(engine.messageBus, "messageBus 应为 nil")

        let task = AgentTask(goal: "单 Agent 回退测试")
        let sub = makeSubTask(title: "简单任务")
        task.updateSubTasks([sub])
        context.insert(task)

        try await engine.run(task) { _ in
            return "单 Agent 结果"
        }

        XCTAssertEqual(sub.status, .completed, "无 messageBus 时单 Agent 流程应正常完成")
        XCTAssertEqual(sub.result, "单 Agent 结果")
    }

    /// 子任务执行失败时，依赖该子任务的下游子任务应被自动 skip（级联跳过）
    func testDelegationFailureCascadesSkipDependents() async throws {
        let engine = DAGExecutionEngine(retryPolicy: zeroDelayPolicy, messageBus: nil)

        let task = AgentTask(goal: "级联跳过测试")
        let sub1 = makeSubTask(title: "失败任务")
        var sub2 = makeSubTask(title: "下游任务")
        sub2.dependencies = [sub1.id]
        task.updateSubTasks([sub1, sub2])
        context.insert(task)

        let failingID = sub1.id
        try await engine.run(task) { sub in
            if sub.id == failingID {
                throw DelegationTestError()
            }
            return "下游结果"
        }

        XCTAssertEqual(sub1.status, .failed, "失败任务应标记为 failed")
        XCTAssertEqual(sub2.status, .skipped, "依赖失败任务的下游应被 skip")
    }
}
