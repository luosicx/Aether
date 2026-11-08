import Foundation

// MARK: - WorkflowDefinition

/// v3.0: AI Workflow 自动化 — 工作流定义与执行引擎。
///
/// 职责：
/// - 定义可视化工作流数据模型（节点 + 连接 + 触发器）
/// - 支持节点类型：触发器 / 条件 / 循环 / 动作 / 输入输出
/// - 工作流序列化为 JSON，可导入导出
/// - 执行引擎复用 DAGExecutionEngine，扩展支持循环与条件分支
///
/// MVP 范围：
/// - 线性 + 条件分支（循环后置）
/// - 节点类型：定时触发 / 手动触发 / LLM 调用 / 工具调用 / 条件分支 / 输出

// MARK: - WorkflowNode

/// 工作流节点
public struct WorkflowNode: Identifiable, Sendable, Codable {

    /// 节点类型
    public enum NodeType: String, Sendable, Codable {
        case triggerTimer     // 定时触发
        case triggerManual    // 手动触发
        case triggerEvent     // 事件触发
        case actionLLM        // 调用 LLM
        case actionTool       // 调用工具
        case actionAgent      // 调用 Agent
        case conditionIfElse  // 条件分支
        case output           // 输出
        case input            // 输入

        /// 是否为触发器
        public var isTrigger: Bool {
            switch self {
            case .triggerTimer, .triggerManual, .triggerEvent: return true
            default: return false
            }
        }
    }

    /// 节点 ID
    public let id: UUID
    /// 节点类型
    public let type: NodeType
    /// 节点名称
    public var name: String
    /// 节点配置（JSON 字符串）
    public var config: [String: String]
    /// 位置 x（编辑器可视化用）
    public var positionX: Double
    /// 位置 y
    public var positionY: Double

    public init(
        id: UUID = UUID(),
        type: NodeType,
        name: String,
        config: [String: String] = [:],
        positionX: Double = 0,
        positionY: Double = 0
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.config = config
        self.positionX = positionX
        self.positionY = positionY
    }
}

// MARK: - WorkflowEdge

/// 工作流连接（节点间的边）
public struct WorkflowEdge: Identifiable, Sendable, Codable {

    /// 边 ID
    public let id: UUID
    /// 源节点 ID
    public let sourceId: UUID
    /// 目标节点 ID
    public let targetId: UUID
    /// 条件标签（条件分支用，如 "true" / "false"）
    public let condition: String?

    public init(
        id: UUID = UUID(),
        sourceId: UUID,
        targetId: UUID,
        condition: String? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.condition = condition
    }
}

// MARK: - Workflow

/// 完整工作流定义
public struct Workflow: Identifiable, Sendable, Codable {

    /// 工作流 ID
    public let id: UUID
    /// 工作流名称
    public var name: String
    /// 描述
    public var description: String
    /// 节点列表
    public var nodes: [WorkflowNode]
    /// 连接列表
    public var edges: [WorkflowEdge]
    /// 创建时间
    public let createdAt: Date
    /// 更新时间
    public var updatedAt: Date
    /// 是否启用
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        nodes: [WorkflowNode] = [],
        edges: [WorkflowEdge] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.nodes = nodes
        self.edges = edges
        self.createdAt = Date()
        self.updatedAt = Date()
        self.enabled = enabled
    }

    /// 入口节点（触发器）
    public var triggerNode: WorkflowNode? {
        nodes.first(where: { $0.type.isTrigger })
    }

    /// 节点数
    public var nodeCount: Int { nodes.count }

    /// 边数
    public var edgeCount: Int { edges.count }

    /// 导出为 JSON 字符串
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 从 JSON 字符串导入
    public static func fromJSON(_ json: String) throws -> Workflow {
        guard let data = json.data(using: .utf8) else {
            throw WorkflowError.invalidJSON
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Workflow.self, from: data)
    }
}

// MARK: - WorkflowExecutionResult

/// 工作流执行结果
public struct WorkflowExecutionResult: Sendable {

    /// 工作流 ID
    public let workflowId: UUID
    /// 是否成功
    public let success: Bool
    /// 各节点执行结果
    public let nodeResults: [NodeExecutionResult]
    /// 总耗时（秒）
    public let durationSeconds: Double
    /// 失败节点 ID（若有）
    public let failedNodeId: UUID?
    /// 失败原因
    public let failureReason: String?
    /// 最终输出
    public let finalOutput: String?

    public init(
        workflowId: UUID,
        success: Bool,
        nodeResults: [NodeExecutionResult],
        durationSeconds: Double,
        failedNodeId: UUID? = nil,
        failureReason: String? = nil,
        finalOutput: String? = nil
    ) {
        self.workflowId = workflowId
        self.success = success
        self.nodeResults = nodeResults
        self.durationSeconds = durationSeconds
        self.failedNodeId = failedNodeId
        self.failureReason = failureReason
        self.finalOutput = finalOutput
    }
}

/// 单节点执行结果
public struct NodeExecutionResult: Sendable, Identifiable {

    public let id: UUID
    public let nodeId: UUID
    public let nodeName: String
    public let nodeType: WorkflowNode.NodeType
    public let output: String
    public let durationSeconds: Double
    public let success: Bool
    public let error: String?

    public init(
        id: UUID = UUID(),
        nodeId: UUID,
        nodeName: String,
        nodeType: WorkflowNode.NodeType,
        output: String,
        durationSeconds: Double,
        success: Bool,
        error: String? = nil
    ) {
        self.id = id
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.nodeType = nodeType
        self.output = output
        self.durationSeconds = durationSeconds
        self.success = success
        self.error = error
    }
}

// MARK: - WorkflowError

public enum WorkflowError: Error, LocalizedError {
    case noTriggerNode
    case cycleDetected
    case nodeNotFound(UUID)
    case invalidJSON
    case executionFailed(UUID, String)
    case maxNodesExceeded

    public var errorDescription: String? {
        switch self {
        case .noTriggerNode: return "工作流缺少触发器节点"
        case .cycleDetected: return "检测到循环依赖"
        case .nodeNotFound(let id): return "节点不存在: \(id)"
        case .invalidJSON: return "JSON 格式无效"
        case .executionFailed(let id, let reason): return "节点 \(id) 执行失败: \(reason)"
        case .maxNodesExceeded: return "节点数超过上限"
        }
    }
}

// MARK: - WorkflowEngine

/// 工作流执行引擎
public final class WorkflowEngine {

    /// 最大节点数（防止过度复杂）
    public let maxNodes: Int

    /// 初始化
    public init(maxNodes: Int = 50) {
        self.maxNodes = maxNodes
    }

    /// 验证工作流（DAG + 有触发器 + 节点数）
    public func validate(_ workflow: Workflow) throws {
        // 检查节点数
        guard workflow.nodes.count <= maxNodes else {
            throw WorkflowError.maxNodesExceeded
        }

        // 检查触发器
        guard workflow.triggerNode != nil else {
            throw WorkflowError.noTriggerNode
        }

        // 检查循环依赖（拓扑排序）
        if hasCycle(workflow) {
            throw WorkflowError.cycleDetected
        }
    }

    /// 执行工作流（骨架实现）
    /// v3.0 骨架：实际执行复用 DAGExecutionEngine，当前为线性模拟
    public func execute(_ workflow: Workflow, input: String = "") async -> WorkflowExecutionResult {
        let startTime = Date()
        var results: [NodeExecutionResult] = []
        var currentInput = input
        var failedNodeId: UUID?
        var failureReason: String?

        // 简单线性执行：从触发器开始，按边连接依次执行
        var currentNode = workflow.triggerNode
        var executedNodes = Set<UUID>()

        while let node = currentNode {
            if executedNodes.contains(node.id) {
                break  // 防止死循环
            }
            executedNodes.insert(node.id)

            let nodeStart = Date()
            let output: String
            let success: Bool
            var error: String? = nil

            switch node.type {
            case .triggerTimer, .triggerManual, .triggerEvent:
                output = currentInput
                success = true
            case .actionLLM:
                // v3.0 骨架：实际调用 LLMProvider
                output = "[LLM 节点] 处理输入：\(currentInput.prefix(50))..."
                success = true
            case .actionTool:
                output = "[工具节点] 执行工具：\(node.config["toolName"] ?? "unknown")"
                success = true
            case .actionAgent:
                output = "[Agent 节点] 执行 Agent：\(node.config["agentRole"] ?? "executor")"
                success = true
            case .conditionIfElse:
                // 简单条件：检查输入是否包含 "error"
                let condition = node.config["condition"] ?? ""
                if currentInput.lowercased().contains(condition.lowercased()) {
                    output = "条件满足"
                } else {
                    output = "条件不满足"
                }
                success = true
            case .output:
                output = currentInput
                success = true
            case .input:
                output = currentInput
                success = true
            }

            let duration = Date().timeIntervalSince(nodeStart)
            let result = NodeExecutionResult(
                nodeId: node.id,
                nodeName: node.name,
                nodeType: node.type,
                output: output,
                durationSeconds: duration,
                success: success,
                error: error
            )
            results.append(result)

            if !success {
                failedNodeId = node.id
                failureReason = error
                break
            }

            currentInput = output

            // 找下一个节点（无条件的边优先）
            let nextEdges = workflow.edges.filter { $0.sourceId == node.id }
            currentNode = nextEdges.first.flatMap { edge in
                workflow.nodes.first(where: { $0.id == edge.targetId })
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let finalOutput = results.last?.output

        return WorkflowExecutionResult(
            workflowId: workflow.id,
            success: failedNodeId == nil,
            nodeResults: results,
            durationSeconds: totalDuration,
            failedNodeId: failedNodeId,
            failureReason: failureReason,
            finalOutput: finalOutput
        )
    }

    // MARK: - 私有

    /// 检测循环依赖（DFS）
    private func hasCycle(_ workflow: Workflow) -> Bool {
        var visited = Set<UUID>()
        var recursionStack = Set<UUID>()

        func dfs(_ nodeId: UUID) -> Bool {
            visited.insert(nodeId)
            recursionStack.insert(nodeId)

            let neighbors = workflow.edges.filter { $0.sourceId == nodeId }
            for edge in neighbors {
                if !visited.contains(edge.targetId) {
                    if dfs(edge.targetId) { return true }
                } else if recursionStack.contains(edge.targetId) {
                    return true
                }
            }
            recursionStack.remove(nodeId)
            return false
        }

        for node in workflow.nodes {
            if !visited.contains(node.id) {
                if dfs(node.id) { return true }
            }
        }
        return false
    }
}
