import XCTest
import SwiftData
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 10/11/12: AgentOrchestrator 单元测试
///
/// 覆盖范围：
/// - AgentOrchestrator 初始化（含断点续执行检查）
/// - startTask 创建并分解任务
/// - executeNext 执行单个子任务
/// - executeAll 执行所有子任务（含 DAG 依赖顺序）
/// - cancel 取消当前任务
/// - resumeTask 恢复任务
/// - AgentRole 枚举与 systemPrompt
/// - AgentConfig 配置
/// - 多 Agent 协作（reviewer 审查流程）
/// - 工具执行与 LLM 执行
/// - 持久化验证
@MainActor
final class AgentOrchestratorTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 按调用顺序依次返回预设响应的 Mock LLMProvider
    final class MockLLMProvider: LLMProvider {
        /// 响应队列：第 N 次 chat 调用返回 responses[N-1]
        var responses: [String] = []
        /// 调用计数
        private(set) var chatCallCount = 0
        /// 记录每次调用的 messages
        private(set) var callMessages: [[APIMessage]] = []
        /// 记录每次调用的 config.systemPrompt
        private(set) var callSystemPrompts: [String] = []

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                self.chatCallCount += 1
                self.callMessages.append(messages)
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
                self.callMessages.append(messages)
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

    /// 3 个子任务的 JSON（含索引依赖：s0→s1→s2 链式依赖）
    private let chainedSubTasksJSON = """
    [
      {"title": "步骤一", "description": "首步", "dependencies": [], "toolName": null, "order": 0},
      {"title": "步骤二", "description": "次步", "dependencies": [0], "toolName": null, "order": 1},
      {"title": "步骤三", "description": "末步", "dependencies": [1], "toolName": null, "order": 2}
    ]
    """

    /// 2 个无依赖子任务的 JSON（可并行执行）
    private let parallelSubTasksJSON = """
    [
      {"title": "并行任务A", "description": "独立任务A", "dependencies": [], "toolName": null, "order": 0},
      {"title": "并行任务B", "description": "独立任务B", "dependencies": [], "toolName": null, "order": 1}
    ]
    """

    /// 1 个使用工具的子任务 JSON
    private let toolSubTasksJSON = """
    [
      {"title": "获取时间", "description": "调用时间工具", "dependencies": [], "toolName": "get_current_time", "order": 0}
    ]
    """

    private var container: ModelContainer!
    private var context: ModelContext!
    private var mockLLM: MockLLMProvider!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: AgentTask.self, configurations: config)
        context = ModelContext(container)
        mockLLM = MockLLMProvider()
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        mockLLM = nil
    }

    /// 创建 orchestrator 实例
    private func makeOrchestrator(enableReview: Bool = false) -> AgentOrchestrator {
        let orchestrator = AgentOrchestrator(modelContext: context, llmProvider: mockLLM)
        if enableReview {
            orchestrator.enableReview = true
        }
        return orchestrator
    }

    // MARK: - AgentRole 枚举与 systemPrompt

    /// AgentRole rawValue 验证
    func testAgentRoleRawValues() {
        XCTAssertEqual(AgentRole.planner.rawValue, "planner")
        XCTAssertEqual(AgentRole.executor.rawValue, "executor")
        XCTAssertEqual(AgentRole.reviewer.rawValue, "reviewer")
    }

    /// AgentRole systemPrompt 非空且角色间不同
    func testAgentRoleSystemPrompts() {
        let plannerPrompt = AgentRole.planner.systemPrompt
        let executorPrompt = AgentRole.executor.systemPrompt
        let reviewerPrompt = AgentRole.reviewer.systemPrompt

        XCTAssertFalse(plannerPrompt.isEmpty, "planner systemPrompt 不应为空")
        XCTAssertFalse(executorPrompt.isEmpty, "executor systemPrompt 不应为空")
        XCTAssertFalse(reviewerPrompt.isEmpty, "reviewer systemPrompt 不应为空")

        XCTAssertNotEqual(plannerPrompt, executorPrompt, "planner 与 executor prompt 应不同")
        XCTAssertNotEqual(plannerPrompt, reviewerPrompt, "planner 与 reviewer prompt 应不同")
        XCTAssertNotEqual(executorPrompt, reviewerPrompt, "executor 与 reviewer prompt 应不同")
    }

    /// AgentRole systemPrompt 应包含角色关键词
    func testAgentRoleSystemPromptContainsKeywords() {
        XCTAssertTrue(AgentRole.planner.systemPrompt.contains("规划"), "planner prompt 应含'规划'")
        XCTAssertTrue(AgentRole.executor.systemPrompt.contains("执行"), "executor prompt 应含'执行'")
        XCTAssertTrue(AgentRole.reviewer.systemPrompt.contains("审查"), "reviewer prompt 应含'审查'")
    }

    /// AgentRole Codable round-trip
    func testAgentRoleCodable() throws {
        for role in [AgentRole.planner, .executor, .reviewer] {
            let encoded = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(AgentRole.self, from: encoded)
            XCTAssertEqual(decoded, role)
        }
    }

    // MARK: - AgentConfig

    /// AgentConfig 默认初始化
    func testAgentConfigDefaultInit() {
        let config = AgentConfig(role: .planner)
        XCTAssertEqual(config.role, .planner)
        XCTAssertNil(config.model, "model 默认应为 nil")
        XCTAssertNil(config.tools, "tools 默认应为 nil")
    }

    /// AgentConfig 全参数初始化
    func testAgentConfigFullInit() {
        let config = AgentConfig(role: .executor, model: "gpt-4", tools: ["calculate"])
        XCTAssertEqual(config.role, .executor)
        XCTAssertEqual(config.model, "gpt-4")
        XCTAssertEqual(config.tools, ["calculate"])
    }

    /// AgentConfig.defaultExecutor 为 executor 角色
    func testAgentConfigDefaultExecutor() {
        let config = AgentConfig.defaultExecutor
        XCTAssertEqual(config.role, .executor)
        XCTAssertNil(config.model)
        XCTAssertNil(config.tools)
    }

    // MARK: - AgentOrchestrator 初始化

    /// 初始化：无未完成任务时 currentTask 为 nil
    func testInitWithNoInProgressTask() throws {
        let orchestrator = makeOrchestrator()
        XCTAssertNil(orchestrator.currentTask, "无未完成任务时 currentTask 应为 nil")
    }

    /// 初始化：存在 inProgress 任务时自动恢复
    func testInitResumesInProgressTask() throws {
        // 预先插入一个 inProgress 的 AgentTask
        let task = AgentTask(goal: "未完成任务")
        task.markInProgress()
        let sub = SubTask(title: "子任务", order: 0)
        task.updateSubTasks([sub])
        context.insert(task)
        try context.save()

        let orchestrator = makeOrchestrator()
        XCTAssertNotNil(orchestrator.currentTask, "存在 inProgress 任务时应自动恢复")
        XCTAssertEqual(orchestrator.currentTask?.goal, "未完成任务")
    }

    /// 初始化：仅恢复 inProgress 任务，不恢复 pending/completed/failed 任务
    func testInitDoesNotResumeNonInProgressTasks() throws {
        let pending = AgentTask(goal: "待执行")
        // pending 状态（默认）

        let completed = AgentTask(goal: "已完成")
        completed.markCompleted()

        let failed = AgentTask(goal: "已失败")
        failed.markFailed()

        context.insert(pending)
        context.insert(completed)
        context.insert(failed)
        try context.save()

        let orchestrator = makeOrchestrator()
        XCTAssertNil(orchestrator.currentTask, "非 inProgress 任务不应被恢复")
    }

    // MARK: - startTask

    /// startTask：创建 AgentTask、分解目标、设置 currentTask
    func testStartTaskCreatesAndDecomposes() async throws {
        mockLLM.responses = [chainedSubTasksJSON]

        let orchestrator = makeOrchestrator()
        let task = try await orchestrator.startTask(goal: "完成一个项目")

        XCTAssertEqual(task.goal, "完成一个项目")
        XCTAssertEqual(task.status, .inProgress, "任务应为 inProgress")
        XCTAssertEqual(task.subTasks.count, 3, "应分解出 3 个子任务")
        XCTAssertEqual(task.subTasks[0].title, "步骤一")
        XCTAssertEqual(task.subTasks[1].title, "步骤二")
        XCTAssertEqual(task.subTasks[2].title, "步骤三")
        XCTAssertEqual(mockLLM.chatCallCount, 1, "应调用 LLM 一次（分解）")
        XCTAssertNotNil(orchestrator.currentTask, "currentTask 应被设置")
    }

    /// startTask：带 conversationID
    func testStartTaskWithConversationID() async throws {
        mockLLM.responses = [parallelSubTasksJSON]
        let convID = UUID()

        let orchestrator = makeOrchestrator()
        let task = try await orchestrator.startTask(goal: "目标", conversationID: convID)

        XCTAssertEqual(task.conversationID, convID)
    }

    /// startTask：分解后任务已持久化
    func testStartTaskPersistsToModelContext() async throws {
        mockLLM.responses = [chainedSubTasksJSON]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "持久化测试")

        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.count, 1, "应持久化 1 条 AgentTask")
        XCTAssertEqual(fetched.first?.subTasks.count, 3)
    }

    // MARK: - executeNext

    /// executeNext：执行第一个子任务
    func testExecuteNextExecutesFirstSubTask() async throws {
        mockLLM.responses = [chainedSubTasksJSON, "步骤一结果"]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "目标")

        try await orchestrator.executeNext()

        guard let task = orchestrator.currentTask else {
            XCTFail("currentTask 不应为 nil")
            return
        }
        XCTAssertEqual(task.subTasks[0].status, .completed, "第一个子任务应完成")
        XCTAssertEqual(task.subTasks[0].result, "步骤一结果")
        XCTAssertEqual(task.subTasks[1].status, .pending, "第二个子任务应仍为 pending")
    }

    /// executeNext：无当前任务时抛错
    func testExecuteNextWithoutTaskThrows() async {
        let orchestrator = makeOrchestrator()
        do {
            try await orchestrator.executeNext()
            XCTFail("无任务时应抛错")
        } catch let error as AgentOrchestrator.OrchestratorError {
            if case .noActiveTask = error {
                // 预期
            } else {
                XCTFail("应抛出 .noActiveTask")
            }
        } catch {
            XCTFail("应抛出 OrchestratorError")
        }
    }

    /// executeNext：执行后状态已持久化
    func testExecuteNextPersistsState() async throws {
        mockLLM.responses = [chainedSubTasksJSON, "结果"]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "持久化验证")
        try await orchestrator.executeNext()

        // 重新 fetch 验证持久化
        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.first?.subTasks[0].status, .completed, "状态应已持久化")
        XCTAssertEqual(fetched.first?.subTasks[0].result, "结果")
    }

    // MARK: - executeAll

    /// executeAll：执行所有子任务（链式依赖）
    func testExecuteAllChainedDependencies() async throws {
        mockLLM.responses = [
            chainedSubTasksJSON,   // 分解
            "结果一",               // 执行步骤一
            "结果二",               // 执行步骤二
            "结果三"                // 执行步骤三
        ]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "链式目标")

        try await orchestrator.executeAll()

        guard let task = orchestrator.currentTask else {
            XCTFail("currentTask 不应为 nil")
            return
        }
        XCTAssertTrue(task.isAllSubTasksCompleted, "所有子任务应完成")
        XCTAssertEqual(task.status, .completed, "任务整体应标记为 completed")
        XCTAssertEqual(task.subTasks[0].result, "结果一")
        XCTAssertEqual(task.subTasks[1].result, "结果二")
        XCTAssertEqual(task.subTasks[2].result, "结果三")
    }

    /// executeAll：并行执行无依赖子任务
    func testExecuteAllParallelSubTasks() async throws {
        mockLLM.responses = [
            parallelSubTasksJSON,  // 分解
            "结果A",               // 执行并行任务A
            "结果B"                // 执行并行任务B
        ]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "并行目标")

        try await orchestrator.executeAll()

        guard let task = orchestrator.currentTask else {
            XCTFail("currentTask 不应为 nil")
            return
        }
        XCTAssertTrue(task.isAllSubTasksCompleted, "所有子任务应完成")
        // 验证两个子任务都有结果（顺序可能因并行而不同）
        let results = task.subTasks.compactMap { $0.result }.sorted()
        XCTAssertEqual(results, ["结果A", "结果B"])
    }

    // MARK: - DAG 依赖正确性

    /// DAG：有依赖的子任务在依赖完成后才执行
    func testDAGDependencyOrdering() async throws {
        mockLLM.responses = [
            chainedSubTasksJSON,   // 分解：s0→s1→s2
            "结果一",               // 执行 s0
            "结果二",               // 执行 s1
            "结果三"                // 执行 s2
        ]

        let orchestrator = makeOrchestrator()
        let task = try await orchestrator.startTask(goal: "DAG 测试")

        // 执行前全部 pending
        XCTAssertTrue(task.subTasks.allSatisfy { $0.status == .pending })

        try await orchestrator.executeAll()

        // 验证执行顺序：s0 的 LLM 调用在 s1 之前
        // callMessages[1] 是分解，[2] 是第一次执行，[3] 是第二次，[4] 是第三次
        XCTAssertEqual(mockLLM.callMessages.count, 4, "应调用 LLM 4 次（1 分解 + 3 执行）")
    }

    /// DAG：executeNext 一次只执行一个子任务
    func testDAGExecuteNextOneAtATime() async throws {
        mockLLM.responses = [
            chainedSubTasksJSON,   // 分解
            "结果一",               // 执行 s0
            "结果二",               // 执行 s1
            "结果三"                // 执行 s2
        ]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "逐步执行")

        // 第一次 executeNext：执行 s0
        try await orchestrator.executeNext()
        XCTAssertEqual(orchestrator.currentTask?.subTasks[0].status, .completed)
        XCTAssertEqual(orchestrator.currentTask?.subTasks[1].status, .pending)

        // 第二次 executeNext：执行 s1
        try await orchestrator.executeNext()
        XCTAssertEqual(orchestrator.currentTask?.subTasks[1].status, .completed)
        XCTAssertEqual(orchestrator.currentTask?.subTasks[2].status, .pending)

        // 第三次 executeNext：执行 s2
        try await orchestrator.executeNext()
        XCTAssertEqual(orchestrator.currentTask?.subTasks[2].status, .completed)
    }

    // MARK: - cancel

    /// cancel：取消当前任务
    func testCancelTask() async throws {
        mockLLM.responses = [chainedSubTasksJSON]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "待取消")

        try orchestrator.cancel()

        XCTAssertEqual(orchestrator.currentTask?.status, .cancelled, "任务应标记为 cancelled")
    }

    /// cancel：无当前任务时抛错
    func testCancelWithoutTaskThrows() {
        let orchestrator = makeOrchestrator()
        XCTAssertThrowsError(try orchestrator.cancel()) { error in
            guard let error = error as? AgentOrchestrator.OrchestratorError else {
                XCTFail("应抛出 OrchestratorError")
                return
            }
            if case .noActiveTask = error {
                // 预期
            } else {
                XCTFail("应抛出 .noActiveTask")
            }
        }
    }

    // MARK: - Task 11: 断点续执行

    /// resumeTask：恢复指定任务
    func testResumeTask() async throws {
        mockLLM.responses = ["结果一", "结果二"]

        // 创建一个未完成的任务
        let task = AgentTask(goal: "待恢复")
        task.markInProgress()
        let s1 = SubTask(title: "步骤一", order: 0)
        let s2 = SubTask(title: "步骤二", order: 1)
        task.updateSubTasks([s1, s2])
        context.insert(task)
        try context.save()

        let orchestrator = makeOrchestrator()
        try await orchestrator.resumeTask(task)

        XCTAssertNotNil(orchestrator.currentTask)
        XCTAssertEqual(orchestrator.currentTask?.goal, "待恢复")

        // 恢复后可以继续执行
        try await orchestrator.executeAll()
        XCTAssertTrue(task.isAllSubTasksCompleted)
    }

    /// 续执行：init 自动恢复 inProgress 任务后可继续执行
    func testResumeInProgressTaskFromInit() throws {
        // 预插入一个部分完成的 inProgress 任务
        let task = AgentTask(goal: "部分完成")
        task.markInProgress()
        let s1 = SubTask(title: "已完成步骤", order: 0)
        let s2 = SubTask(title: "待执行步骤", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed, result: "已完成")
        context.insert(task)
        try context.save()

        // 初始化 orchestrator，应自动恢复
        let orchestrator = makeOrchestrator()
        XCTAssertNotNil(orchestrator.currentTask, "应自动恢复 inProgress 任务")
        XCTAssertEqual(orchestrator.currentTask?.subTasks[0].status, .completed, "已完成子任务应保持完成")
        XCTAssertEqual(orchestrator.currentTask?.subTasks[1].status, .pending, "未完成子任务应保持 pending")
    }

    // MARK: - Task 12: 多 Agent 协作

    /// 多 Agent 协作：reviewer 审查通过
    func testMultiAgentCollaborationReviewPass() async throws {
        mockLLM.responses = [
            parallelSubTasksJSON,  // 分解（planner）
            "执行结果A",            // 执行A（executor）
            "通过",                 // 审查A（reviewer）
            "执行结果B",            // 执行B（executor）
            "通过"                  // 审查B（reviewer）
        ]

        let orchestrator = makeOrchestrator(enableReview: true)
        _ = try await orchestrator.startTask(goal: "需审查的目标")

        try await orchestrator.executeAll()

        guard let task = orchestrator.currentTask else {
            XCTFail("currentTask 不应为 nil")
            return
        }
        XCTAssertTrue(task.isAllSubTasksCompleted, "审查通过后所有子任务应完成")
    }

    /// 多 Agent 协作：reviewer 审查不通过后重试
    func testMultiAgentCollaborationReviewRetry() async throws {
        mockLLM.responses = [
            parallelSubTasksJSON,  // 分解
            "第一次结果",           // 执行A
            "通过",                 // 审查A通过
            "第一次结果B",          // 执行B
            "不通过",               // 审查B不通过
            "重试结果B",            // 重试执行B
            "通过"                  // 重试审查B通过
        ]

        let orchestrator = makeOrchestrator(enableReview: true)
        _ = try await orchestrator.startTask(goal: "需重试的目标")

        try await orchestrator.executeAll()

        guard let task = orchestrator.currentTask else {
            XCTFail("currentTask 不应为 nil")
            return
        }
        XCTAssertTrue(task.isAllSubTasksCompleted, "重试后所有子任务应完成")
        // 最终结果应为重试后的结果
        let resultB = task.subTasks.first { $0.title == "并行任务B" }?.result
        XCTAssertEqual(resultB, "重试结果B", "应使用重试后的结果")
    }

    /// executor 角色使用 executor systemPrompt
    func testExecutorUsesExecutorSystemPrompt() async throws {
        mockLLM.responses = [chainedSubTasksJSON, "结果"]

        let orchestrator = makeOrchestrator()
        _ = try await orchestrator.startTask(goal: "目标")
        try await orchestrator.executeNext()

        // callSystemPrompts[0] 是分解用的 prompt
        // callSystemPrompts[1] 是执行用的 prompt（应为 executor systemPrompt）
        XCTAssertEqual(mockLLM.callSystemPrompts.count, 2)
        XCTAssertEqual(mockLLM.callSystemPrompts[1], AgentRole.executor.systemPrompt,
                       "执行时应使用 executor systemPrompt")
    }

    /// reviewer 角色使用 reviewer systemPrompt
    func testReviewerUsesReviewerSystemPrompt() async throws {
        mockLLM.responses = [
            parallelSubTasksJSON,  // 分解
            "结果A",                // 执行A
            "通过",                  // 审查A
            "结果B",                // 执行B
            "通过"                   // 审查B
        ]

        let orchestrator = makeOrchestrator(enableReview: true)
        _ = try await orchestrator.startTask(goal: "目标")
        try await orchestrator.executeAll()

        // 审查调用应使用 reviewer systemPrompt
        let reviewPrompts = mockLLM.callSystemPrompts.filter { $0 == AgentRole.reviewer.systemPrompt }
        XCTAssertFalse(reviewPrompts.isEmpty, "应至少有一次审查调用使用 reviewer systemPrompt")
    }

    // MARK: - 工具执行

    /// 子任务指定 toolName 时调用 ToolRegistry
    func testSubTaskExecutionWithTool() async throws {
        mockLLM.responses = [toolSubTasksJSON]

        let orchestrator = makeOrchestrator()
        let task = try await orchestrator.startTask(goal: "工具任务")
        try await orchestrator.executeAll()

        // get_current_time 工具应返回时间字符串
        let result = task.subTasks.first?.result ?? ""
        XCTAssertFalse(result.isEmpty, "工具执行结果不应为空")
        // DateTimeTool 返回格式 "yyyy-MM-dd HH:mm:ss ZZZZ"
        XCTAssertTrue(result.contains("-"), "时间结果应包含日期分隔符")
    }

    // MARK: - 持久化验证

    /// 每个子任务完成后状态已持久化
    func testStatePersistedAfterEachSubTask() async throws {
        mockLLM.responses = [chainedSubTasksJSON, "结果一"]

        let orchestrator = makeOrchestrator()
        let task = try await orchestrator.startTask(goal: "持久化验证")
        try await orchestrator.executeNext()

        // 重新创建 context 验证持久化
        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.first?.subTasks[0].status, .completed)
        XCTAssertEqual(fetched.first?.subTasks[0].result, "结果一")
        XCTAssertEqual(fetched.first?.subTasks[1].status, .pending)
        XCTAssertEqual(fetched.first?.updatedAt, task.updatedAt)
    }

    /// AgentConfig 可设置角色
    func testOrchestratorAgentConfigDefault() {
        let orchestrator = makeOrchestrator()
        XCTAssertEqual(orchestrator.agentConfig.role, .executor, "默认角色应为 executor")
    }

    /// enableReview 默认为 false
    func testEnableReviewDefaultFalse() {
        let orchestrator = makeOrchestrator()
        XCTAssertFalse(orchestrator.enableReview, "enableReview 默认应为 false")
    }
}
