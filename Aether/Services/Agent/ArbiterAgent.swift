import Foundation

// MARK: - ArbiterAgent

/// v3.0: 多 Agent 协作增强 — 冲突仲裁 Agent。
///
/// 职责：
/// - 当多个 Agent 结果冲突时，由 Arbiter 决策最终结果
/// - 支持三种决策策略：多数表决 / 优先级 / 用户介入
/// - 设置最大轮次（默认 5），超限强制用户介入
///
/// 决策策略：
/// - majority: 取多数 Agent 一致的结果
/// - priority: 按角色优先级（reviewer > researcher > executor）
/// - userIntervention: 标记需要用户决策
public final class ArbiterAgent {

    /// 决策策略
    public enum ResolutionStrategy: String, Sendable {
        case majority      // 多数表决
        case priority      // 优先级
        case userIntervention  // 用户介入
    }

    /// 仲裁结果
    public struct ArbitrationResult: Sendable {
        public let winnerAgentId: UUID?
        public let result: String
        public let strategy: ResolutionStrategy
        public let reason: String
        public let round: Int

        public init(winnerAgentId: UUID?, result: String, strategy: ResolutionStrategy, reason: String, round: Int) {
            self.winnerAgentId = winnerAgentId
            self.result = result
            self.strategy = strategy
            self.reason = reason
            self.round = round
        }
    }

    /// Agent 结果输入
    public struct AgentResult: Sendable {
        public let agentId: UUID
        public let role: String
        public let result: String
        public let confidence: Double  // 0.0~1.0

        public init(agentId: UUID, role: String, result: String, confidence: Double) {
            self.agentId = agentId
            self.role = role
            self.result = result
            self.confidence = confidence
        }
    }

    // MARK: - 属性

    /// 最大仲裁轮次（默认 5）
    public let maxRounds: Int

    /// 当前轮次
    private(set) var currentRound: Int = 0

    /// 角色优先级（高 → 低）
    private let rolePriority: [String] = ["reviewer", "researcher", "coordinator", "executor", "planner"]

    // MARK: - 初始化

    public init(maxRounds: Int = 5) {
        self.maxRounds = maxRounds
    }

    // MARK: - 仲裁

    /// 仲裁多个 Agent 的冲突结果
    /// - Parameter results: 多个 Agent 的结果列表
    /// - Returns: 仲裁结果
    public func arbitrate(results: [AgentResult]) -> ArbitrationResult {
        currentRound += 1

        // 单一结果：直接返回
        if results.count == 1 {
            let r = results[0]
            return ArbitrationResult(
                winnerAgentId: r.agentId,
                result: r.result,
                strategy: .majority,
                reason: "单一结果，无需仲裁",
                round: currentRound
            )
        }

        // 检查是否达到最大轮次
        if currentRound > maxRounds {
            return ArbitrationResult(
                winnerAgentId: nil,
                result: "",
                strategy: .userIntervention,
                reason: "达到最大仲裁轮次 \(maxRounds)，需要用户介入",
                round: currentRound
            )
        }

        // 策略 1: 多数表决
        if let majorityResult = resolveByMajority(results) {
            return majorityResult
        }

        // 策略 2: 优先级
        if let priorityResult = resolveByPriority(results) {
            return priorityResult
        }

        // 兜底：用户介入
        return ArbitrationResult(
            winnerAgentId: nil,
            result: "",
            strategy: .userIntervention,
            reason: "无法通过多数表决或优先级仲裁，需要用户介入",
            round: currentRound
        )
    }

    /// 重置仲裁轮次
    public func reset() {
        currentRound = 0
    }

    // MARK: - 私有：决策策略

    /// 多数表决：相同结果占比 ≥60% 则采纳
    private func resolveByMajority(_ results: [AgentResult]) -> ArbitrationResult? {
        // 按结果文本分组
        var groups: [String: [AgentResult]] = [:]
        for r in results {
            // 简单归一化：去除首尾空白后比较
            let normalized = r.result.trimmingCharacters(in: .whitespacesAndNewlines)
            groups[normalized, default: []].append(r)
        }

        // 找出占比最高的组
        let sortedGroups = groups.sorted { $0.value.count > $1.value.count }
        guard let topGroup = sortedGroups.first else { return nil }

        let ratio = Double(topGroup.value.count) / Double(results.count)
        if ratio >= 0.6 {
            // 取该组中置信度最高的
            let winner = topGroup.value.max(by: { $0.confidence < $1.confidence })!
            return ArbitrationResult(
                winnerAgentId: winner.agentId,
                result: winner.result,
                strategy: .majority,
                reason: "多数表决通过：\(topGroup.value.count)/\(results.count)（\(String(format: "%.0f%%", ratio * 100))）一致",
                round: currentRound
            )
        }
        return nil
    }

    /// 优先级：按角色优先级选择
    private func resolveByPriority(_ results: [AgentResult]) -> ArbitrationResult? {
        // 按 rolePriority 排序
        let sorted = results.sorted { a, b in
            let aPriority = rolePriority.firstIndex(of: a.role) ?? Int.max
            let bPriority = rolePriority.firstIndex(of: b.role) ?? Int.max
            if aPriority != bPriority {
                return aPriority < bPriority
            }
            // 同优先级：按置信度
            return a.confidence > b.confidence
        }

        guard let winner = sorted.first else { return nil }
        return ArbitrationResult(
            winnerAgentId: winner.agentId,
            result: winner.result,
            strategy: .priority,
            reason: "按角色优先级选择：\(winner.role)（置信度 \(String(format: "%.0f%%", winner.confidence * 100))）",
            round: currentRound
        )
    }
}
