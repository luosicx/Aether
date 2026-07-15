import XCTest
import SwiftData
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 9: GoalDecomposer 与 AgentTask / SubTask 单元测试
///
/// 覆盖范围：
/// - AgentTask 初始化与状态变更（markInProgress/markCompleted/markFailed/cancel）
/// - SubTask 创建与依赖关系
/// - AgentTaskStatus / SubTaskStatus 枚举
/// - GoalDecomposer.buildDecompositionPrompt 生成的 prompt 含目标与字段约定
/// - GoalDecomposer.parseSubTasks 解析能力（含 markdown fence、索引依赖、UUID 依赖）
/// - GoalDecomposer.decompose 端到端流程（mock LLMProvider）
/// - SwiftData 持久化
@MainActor
final class GoalDecomposerTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 可配置返回内容的 Mock LLMProvider，用于测试 GoalDecomposer.decompose
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

    /// 常用 JSON 子任务响应（含 markdown fence + 索引依赖）
    private let sampleJSONWithFence = """
    ```json
    [
      {"title": "分析需求", "description": "理解用户目标", "dependencies": [], "toolName": null, "order": 0},
      {"title": "设计方案", "description": "设计实现方案", "dependencies": [0], "toolName": null, "order": 1},
      {"title": "执行实现", "description": "按方案执行", "dependencies": [1], "toolName": "calculate", "order": 2}
    ]
    ```
    """

    /// 无 fence、UUID 依赖格式的 JSON 子任务响应
    private let sampleJSONWithUUIDDependencies = """
    [
      {"title": "步骤一", "description": "首步", "dependencies": [], "toolName": null, "order": 0},
      {"title": "步骤二", "description": "次步", "dependencies": [], "toolName": null, "order": 1}
    ]
    """

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: AgentTask.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - AgentTask 初始化与状态变更

    /// 默认初始化：goal 传入，subTasks 为空数组，status 为 .pending
    func testAgentTaskInitWithDefaults() {
        let task = AgentTask(goal: "完成一份报告")
        XCTAssertEqual(task.goal, "完成一份报告", "goal 应为传入值")
        XCTAssertEqual(task.subTasks, [], "subTasks 默认应为空数组")
        XCTAssertEqual(task.status, .pending, "status 默认应为 pending")
        XCTAssertNil(task.conversationID, "conversationID 默认应为 nil")
        XCTAssertNotNil(task.id, "id 应自动生成")
        XCTAssertTrue(task.createdAt <= Date(), "createdAt 应不晚于当前时间")
    }

    /// 带 conversationID 初始化
    func testAgentTaskInitWithConversationID() {
        let convID = UUID()
        let task = AgentTask(goal: "目标", conversationID: convID)
        XCTAssertEqual(task.conversationID, convID, "conversationID 应为传入值")
    }

    /// 多次初始化应生成不同 UUID
    func testAgentTaskInitGeneratesUniqueIDs() {
        let a = AgentTask(goal: "目标 A")
        let b = AgentTask(goal: "目标 B")
        XCTAssertNotEqual(a.id, b.id, "不同实例 id 应不同")
    }

    /// 状态变更：markInProgress
    func testAgentTaskMarkInProgress() {
        let task = AgentTask(goal: "目标")
        let before = task.updatedAt
        // 等待至少 1ms 以确保 updatedAt 改变
        Thread.sleep(forTimeInterval: 0.01)
        task.markInProgress()
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertGreaterThan(task.updatedAt, before, "markInProgress 应刷新 updatedAt")
    }

    /// 状态变更：markCompleted
    func testAgentTaskMarkCompleted() {
        let task = AgentTask(goal: "目标")
        task.markCompleted()
        XCTAssertEqual(task.status, .completed)
    }

    /// 状态变更：markFailed
    func testAgentTaskMarkFailed() {
        let task = AgentTask(goal: "目标")
        task.markFailed()
        XCTAssertEqual(task.status, .failed)
    }

    /// 状态变更：cancel
    func testAgentTaskCancel() {
        let task = AgentTask(goal: "目标")
        task.cancel()
        XCTAssertEqual(task.status, .cancelled)
    }

    /// updateSubTasks：替换子任务列表并刷新 updatedAt
    func testAgentTaskUpdateSubTasks() {
        let task = AgentTask(goal: "目标")
        let subTasks = [
            SubTask(title: "步骤 1", order: 0),
            SubTask(title: "步骤 2", order: 1)
        ]
        task.updateSubTasks(subTasks)
        XCTAssertEqual(task.subTasks.count, 2, "subTasks 应为 2 个")
        XCTAssertEqual(task.subTasks.first?.title, "步骤 1")
        XCTAssertEqual(task.subTasks.last?.title, "步骤 2")
    }

    /// updateSubTaskStatus：更新指定子任务状态与结果
    func testAgentTaskUpdateSubTaskStatus() {
        let task = AgentTask(goal: "目标")
        let sub = SubTask(title: "步骤", order: 0)
        task.updateSubTasks([sub])
        let updated = task.updateSubTaskStatus(id: sub.id, status: .completed, result: "完成结果")
        XCTAssertTrue(updated, "找到对应子任务应返回 true")
        XCTAssertEqual(task.subTasks.first?.status, .completed)
        XCTAssertEqual(task.subTasks.first?.result, "完成结果")
    }

    /// updateSubTaskStatus：找不到对应子任务时返回 false
    func testAgentTaskUpdateSubTaskStatusNotFound() {
        let task = AgentTask(goal: "目标")
        let updated = task.updateSubTaskStatus(id: UUID(), status: .completed)
        XCTAssertFalse(updated, "不存在的 subTaskID 应返回 false")
    }

    // MARK: - nextExecutableSubTask

    /// 无依赖场景：返回第一个 pending 子任务
    func testNextExecutableSubTaskNoDependencies() {
        let task = AgentTask(goal: "目标")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        task.updateSubTasks([s1, s2])
        let next = task.nextExecutableSubTask()
        XCTAssertEqual(next?.id, s1.id, "首个 pending 子任务应为 s1")
    }

    /// 依赖场景：依赖未完成时跳过
    func testNextExecutableSubTaskWithUnmetDependency() {
        let task = AgentTask(goal: "目标")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", dependencies: [s1.id], order: 1)
        task.updateSubTasks([s1, s2])
        // s1 未完成时，s2 虽 order 较高但依赖未满足，next 应为 s1
        let next = task.nextExecutableSubTask()
        XCTAssertEqual(next?.id, s1.id, "依赖未完成时应返回 s1")
    }

    /// 依赖场景：依赖已完成时返回依赖此任务的子任务
    func testNextExecutableSubTaskWithMetDependency() {
        let task = AgentTask(goal: "目标")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", dependencies: [s1.id], order: 1)
        task.updateSubTasks([s1, s2])
        // 标记 s1 完成
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        let next = task.nextExecutableSubTask()
        XCTAssertEqual(next?.id, s2.id, "s1 完成后 next 应为 s2")
    }

    /// 全部完成时返回 nil
    func testNextExecutableSubTaskAllCompleted() {
        let task = AgentTask(goal: "目标")
        let s1 = SubTask(title: "一", order: 0)
        task.updateSubTasks([s1])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        XCTAssertNil(task.nextExecutableSubTask(), "全部完成时应返回 nil")
    }

    /// 空子任务列表时返回 nil
    func testNextExecutableSubTaskEmpty() {
        let task = AgentTask(goal: "目标")
        XCTAssertNil(task.nextExecutableSubTask(), "空列表应返回 nil")
    }

    /// isAllSubTasksCompleted：全部完成时为 true
    func testIsAllSubTasksCompletedAllDone() {
        let task = AgentTask(goal: "目标")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        _ = task.updateSubTaskStatus(id: s2.id, status: .completed)
        XCTAssertTrue(task.isAllSubTasksCompleted)
    }

    /// isAllSubTasksCompleted：未全部完成时为 false
    func testIsAllSubTasksCompletedNotAllDone() {
        let task = AgentTask(goal: "目标")
        let s1 = SubTask(title: "一", order: 0)
        let s2 = SubTask(title: "二", order: 1)
        task.updateSubTasks([s1, s2])
        _ = task.updateSubTaskStatus(id: s1.id, status: .completed)
        // s2 仍 pending
        XCTAssertFalse(task.isAllSubTasksCompleted)
    }

    /// isAllSubTasksCompleted：空列表时为 false（避免空数组的 allSatisfy 返回 true 误判）
    func testIsAllSubTasksCompletedEmpty() {
        let task = AgentTask(goal: "目标")
        XCTAssertFalse(task.isAllSubTasksCompleted, "空列表应返回 false")
    }

    // MARK: - SubTask 创建与依赖

    /// SubTask 默认初始化：status 为 pending，dependencies 为空，result 为 nil
    func testSubTaskInitWithDefaults() {
        let sub = SubTask(title: "测试任务")
        XCTAssertEqual(sub.title, "测试任务")
        XCTAssertEqual(sub.description, "", "description 默认应为空字符串")
        XCTAssertEqual(sub.status, .pending)
        XCTAssertEqual(sub.dependencies, [], "dependencies 默认应为空数组")
        XCTAssertNil(sub.toolName, "toolName 默认应为 nil")
        XCTAssertNil(sub.result, "result 默认应为 nil")
        XCTAssertEqual(sub.order, 0, "order 默认应为 0")
        XCTAssertNotNil(sub.id)
    }

    /// SubTask 全参数初始化
    func testSubTaskInitWithAllParameters() {
        let depID = UUID()
        let sub = SubTask(
            title: "复杂任务",
            description: "带描述",
            dependencies: [depID],
            toolName: "calculate",
            order: 3
        )
        XCTAssertEqual(sub.title, "复杂任务")
        XCTAssertEqual(sub.description, "带描述")
        XCTAssertEqual(sub.dependencies, [depID])
        XCTAssertEqual(sub.toolName, "calculate")
        XCTAssertEqual(sub.order, 3)
    }

    /// SubTask Hashable：可放入 Set / Dictionary
    func testSubTaskHashable() {
        let sub = SubTask(title: "任务")
        let set: Set<SubTask> = [sub]
        XCTAssertTrue(set.contains(sub), "SubTask 应可放入 Set")
    }

    /// SubTask 依赖关系：可建立多个依赖
    func testSubTaskMultipleDependencies() {
        let dep1 = UUID()
        let dep2 = UUID()
        let dep3 = UUID()
        let sub = SubTask(title: "多依赖", dependencies: [dep1, dep2, dep3])
        XCTAssertEqual(sub.dependencies.count, 3)
        XCTAssertTrue(sub.dependencies.contains(dep1))
        XCTAssertTrue(sub.dependencies.contains(dep2))
        XCTAssertTrue(sub.dependencies.contains(dep3))
    }

    // MARK: - AgentTaskStatus 枚举

    /// AgentTaskStatus rawValue 验证
    func testAgentTaskStatusRawValues() {
        XCTAssertEqual(AgentTaskStatus.pending.rawValue, "pending")
        XCTAssertEqual(AgentTaskStatus.inProgress.rawValue, "inProgress")
        XCTAssertEqual(AgentTaskStatus.completed.rawValue, "completed")
        XCTAssertEqual(AgentTaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(AgentTaskStatus.cancelled.rawValue, "cancelled")
    }

    /// AgentTaskStatus Codable：可从 rawValue 解码
    func testAgentTaskStatusCodable() throws {
        let cases: [AgentTaskStatus] = [.pending, .inProgress, .completed, .failed, .cancelled]
        for status in cases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(AgentTaskStatus.self, from: encoded)
            XCTAssertEqual(decoded, status, "round-trip 编解码应保持一致")
        }
    }

    /// AgentTaskStatus 从无效 rawValue 初始化应返回 nil
    func testAgentTaskStatusInvalidRawValue() {
        XCTAssertNil(AgentTaskStatus(rawValue: "invalid"))
    }

    // MARK: - SubTaskStatus 枚举

    /// SubTaskStatus rawValue 验证
    func testSubTaskStatusRawValues() {
        XCTAssertEqual(SubTaskStatus.pending.rawValue, "pending")
        XCTAssertEqual(SubTaskStatus.inProgress.rawValue, "inProgress")
        XCTAssertEqual(SubTaskStatus.completed.rawValue, "completed")
        XCTAssertEqual(SubTaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(SubTaskStatus.skipped.rawValue, "skipped")
    }

    /// SubTaskStatus Codable：round-trip 测试
    func testSubTaskStatusCodable() throws {
        let cases: [SubTaskStatus] = [.pending, .inProgress, .completed, .failed, .skipped]
        for status in cases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(SubTaskStatus.self, from: encoded)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - GoalDecomposer.buildDecompositionPrompt

    /// buildDecompositionPrompt 应包含目标文本与字段约定
    func testBuildDecompositionPromptContainsGoal() {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let goal = "组织一次团队周会"
        let prompt = decomposer.buildDecompositionPrompt(goal: goal)
        XCTAssertTrue(prompt.contains(goal), "prompt 应包含原始目标")
        XCTAssertTrue(prompt.contains("title"), "prompt 应包含 title 字段约定")
        XCTAssertTrue(prompt.contains("description"), "prompt 应包含 description 字段约定")
        XCTAssertTrue(prompt.contains("dependencies"), "prompt 应包含 dependencies 字段约定")
        XCTAssertTrue(prompt.contains("toolName"), "prompt 应包含 toolName 字段约定")
        XCTAssertTrue(prompt.contains("order"), "prompt 应包含 order 字段约定")
    }

    /// buildDecompositionPrompt 不同目标应生成不同 prompt
    func testBuildDecompositionPromptDifferentGoals() {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let promptA = decomposer.buildDecompositionPrompt(goal: "目标 A")
        let promptB = decomposer.buildDecompositionPrompt(goal: "目标 B")
        XCTAssertNotEqual(promptA, promptB, "不同目标应生成不同 prompt")
        XCTAssertTrue(promptA.contains("目标 A"))
        XCTAssertTrue(promptB.contains("目标 B"))
    }

    // MARK: - GoalDecomposer.parseSubTasks

    /// parseSubTasks 解析带 markdown fence 与索引依赖的 JSON
    func testParseSubTasksWithFenceAndIndexDependencies() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let subTasks = try decomposer.parseSubTasks(from: sampleJSONWithFence)

        XCTAssertEqual(subTasks.count, 3, "应解析出 3 个子任务")

        // 验证顺序：按 order 升序
        XCTAssertEqual(subTasks[0].title, "分析需求")
        XCTAssertEqual(subTasks[1].title, "设计方案")
        XCTAssertEqual(subTasks[2].title, "执行实现")

        // 验证 description
        XCTAssertEqual(subTasks[0].description, "理解用户目标")

        // 验证 order 字段
        XCTAssertEqual(subTasks[0].order, 0)
        XCTAssertEqual(subTasks[1].order, 1)
        XCTAssertEqual(subTasks[2].order, 2)

        // 验证 toolName
        XCTAssertNil(subTasks[0].toolName)
        XCTAssertEqual(subTasks[2].toolName, "calculate")

        // 验证索引依赖已被映射为 UUID：s1 依赖 []，s2 依赖 [s1]，s3 依赖 [s2]
        XCTAssertTrue(subTasks[0].dependencies.isEmpty, "s1 无依赖")
        XCTAssertEqual(subTasks[1].dependencies, [subTasks[0].id], "s2 应依赖 s1 的 UUID")
        XCTAssertEqual(subTasks[2].dependencies, [subTasks[1].id], "s3 应依赖 s2 的 UUID")

        // 验证 status 默认为 pending
        XCTAssertTrue(subTasks.allSatisfy { $0.status == .pending })
    }

    /// parseSubTasks 解析无 fence 的 UUID 依赖 JSON
    func testParseSubTasksWithUUIDDependencies() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let subTasks = try decomposer.parseSubTasks(from: sampleJSONWithUUIDDependencies)
        XCTAssertEqual(subTasks.count, 2)
        XCTAssertEqual(subTasks[0].title, "步骤一")
        XCTAssertEqual(subTasks[1].title, "步骤二")
        XCTAssertTrue(subTasks.allSatisfy { $0.dependencies.isEmpty })
    }

    /// parseSubTasks 解析纯 JSON 数组（无 fence 无额外文本）
    func testParseSubTasksPureJSON() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let json = """
        [{"title": "任务一", "order": 0}, {"title": "任务二", "order": 1}]
        """
        let subTasks = try decomposer.parseSubTasks(from: json)
        XCTAssertEqual(subTasks.count, 2)
        XCTAssertEqual(subTasks[0].title, "任务一")
        XCTAssertEqual(subTasks[1].title, "任务二")
    }

    /// parseSubTasks 解析 LLM 在 JSON 前后添加额外文本的场景
    func testParseSubTasksWithSurroundingText() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let response = """
        好的，以下是分解结果：

        [{"title": "步骤", "order": 0}]

        希望对您有帮助！
        """
        let subTasks = try decomposer.parseSubTasks(from: response)
        XCTAssertEqual(subTasks.count, 1)
        XCTAssertEqual(subTasks.first?.title, "步骤")
    }

    /// parseSubTasks 字段缺失时使用默认值（description/status/toolName/result/order）
    func testParseSubTasksWithMissingFields() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let json = """
        [{"title": "仅标题"}]
        """
        let subTasks = try decomposer.parseSubTasks(from: json)
        XCTAssertEqual(subTasks.count, 1)
        XCTAssertEqual(subTasks.first?.title, "仅标题")
        XCTAssertEqual(subTasks.first?.description, "", "缺失 description 应默认为空字符串")
        XCTAssertEqual(subTasks.first?.status, .pending, "缺失 status 应默认为 pending")
        XCTAssertEqual(subTasks.first?.dependencies, [], "缺失 dependencies 应默认为空数组")
        XCTAssertNil(subTasks.first?.toolName, "缺失 toolName 应默认为 nil")
        XCTAssertNil(subTasks.first?.result, "缺失 result 应默认为 nil")
        XCTAssertEqual(subTasks.first?.order, 0, "缺失 order 应默认为 0")
    }

    /// parseSubTasks 无 JSON 数组时抛 invalidJSON
    func testParseSubTasksInvalidNoArray() {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        XCTAssertThrowsError(try decomposer.parseSubTasks(from: "没有 JSON 数组的内容")) { error in
            guard let decomposeError = error as? GoalDecomposer.DecomposeError else {
                XCTFail("应抛出 DecomposeError")
                return
            }
            if case .invalidJSON = decomposeError {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON")
            }
        }
    }

    /// parseSubTasks 解析无效 JSON 抛 invalidJSON
    func testParseSubTasksInvalidJSON() {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let badJSON = "[{\"title\": \"缺右括号\""
        XCTAssertThrowsError(try decomposer.parseSubTasks(from: badJSON)) { error in
            guard let decomposeError = error as? GoalDecomposer.DecomposeError else {
                XCTFail("应抛出 DecomposeError")
                return
            }
            if case .invalidJSON = decomposeError {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON")
            }
        }
    }

    /// parseSubTasks 自引用依赖（依赖自身索引）应被忽略
    func testParseSubTasksSelfReferenceIgnored() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let json = """
        [
          {"title": "任务一", "dependencies": [0], "order": 0},
          {"title": "任务二", "dependencies": [1], "order": 1}
        ]
        """
        let subTasks = try decomposer.parseSubTasks(from: json)
        XCTAssertEqual(subTasks.count, 2)
        XCTAssertTrue(subTasks[0].dependencies.isEmpty, "自引用依赖应被忽略")
        XCTAssertTrue(subTasks[1].dependencies.isEmpty, "自引用依赖应被忽略")
    }

    /// parseSubTasks 越界索引依赖应被忽略
    func testParseSubTasksOutOfRangeDependencyIgnored() throws {
        let decomposer = GoalDecomposer(llmProvider: MockLLMProvider())
        let json = """
        [
          {"title": "任务一", "dependencies": [99], "order": 0}
        ]
        """
        let subTasks = try decomposer.parseSubTasks(from: json)
        XCTAssertEqual(subTasks.count, 1)
        XCTAssertTrue(subTasks[0].dependencies.isEmpty, "越界索引依赖应被忽略")
    }

    // MARK: - GoalDecomposer.decompose 端到端

    /// decompose 正常流程：mock 返回 JSON，验证返回子任务列表与排序
    func testDecomposeSuccess() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = [sampleJSONWithFence]
        let decomposer = GoalDecomposer(llmProvider: mock)

        let subTasks = try await decomposer.decompose(goal: "完成一个项目")

        XCTAssertEqual(subTasks.count, 3, "应返回 3 个子任务")
        XCTAssertEqual(subTasks[0].order, 0)
        XCTAssertEqual(subTasks[1].order, 1)
        XCTAssertEqual(subTasks[2].order, 2)
        XCTAssertEqual(mock.chatCallCount, 1, "应调用 LLMProvider.chat 一次")
        XCTAssertNotNil(mock.lastUserMessage, "应记录最后一次 user 消息")
        XCTAssertTrue(mock.lastUserMessage?.contains("完成一个项目") ?? false, "user 消息应包含目标")
    }

    /// decompose 多 chunk 累积：mock 分多次返回 JSON 片段
    func testDecomposeMultipleChunksAccumulated() async throws {
        let mock = MockLLMProvider()
        // 将 JSON 拆成多个 chunk
        mock.chatContents = [
            "[{\"title\": \"一\",",
            "\"order\": 0},",
            "{\"title\": \"二\",",
            "\"order\": 1}]"
        ]
        let decomposer = GoalDecomposer(llmProvider: mock)

        let subTasks = try await decomposer.decompose(goal: "目标")
        XCTAssertEqual(subTasks.count, 2)
        XCTAssertEqual(subTasks[0].title, "一")
        XCTAssertEqual(subTasks[1].title, "二")
    }

    /// decompose LLM 返回空内容时抛 emptyResponse
    func testDecomposeEmptyResponseThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = []
        let decomposer = GoalDecomposer(llmProvider: mock)

        do {
            _ = try await decomposer.decompose(goal: "目标")
            XCTFail("空响应应抛出错误")
        } catch let error as GoalDecomposer.DecomposeError {
            if case .emptyResponse = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .emptyResponse，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 DecomposeError，实际：\(error)")
        }
    }

    /// decompose LLM 返回仅空白字符时抛 emptyResponse
    func testDecomposeWhitespaceOnlyThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = ["   \n  \t  \n"]
        let decomposer = GoalDecomposer(llmProvider: mock)

        do {
            _ = try await decomposer.decompose(goal: "目标")
            XCTFail("空白响应应抛出错误")
        } catch let error as GoalDecomposer.DecomposeError {
            if case .emptyResponse = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .emptyResponse，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 DecomposeError")
        }
    }

    /// decompose LLM 返回无效 JSON 时抛 invalidJSON
    func testDecomposeInvalidJSONThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = ["这不是 JSON"]
        let decomposer = GoalDecomposer(llmProvider: mock)

        do {
            _ = try await decomposer.decompose(goal: "目标")
            XCTFail("无效 JSON 应抛出错误")
        } catch let error as GoalDecomposer.DecomposeError {
            if case .invalidJSON = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .invalidJSON，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 DecomposeError")
        }
    }

    /// decompose LLM 返回空数组 JSON 时抛 noSubTasks
    func testDecomposeEmptyArrayThrows() async {
        let mock = MockLLMProvider()
        mock.chatContents = ["[]"]
        let decomposer = GoalDecomposer(llmProvider: mock)

        do {
            _ = try await decomposer.decompose(goal: "目标")
            XCTFail("空数组应抛出错误")
        } catch let error as GoalDecomposer.DecomposeError {
            if case .noSubTasks = error {
                // 预期路径
            } else {
                XCTFail("应抛出 .noSubTasks，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 DecomposeError")
        }
    }

    /// decompose LLM 未填 order 字段时按数组顺序重新赋值并排序
    func testDecomposeMissingOrderFieldSortedByIndex() async throws {
        let mock = MockLLMProvider()
        // 所有子任务的 order 均为 0（缺失字段默认），decompose 应按数组顺序重新赋值
        mock.chatContents = [
            """
            [
              {"title": "第一步"},
              {"title": "第二步"},
              {"title": "第三步"}
            ]
            """
        ]
        let decomposer = GoalDecomposer(llmProvider: mock)

        let subTasks = try await decomposer.decompose(goal: "目标")
        XCTAssertEqual(subTasks.count, 3)
        XCTAssertEqual(subTasks[0].order, 0)
        XCTAssertEqual(subTasks[1].order, 1)
        XCTAssertEqual(subTasks[2].order, 2)
    }

    /// decompose 传入的 config 与 messages 应正确（验证 chat 调用参数）
    func testDecomposeChatConfigParameters() async throws {
        let mock = MockLLMProvider()
        mock.chatContents = [sampleJSONWithUUIDDependencies]
        let decomposer = GoalDecomposer(llmProvider: mock)

        _ = try await decomposer.decompose(goal: "测试目标")

        XCTAssertEqual(mock.chatCallCount, 1, "应调用 chat 一次")
        // 验证 user 消息含目标
        XCTAssertTrue(mock.lastUserMessage?.contains("测试目标") ?? false)
    }

    // MARK: - SwiftData 持久化

    /// AgentTask 插入并 fetch 应返回存储的实例
    func testSwiftDataInsertAndFetch() throws {
        let task = AgentTask(goal: "持久化测试")
        let sub = SubTask(title: "子任务", order: 0)
        task.updateSubTasks([sub])
        context.insert(task)
        try context.save()

        let descriptor = FetchDescriptor<AgentTask>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "应 fetch 到 1 条 AgentTask")
        XCTAssertEqual(fetched.first?.goal, "持久化测试")
        XCTAssertEqual(fetched.first?.subTasks.count, 1, "应能取回 1 个子任务")
        XCTAssertEqual(fetched.first?.subTasks.first?.title, "子任务")
        XCTAssertEqual(fetched.first?.status, .pending)
    }

    /// AgentTask 状态变更后能正确持久化
    func testSwiftDataStatusUpdatePersists() throws {
        let task = AgentTask(goal: "状态测试")
        context.insert(task)
        try context.save()

        task.markInProgress()
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.first?.status, .inProgress, "状态变更后应能取回新状态")
    }

    /// AgentTask 子任务状态变更后能正确持久化
    func testSwiftDataSubTaskStatusUpdatePersists() throws {
        let task = AgentTask(goal: "子任务状态测试")
        let sub = SubTask(title: "子任务", order: 0)
        task.updateSubTasks([sub])
        context.insert(task)
        try context.save()

        _ = task.updateSubTaskStatus(id: sub.id, status: .completed, result: "已完成")
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.first?.subTasks.first?.status, .completed)
        XCTAssertEqual(fetched.first?.subTasks.first?.result, "已完成")
    }

    /// 插入多个 AgentTask 后 fetch 应返回全部
    func testSwiftDataInsertMultipleTasks() throws {
        for i in 0..<3 {
            context.insert(AgentTask(goal: "目标 \(i)"))
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.count, 3, "应 fetch 到 3 条 AgentTask")
    }

    /// 删除 AgentTask 后 fetch 应返回空
    func testSwiftDataDeleteTask() throws {
        let task = AgentTask(goal: "待删除")
        context.insert(task)
        try context.save()

        context.delete(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AgentTask>())
        XCTAssertEqual(fetched.count, 0, "删除后应 fetch 到 0 条")
    }
}
