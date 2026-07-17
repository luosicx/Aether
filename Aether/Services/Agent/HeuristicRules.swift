import Foundation

/// Task 20 阶段 1: 启发式规则约束。
///
/// 提供 LLM 驱动层次化分解的边界约束与复杂度判断：
/// - 分解深度 ≤ `maxDepth`（默认 3）
/// - 每层宽度 ≤ `maxWidth`（默认 8）
/// - 子任务总数 ≤ `maxTotalCount`（默认 50）
/// - 复杂度启发式：描述长度 > `complexityLengthThreshold` 字或含连接词触发递归分解
///
/// 所有方法为 `static`，无状态，便于单元测试与跨线程调用。
struct HeuristicRules {

    /// 默认最大深度
    static let defaultMaxDepth = 3
    /// 默认最大宽度（单层子任务数）
    static let defaultMaxWidth = 8
    /// 默认最大总子任务数
    static let defaultMaxTotalCount = 50
    /// 复杂度阈值：描述字符数 > 此值则视为复杂
    static let complexityLengthThreshold = 100
    /// 触发递归分解的连接词
    static let complexityConnectors: [String] = ["并且", "然后", "之后", "接着", "同时", "此外", "另外"]

    /// 可配置规则参数（默认值同上）
    let maxDepth: Int
    let maxWidth: Int
    let maxTotalCount: Int
    let complexityLengthThreshold: Int
    let complexityConnectors: [String]

    init(maxDepth: Int = HeuristicRules.defaultMaxDepth,
         maxWidth: Int = HeuristicRules.defaultMaxWidth,
         maxTotalCount: Int = HeuristicRules.defaultMaxTotalCount,
         complexityLengthThreshold: Int = HeuristicRules.complexityLengthThreshold,
         complexityConnectors: [String] = HeuristicRules.complexityConnectors) {
        self.maxDepth = maxDepth
        self.maxWidth = maxWidth
        self.maxTotalCount = maxTotalCount
        self.complexityLengthThreshold = complexityLengthThreshold
        self.complexityConnectors = complexityConnectors
    }

    /// 默认规则实例
    static let `default` = HeuristicRules()

    // MARK: - 深度/宽度/总数约束

    /// 判断当前深度是否允许继续分解
    /// - Parameter currentDepth: 当前深度（根任务为 0，第一次分解后子节点为 1）
    /// - Returns: true 表示可继续分解
    func canDecompose(depth currentDepth: Int) -> Bool {
        currentDepth < maxDepth
    }

    /// 判断给定宽度是否在约束内
    /// - Parameter width: 当前层的子任务数
    /// - Returns: true 表示在约束内
    func isWidthValid(_ width: Int) -> Bool {
        width <= maxWidth
    }

    /// 判断给定总子任务数是否在约束内
    /// - Parameter totalCount: 总子任务数
    /// - Returns: true 表示在约束内
    func isTotalCountValid(_ totalCount: Int) -> Bool {
        totalCount <= maxTotalCount
    }

    /// 截断子任务列表至允许的最大宽度
    /// - Parameter subTasks: 待截断的子任务列表
    /// - Returns: 截断后的列表（长度 ≤ maxWidth）
    func clampWidth(_ subTasks: [SubTask]) -> [SubTask] {
        guard subTasks.count > maxWidth else { return subTasks }
        return Array(subTasks.prefix(maxWidth))
    }

    // MARK: - 复杂度启发式

    /// 判断子任务描述是否触发递归分解
    ///
    /// 满足以下任一条件即视为复杂，需要递归分解：
    /// 1. 描述字符数 > `complexityLengthThreshold`
    /// 2. 描述中包含任一连接词（"并且"/"然后"/"之后"/"接着"/"同时"/"此外"/"另外"）
    /// - Parameter description: 子任务描述
    /// - Returns: true 表示需要递归分解
    func shouldDecomposeFurther(description: String) -> Bool {
        guard !description.isEmpty else { return false }
        if description.count > complexityLengthThreshold {
            return true
        }
        for connector in complexityConnectors where description.contains(connector) {
            return true
        }
        return false
    }

    /// 判断子任务是否需要递归分解（基于 SubTask 实例，综合 description + title）
    /// - Parameter subTask: 待判断的子任务
    /// - Parameter currentDepth: 当前子任务深度
    /// - Parameter currentTotalCount: 当前已分解出的总子任务数（含本节点）
    /// - Returns: true 表示应继续分解
    func shouldDecompose(subTask: SubTask, atDepth currentDepth: Int, currentTotalCount: Int) -> Bool {
        // 深度用尽或总数超限时不再分解
        guard canDecompose(depth: currentDepth) else { return false }
        guard currentTotalCount < maxTotalCount else { return false }
        // 综合 description 与 title
        let combined = "\(subTask.title) \(subTask.description)"
        return shouldDecomposeFurther(description: combined)
    }

    // MARK: - DAG 依赖生成

    /// 为同层兄弟子任务生成 DAG 依赖：默认串行，parallel=true 节点无相互依赖。
    ///
    /// 规则：
    /// - 同层兄弟节点按 `order` 排序
    /// - 第一个节点无依赖（依赖列表清空）
    /// - 后续节点：
    ///   - 若 `parallel == true`：依赖列表清空（与同层兄弟无依赖）
    ///   - 若 `parallel == false`（默认）：依赖前一个非 parallel 节点的 ID
    /// - 跨层依赖由 `HierarchicalDecomposer` 单独处理（子任务继承父节点依赖）
    /// - Parameter siblings: 同层兄弟子任务
    /// - Returns: 处理后的兄弟子任务列表（依赖已生成）
    func generateSiblingDependencies(_ siblings: [SubTask]) -> [SubTask] {
        guard !siblings.isEmpty else { return [] }
        var result = siblings.sorted { $0.order < $1.order }
        // 第一个：清空依赖
        result[0].dependencies = []
        // 后续：根据 parallel 决定是否依赖前一个
        var lastNonParallelIndex: Int? = nil
        for index in result.indices {
            if index == 0 {
                if !result[index].parallel {
                    lastNonParallelIndex = index
                }
                continue
            }
            if result[index].parallel {
                // parallel 节点：清空依赖（不依赖兄弟）
                result[index].dependencies = []
            } else {
                // 串行节点：依赖上一个非 parallel 节点
                if let prev = lastNonParallelIndex {
                    let prevID = result[prev].id
                    // 去重后加入前一个非 parallel 节点 ID
                    var deps = result[index].dependencies.filter { $0 != prevID }
                    deps.append(prevID)
                    result[index].dependencies = deps
                } else {
                    // 前面所有都是 parallel，本节点不依赖任何兄弟
                    result[index].dependencies = []
                }
                lastNonParallelIndex = index
            }
        }
        return result
    }

    // MARK: - 拓扑排序与循环依赖检测（Kahn 算法）

    /// Kahn 算法拓扑排序：检测是否存在循环依赖并返回拓扑顺序。
    ///
    /// - Parameter subTasks: 子任务列表
    /// - Returns: `(isAcyclic: Bool, topologicalOrder: [UUID])`
    ///   - `isAcyclic == true` 时 `topologicalOrder` 为合法拓扑序
    ///   - `isAcyclic == false` 时存在循环依赖，`topologicalOrder` 为部分排序
    static func topologicalSort(_ subTasks: [SubTask]) -> (isAcyclic: Bool, topologicalOrder: [UUID]) {
        var inDegree: [UUID: Int] = [:]
        var adjacency: [UUID: [UUID]] = [:]
        // 初始化
        for sub in subTasks {
            inDegree[sub.id] = 0
            adjacency[sub.id] = []
        }
        // 构建邻接表与入度
        for sub in subTasks {
            for depID in sub.dependencies {
                // 仅当依赖存在于子任务集合中时计入
                if inDegree[depID] != nil {
                    adjacency[depID]?.append(sub.id)
                    inDegree[sub.id, default: 0] += 1
                }
            }
        }
        // 自环检测：依赖包含自身视为循环
        for sub in subTasks where sub.dependencies.contains(sub.id) {
            return (false, [])
        }

        // Kahn 算法
        var queue: [UUID] = inDegree.filter { $0.value == 0 }.map(\.key)
        var order: [UUID] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            order.append(node)
            if let neighbors = adjacency[node] {
                for neighbor in neighbors {
                    inDegree[neighbor, default: 0] -= 1
                    if inDegree[neighbor] == 0 {
                        queue.append(neighbor)
                    }
                }
            }
        }
        let isAcyclic = order.count == subTasks.count
        return (isAcyclic, order)
    }

    /// 检测子任务列表中是否存在循环依赖
    /// - Parameter subTasks: 子任务列表
    /// - Returns: true 表示存在循环依赖
    static func hasCycle(_ subTasks: [SubTask]) -> Bool {
        !topologicalSort(subTasks).isAcyclic
    }

    /// 校验子任务列表的 DAG 合法性：
    /// - 无循环依赖
    /// - 所有 dependencies 引用的 ID 都在子任务集合内（缺失依赖视为非法）
    /// - Parameter subTasks: 子任务列表
    /// - Returns: 校验结果与失败原因
    static func validateDAG(_ subTasks: [SubTask]) -> (isValid: Bool, reason: String?) {
        // 1. 检测缺失依赖
        let knownIDs = Set(subTasks.map(\.id))
        for sub in subTasks {
            let missing = sub.dependencies.filter { !knownIDs.contains($0) }
            if !missing.isEmpty {
                return (false, "子任务 \(sub.title) 引用了不存在的依赖：\(missing)")
            }
        }
        // 2. 检测循环依赖
        let (isAcyclic, _) = topologicalSort(subTasks)
        if !isAcyclic {
            return (false, "子任务 DAG 存在循环依赖")
        }
        return (true, nil)
    }
}
