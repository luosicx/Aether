import Foundation
import AetherFoundation

/// Task 20 阶段 1: 层次化目标分解器。
///
/// 包装现有 `GoalDecomposer`，在 LLM 单次分解之上叠加：
/// 1. **启发式约束**：深度 ≤ 3、宽度 ≤ 8、总数 ≤ 50（由 `HeuristicRules` 配置）
/// 2. **递归分解**：复杂度高的子任务（描述长度 > 100 字或含"并且/然后"等连接词）递归分解为子层
/// 3. **DAG 依赖生成**：同层兄弟默认串行依赖，`parallel: true` 节点无相互依赖
/// 4. **拓扑校验**：Kahn 算法检测循环依赖，提交前校验 DAG 合法性
///
/// 与 `GoalDecomposer` 关系：复用其 LLM 调用与 JSON 解析能力，
/// `HierarchicalDecomposer` 负责层次化包装、约束、依赖生成与校验。
final class HierarchicalDecomposer {

    /// 分解错误
    enum DecomposeError: Error, LocalizedError {
        /// 启发式约束失败：深度/宽度/总数超限
        case heuristicViolation(reason: String)
        /// DAG 校验失败：循环依赖或缺失依赖
        case invalidDAG(reason: String)
        /// LLM 分解返回空
        case emptyDecomposition
        /// 内部 GoalDecomposer 错误，透传
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .heuristicViolation(let reason):
                return "启发式约束失败：\(reason)"
            case .invalidDAG(let reason):
                return "DAG 校验失败：\(reason)"
            case .emptyDecomposition:
                return "LLM 分解返回空子任务列表"
            case .underlying(let error):
                return "底层 GoalDecomposer 错误：\(error.localizedDescription)"
            }
        }
    }

    /// 底层单次 LLM 分解器
    private let goalDecomposer: GoalDecomposer
    /// 启发式规则
    private let rules: HeuristicRules

    /// 创建 HierarchicalDecomposer
    /// - Parameters:
    ///   - goalDecomposer: 底层 LLM 分解器
    ///   - rules: 启发式规则，默认 `.default`
    init(goalDecomposer: GoalDecomposer, rules: HeuristicRules = .default) {
        self.goalDecomposer = goalDecomposer
        self.rules = rules
    }

    /// 层次化分解入口：将用户目标递归分解为受约束的 DAG 子任务列表
    /// - Parameter goal: 用户原始目标
    /// - Returns: 扁平化后的子任务列表（已通过 DAG 校验，依赖已生成）
    /// - Throws: `DecomposeError`
    func decompose(goal: String) async throws -> [SubTask] {
        var collected: [SubTask] = []
        var orderCounter = 0
        try await decomposeRecursively(
            goal: goal,
            currentDepth: 1,
            parentDependencies: [],
            collected: &collected,
            orderCounter: &orderCounter
        )

        guard !collected.isEmpty else {
            throw DecomposeError.emptyDecomposition
        }

        // 启发式约束校验：总数与宽度
        let totalValid = rules.isTotalCountValid(collected.count)
        if !totalValid {
            // 超总数上限时截断（保留前 maxTotalCount 个）
            collected = Array(collected.prefix(rules.maxTotalCount))
        }

        // DAG 合法性校验（循环依赖 + 缺失依赖）
        let (isValid, reason) = HeuristicRules.validateDAG(collected)
        guard isValid else {
            throw DecomposeError.invalidDAG(reason: reason ?? "未知")
        }

        return collected
    }

    /// 递归分解内部实现
    ///
    /// - Parameters:
    ///   - goal: 当前待分解的目标文本（根目标或子任务描述）
    ///   - currentDepth: 当前深度（根分解为 1）
    ///   - parentDependencies: 父节点的依赖列表（子任务继承）
    ///   - collected: 累积收集的子任务列表（inout）
    ///   - orderCounter: 全局 order 计数器（inout）
    private func decomposeRecursively(
        goal: String,
        currentDepth: Int,
        parentDependencies: [UUID],
        collected: inout [SubTask],
        orderCounter: inout Int
    ) async throws {
        // 深度约束：超过 maxDepth 不再分解
        guard rules.canDecompose(depth: currentDepth - 1) else {
            // 深度用尽：将目标作为单个子任务（不再分解）
            let leaf = SubTask(
                title: String(goal.prefix(50)),
                description: goal,
                dependencies: parentDependencies,
                order: orderCounter,
                parallel: false,
                depth: currentDepth
            )
            orderCounter += 1
            collected.append(leaf)
            return
        }

        // 调用底层 GoalDecomposer 进行单次 LLM 分解
        let rawSubTasks: [SubTask]
        do {
            rawSubTasks = try await goalDecomposer.decompose(goal: goal)
        } catch {
            // LLM 分解失败：降级为单叶子节点
            let leaf = SubTask(
                title: String(goal.prefix(50)),
                description: goal,
                dependencies: parentDependencies,
                order: orderCounter,
                parallel: false,
                depth: currentDepth
            )
            orderCounter += 1
            collected.append(leaf)
            return
        }

        guard !rawSubTasks.isEmpty else {
            throw DecomposeError.emptyDecomposition
        }

        // 宽度约束：截断至 maxWidth
        let clamped = rules.clampWidth(rawSubTasks)

        // 设置 depth、order；为同层兄弟生成 DAG 依赖
        var siblings: [SubTask] = clamped.enumerated().map { index, sub in
            var copy = sub
            copy.depth = currentDepth
            copy.order = orderCounter + index
            return copy
        }
        orderCounter += siblings.count

        // 生成同层兄弟依赖（覆盖 LLM 给定的同层依赖，避免循环）
        siblings = rules.generateSiblingDependencies(siblings)

        // 跨层依赖：第一个兄弟节点继承父节点依赖
        if !siblings.isEmpty {
            var firstDeps = siblings[0].dependencies
            for parentDep in parentDependencies where !firstDeps.contains(parentDep) {
                firstDeps.append(parentDep)
            }
            siblings[0].dependencies = firstDeps
        }

        // 总数约束：已超限时不再递归分解，直接收集
        if !rules.isTotalCountValid(collected.count + siblings.count) {
            // 截断到不超过 maxTotalCount
            let remaining = rules.maxTotalCount - collected.count
            if remaining > 0 {
                collected.append(contentsOf: siblings.prefix(remaining))
            }
            return
        }

        // 递归分解：对每个复杂子任务再次分解
        for var sub in siblings {
            // 判断是否需要进一步分解
            if rules.shouldDecompose(subTask: sub, atDepth: currentDepth, currentTotalCount: collected.count + 1) {
                // 递归分解：将本子任务作为新目标
                let subGoal = "\(sub.title)。\(sub.description)"
                let childParentDeps = sub.dependencies // 子节点继承本节点的依赖
                try await decomposeRecursively(
                    goal: subGoal,
                    currentDepth: currentDepth + 1,
                    parentDependencies: childParentDeps,
                    collected: &collected,
                    orderCounter: &orderCounter
                )
            } else {
                // 不再分解，直接收集
                collected.append(sub)
            }
        }
    }

    // MARK: - 同步辅助（不调用 LLM）

    /// 对已存在的子任务列表做启发式约束与 DAG 校验（不调用 LLM）。
    ///
    /// 用于：上层已有 LLM 分解结果，仅需约束与校验时调用。
    /// - Parameter subTasks: 待校验的子任务列表
    /// - Returns: 校验通过的子任务列表（可能被截断）
    /// - Throws: `DecomposeError`
    func applyHeuristics(to subTasks: [SubTask]) throws -> [SubTask] {
        guard !subTasks.isEmpty else {
            throw DecomposeError.emptyDecomposition
        }
        // 总数截断
        var result = rules.isTotalCountValid(subTasks.count) ? subTasks : Array(subTasks.prefix(rules.maxTotalCount))
        // 宽度截断（按 depth 分组，每组内截断至 maxWidth）
        let byDepth = Dictionary(grouping: result, by: \.depth)
        result = byDepth.sorted { $0.key < $1.key }.flatMap { (_, group) -> [SubTask] in
            rules.clampWidth(group)
        }
        // DAG 校验
        let (isValid, reason) = HeuristicRules.validateDAG(result)
        guard isValid else {
            throw DecomposeError.invalidDAG(reason: reason ?? "未知")
        }
        return result
    }
}
