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
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
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
        let s2 = SubTask(title: "T2", dependencies: [s1.id], order: 1)
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

    // MARK: - 深度耗尽

    /// maxDepth=1 时复杂目标不再递归分解，叶子节点 depth == 1。
    /// canDecompose(depth: 1) 返回 false，shouldDecompose 直接返回 false，
    /// 含"并且"的复杂子任务不再递归，作为叶子收集在 depth=1。
    func testDecomposeDepthExhaustion() async throws {
        let rules = HeuristicRules(maxDepth: 1, maxWidth: 8, maxTotalCount: 50)
        let shallowDecomposer = HierarchicalDecomposer(goalDecomposer: goalDecomposer, rules: rules)
        mockLLM.responses = [complexSubTasksJSON]

        let subTasks = try await shallowDecomposer.decompose(goal: "深度耗尽测试")

        XCTAssertEqual(mockLLM.chatCallCount, 1, "maxDepth=1 时复杂目标不应递归分解")
        XCTAssertEqual(subTasks.count, 1, "应只收集到一个叶子节点")
        XCTAssertEqual(subTasks[0].depth, 1, "叶子节点深度应为 1")
    }

    // MARK: - LLM 返回空数组与 emptyDecomposition

    /// LLM 返回空数组时的行为验证：
    /// - 场景 1: LLM 返回 "[]"，GoalDecomposer 抛 .noSubTasks，
    ///   HierarchicalDecomposer 捕获后降级为单叶子节点（不抛 .emptyDecomposition）。
    /// - 场景 2: maxTotalCount=0 时 collected 为空，decompose 抛 .emptyDecomposition。
    func testDecomposeLLMReturnsEmptyArrayThrows() async throws {
        // 场景 1: LLM 返回空数组 — 降级为单叶子节点
        mockLLM.responses = ["[]"]
        let subTasks = try await decomposer.decompose(goal: "空数组测试")
        XCTAssertEqual(subTasks.count, 1, "LLM 返回空数组时应降级为单叶子节点")
        XCTAssertEqual(subTasks[0].depth, 1)

        // 场景 2: maxTotalCount=0 时 collected 为空，触发 .emptyDecomposition
        let zeroMock = MockLLMProvider()
        zeroMock.responses = [simpleSubTasksJSON]
        let zeroDecomposer = HierarchicalDecomposer(
            goalDecomposer: GoalDecomposer(llmProvider: zeroMock),
            rules: HeuristicRules(maxDepth: 3, maxWidth: 8, maxTotalCount: 0)
        )
        do {
            _ = try await zeroDecomposer.decompose(goal: "零上限测试")
            XCTFail("应抛出 .emptyDecomposition")
        } catch let error as HierarchicalDecomposer.DecomposeError {
            guard case .emptyDecomposition = error else {
                XCTFail("应抛出 .emptyDecomposition，实际：\(error)")
                return
            }
        } catch {
            XCTFail("应抛出 DecomposeError.emptyDecomposition，实际：\(error)")
        }
    }

    // MARK: - 总数截断

    /// 总数超限时 decompose 截断到 maxTotalCount。
    /// 构造 maxTotalCount=3 的 rules，LLM 返回 5 个子任务，
    /// 由于 collected.count + siblings.count 超限，提前返回并截断到 3 个。
    func testDecomposeTruncatesToMaxTotalCount() async throws {
        let fiveSubTasksJSON = """
        [
          {"title": "T1", "description": "d1", "dependencies": [], "toolName": null, "order": 0},
          {"title": "T2", "description": "d2", "dependencies": [0], "toolName": null, "order": 1},
          {"title": "T3", "description": "d3", "dependencies": [1], "toolName": null, "order": 2},
          {"title": "T4", "description": "d4", "dependencies": [2], "toolName": null, "order": 3},
          {"title": "T5", "description": "d5", "dependencies": [3], "toolName": null, "order": 4}
        ]
        """
        let rules = HeuristicRules(maxDepth: 3, maxWidth: 8, maxTotalCount: 3)
        let smallLimitDecomposer = HierarchicalDecomposer(goalDecomposer: goalDecomposer, rules: rules)
        mockLLM.responses = [fiveSubTasksJSON]

        let subTasks = try await smallLimitDecomposer.decompose(goal: "总数截断测试")

        XCTAssertLessThanOrEqual(subTasks.count, 3, "应截断到 maxTotalCount=3")
    }

    // MARK: - 宽度截断

    /// applyHeuristics 按深度分组截断宽度，每组 ≤ maxWidth。
    /// 构造 10 个 depth=1 的无依赖子任务，maxWidth=3，
    /// 校验结果按 depth 分组后每组数量 ≤ 3。
    func testApplyHeuristicsTruncatesWidthByDepth() throws {
        let rules = HeuristicRules(maxDepth: 3, maxWidth: 3, maxTotalCount: 50)
        let smallWidthDecomposer = HierarchicalDecomposer(goalDecomposer: goalDecomposer, rules: rules)
        // 构造 10 个 depth=1 的无依赖子任务
        let subTasks = (0..<10).map { i in SubTask(title: "T\(i)", order: i) }

        let result = try smallWidthDecomposer.applyHeuristics(to: subTasks)

        let byDepth = Dictionary(grouping: result, by: \.depth)
        for (_, group) in byDepth {
            XCTAssertLessThanOrEqual(group.count, 3, "每组子任务数应 ≤ maxWidth=3")
        }
        XCTAssertLessThanOrEqual(result.count, 3, "总结果数应 ≤ maxWidth=3")
    }

    // MARK: - 跨层依赖继承

    /// 第二层第一个子任务的 dependencies 应包含父节点的依赖。
    /// 构造两层分解：第一层 sub1(简单) + sub2(含"并且"，触发递归)，
    /// sub2 经 generateSiblingDependencies 后依赖 sub1.id；
    /// 递归进入第二层时 parentDependencies=[sub1.id]，
    /// 第二层第一个子任务 child1 继承 parentDependencies。
    func testDecomposeInheritsParentDependencies() async throws {
        let layer1JSON = """
        [
          {"title": "简单任务", "description": "简单", "dependencies": [], "toolName": null, "order": 0},
          {"title": "复杂任务", "description": "做A并且做B", "dependencies": [0], "toolName": null, "order": 1}
        ]
        """
        let layer2JSON = """
        [
          {"title": "子A", "description": "做A", "dependencies": [], "toolName": null, "order": 0},
          {"title": "子B", "description": "做B", "dependencies": [0], "toolName": null, "order": 1}
        ]
        """
        mockLLM.responses = [layer1JSON, layer2JSON]

        let subTasks = try await decomposer.decompose(goal: "继承依赖测试")

        let depth1Tasks = subTasks.filter { $0.depth == 1 }
        let depth2Tasks = subTasks.filter { $0.depth == 2 }

        XCTAssertEqual(depth1Tasks.count, 1, "应有一个 depth=1 的子任务（简单任务；复杂任务被递归分解，不再保留）")
        XCTAssertEqual(depth2Tasks.count, 2, "应有两个 depth=2 的子任务")

        // 第二层第一个子任务的 dependencies 应包含父节点的依赖（即第一层第一个子任务的 ID）
        let parentID = depth1Tasks[0].id
        XCTAssertTrue(depth2Tasks[0].dependencies.contains(parentID),
                      "第二层第一个子任务的 dependencies 应包含父节点的依赖")
    }
}
