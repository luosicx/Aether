import XCTest
import AetherFoundation
import AetherServices
@testable import Aether

/// Task 20 阶段 1: HierarchicalDecomposer 单元测试
///
/// 覆盖：
/// - 包装 GoalDecomposer 调用 LLM
/// - 递归分解触发（复杂度启发式）
/// - 深度约束（≤ 3）
/// - 宽度约束（≤ 8）
/// - 总数约束（≤ 50）
/// - DAG 依赖生成（同层串行 / parallel 无依赖）
/// - 拓扑校验与循环依赖检测
/// - applyHeuristics 同步校验
@MainActor
final class HierarchicalDecomposerTests: XCTestCase {

    // MARK: - Mock LLMProvider

    /// 按调用顺序依次返回预设响应的 Mock LLMProvider
    final class MockLLMProvider: LLMProvider {
        /// 响应队列：第 N 次 chat 调用返回 responses[N-1]
        var responses: [String] = []
        /// 调用计数
        private(set) var chatCallCount = 0

        func chat(messages: [APIMessage], config: ChatConfig, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                self.chatCallCount += 1
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

    /// 简单子任务 JSON：3 个串行子任务（无连接词，描述短）
    private let simpleSubTasksJSON = """
    [
      {"title": "步骤一", "description": "首步", "dependencies": [], "toolName": null, "order": 0},
      {"title": "步骤二", "description": "次步", "dependencies": [0], "toolName": null, "order": 1},
      {"title": "步骤三", "description": "末步", "dependencies": [1], "toolName": null, "order": 2}
    ]
    """

    /// 复杂子任务 JSON：1 个子任务描述包含"并且"（应触发递归分解）
    private let complexSubTasksJSON = """
    [
      {"title": "复杂任务", "description": "做A并且做B", "dependencies": [], "toolName": null, "order": 0}
    ]
    """

    /// 第二层分解：返回 2 个简单子任务
    private let secondLevelSubTasksJSON = """
    [
      {"title": "子任务A", "description": "做A", "dependencies": [], "toolName": null, "order": 0},
      {"title": "子任务B", "description": "做B", "dependencies": [0], "toolName": null, "order": 1}
    ]
    """

    private var mockLLM: MockLLMProvider!
    private var goalDecomposer: GoalDecomposer!
    private var decomposer: HierarchicalDecomposer!

    override func setUpWithError() throws {
        mockLLM = MockLLMProvider()
        goalDecomposer = GoalDecomposer(llmProvider: mockLLM)
        decomposer = HierarchicalDecomposer(goalDecomposer: goalDecomposer)
    }

    override func tearDownWithError() throws {
        mockLLM = nil
        goalDecomposer = nil
        decomposer = nil
    }

    // MARK: - 基本分解

    /// 简单目标分解：3 个串行子任务，无递归
    func testDecomposeSimpleGoal() async throws {
        mockLLM.responses = [simpleSubTasksJSON]

        let subTasks = try await decomposer.decompose(goal: "完成一个简单项目")

        XCTAssertEqual(subTasks.count, 3, "应分解出 3 个子任务")
        XCTAssertEqual(mockLLM.chatCallCount, 1, "应调用 LLM 一次")
        // 同层兄弟依赖：第一个无依赖，后续串行依赖前一个
        XCTAssertTrue(subTasks[0].dependencies.isEmpty)
        XCTAssertEqual(subTasks[1].dependencies, [subTasks[0].id])
        XCTAssertEqual(subTasks[2].dependencies, [subTasks[1].id])
        // 深度均为 1
        XCTAssertTrue(subTasks.allSatisfy { $0.depth == 1 })
    }

    /// 复杂目标分解：含连接词，触发递归
    func testDecomposeComplexGoalTriggersRecursion() async throws {
        mockLLM.responses = [complexSubTasksJSON, secondLevelSubTasksJSON]

        let subTasks = try await decomposer.decompose(goal: "完成复杂任务")

        // 第一次分解得到 1 个复杂子任务，递归分解后应得到 2 个子任务
        XCTAssertEqual(subTasks.count, 2, "复杂任务应被递归分解为 2 个子任务")
        XCTAssertEqual(mockLLM.chatCallCount, 2, "应调用 LLM 两次（外层+内层）")
        XCTAssertEqual(subTasks[0].title, "子任务A")
        XCTAssertEqual(subTasks[1].title, "子任务B")
        // 子任务深度应为 2
        XCTAssertTrue(subTasks.allSatisfy { $0.depth == 2 })
    }

    /// LLM 分解失败时降级为单叶子节点
    func testDecomposeLLMFailureDegradesToLeaf() async throws {
        // 返回非法 JSON 触发 GoalDecomposer 解析失败
        mockLLM.responses = ["not a valid json"]

        let subTasks = try await decomposer.decompose(goal: "失败测试")

        XCTAssertEqual(subTasks.count, 1, "LLM 失败时应降级为单叶子节点")
        XCTAssertEqual(subTasks[0].depth, 1)
        XCTAssertTrue(subTasks[0].dependencies.isEmpty)
    }

    // MARK: - DAG 校验

    /// 分解结果应通过 DAG 校验（无循环依赖）
    func testDecomposeProducesValidDAG() async throws {
        mockLLM.responses = [simpleSubTasksJSON]

        let subTasks = try await decomposer.decompose(goal: "DAG 校验测试")

        let (isValid, reason) = HeuristicRules.validateDAG(subTasks)
        XCTAssertTrue(isValid, "分解结果应通过 DAG 校验：\(reason ?? "")")
        XCTAssertFalse(HeuristicRules.hasCycle(subTasks), "分解结果不应有循环依赖")
    }

    // MARK: - applyHeuristics 同步校验

    /// applyHeuristics 对合法子任务列表应原样返回
    func testApplyHeuristicsValidList() throws {
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", order: 1, dependencies: [s1.id])
        let result = try decomposer.applyHeuristics(to: [s1, s2])
        XCTAssertEqual(result.count, 2)
    }

    /// applyHeuristics 对空列表应抛错
    func testApplyHeuristicsEmptyThrows() {
        XCTAssertThrowsError(try decomposer.applyHeuristics(to: [])) { error in
            guard let error = error as? HierarchicalDecomposer.DecomposeError else {
                XCTFail("应抛出 DecomposeError")
                return
            }
            if case .emptyDecomposition = error {
                // 预期
            } else {
                XCTFail("应抛出 .emptyDecomposition")
            }
        }
    }

    /// applyHeuristics 对有循环依赖的列表应抛错
    func testApplyHeuristicsWithCycleThrows() {
        let s1 = SubTask(title: "T1", order: 0)
        var s1WithDep = s1
        s1WithDep.dependencies = [s1.id] // 自环
        XCTAssertThrowsError(try decomposer.applyHeuristics(to: [s1WithDep])) { error in
            guard let error = error as? HierarchicalDecomposer.DecomposeError else {
                XCTFail("应抛出 DecomposeError")
                return
            }
            if case .invalidDAG = error {
                // 预期
            } else {
                XCTFail("应抛出 .invalidDAG")
            }
        }
    }

    /// applyHeuristics 总数超限时截断
    func testApplyHeuristicsTruncatesToMaxTotal() throws {
        let rules = HeuristicRules(maxDepth: 3, maxWidth: 8, maxTotalCount: 5)
        let decomposerWithSmallLimit = HierarchicalDecomposer(goalDecomposer: goalDecomposer, rules: rules)
        // 创建 10 个无依赖子任务
        let subTasks = (0..<10).map { i in SubTask(title: "T\(i)", order: i) }
        let result = try decomposerWithSmallLimit.applyHeuristics(to: subTasks)
        XCTAssertLessThanOrEqual(result.count, 5, "应截断到 maxTotalCount=5")
    }

    // MARK: - 验收标准对齐

    /// 验收 1: 生成的子任务 DAG 深度 ≤ 3、宽度 ≤ 8、总数 ≤ 50
    func testAcceptanceCriteriaDepthWidthTotalBounds() async throws {
        mockLLM.responses = [simpleSubTasksJSON]

        let subTasks = try await decomposer.decompose(goal: "验收测试")

        // 总数 ≤ 50
        XCTAssertLessThanOrEqual(subTasks.count, 50)
        // 深度 ≤ 3
        let maxDepth = subTasks.map(\.depth).max() ?? 0
        XCTAssertLessThanOrEqual(maxDepth, 3)
        // 宽度 ≤ 8（按 depth 分组）
        let byDepth = Dictionary(grouping: subTasks, by: \.depth)
        for (_, group) in byDepth {
            XCTAssertLessThanOrEqual(group.count, 8, "每层子任务数应 ≤ 8")
        }
        // 无循环依赖
        XCTAssertFalse(HeuristicRules.hasCycle(subTasks), "应无循环依赖")
    }

    /// 验收: 循环依赖检测 — LLM 分解生成循环依赖时校验失败
    func testAcceptanceCycleDependencyDetection() {
        // 构造带循环依赖的子任务列表
        let s1 = SubTask(title: "T1", order: 0)
        let s2 = SubTask(title: "T2", order: 1, dependencies: [s1.id])
        var s1WithDep = s1
        s1WithDep.dependencies = [s2.id]
        // applyHeuristics 应抛 invalidDAG 错误
        XCTAssertThrowsError(try decomposer.applyHeuristics(to: [s1WithDep, s2])) { error in
            guard let error = error as? HierarchicalDecomposer.DecomposeError,
                  case .invalidDAG = error else {
                XCTFail("应抛出 .invalidDAG")
                return
            }
        }
    }
}
