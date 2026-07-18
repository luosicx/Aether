import Foundation

/// Task 20 阶段 2: 节点状态机。
///
/// 管理子任务节点的状态迁移：`pending → running → completed/failed/skipped`，
/// 使用 actor 保证线程安全（并行调度场景下多节点同时迁移）。
///
/// 状态迁移规则：
/// - `pending → running`：节点被引擎选中开始执行
/// - `running → completed`：执行成功
/// - `running → failed`：执行失败（重试用尽后）
/// - `pending → skipped`：依赖节点被跳过导致本节点也跳过
/// - `failed → running`：用户手动重试
/// - `failed → skipped`：用户手动跳过
/// - 其他迁移视为非法，抛错
actor NodeStateMachine {

    /// 状态机错误
    enum StateMachineError: Error, LocalizedError {
        /// 非法状态迁移
        case illegalTransition(from: SubTaskStatus, to: SubTaskStatus, nodeID: UUID)
        /// 节点未找到
        case nodeNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .illegalTransition(let from, let to, let id):
                return "非法状态迁移：节点 \(id) \(from.rawValue) → \(to.rawValue)"
            case .nodeNotFound(let id):
                return "节点未找到：\(id)"
            }
        }
    }

    /// 节点状态快照（id -> status）
    private var statuses: [UUID: SubTaskStatus] = [:]
    /// 节点尝试次数（用于重试计数）
    private var attemptCounts: [UUID: Int] = [:]

    /// 初始化：批量注册节点（默认 pending）
    /// - Parameter nodeIDs: 节点 ID 列表
    init(nodeIDs: [UUID] = []) {
        for id in nodeIDs {
            statuses[id] = .pending
            attemptCounts[id] = 0
        }
    }

    /// 注册单个节点
    /// - Parameter nodeID: 节点 ID
    func register(nodeID: UUID) {
        if statuses[nodeID] == nil {
            statuses[nodeID] = .pending
            attemptCounts[nodeID] = 0
        }
    }

    /// 批量注册节点
    /// - Parameter nodeIDs: 节点 ID 列表
    func register(nodeIDs: [UUID]) {
        for id in nodeIDs where statuses[id] == nil {
            statuses[id] = .pending
            attemptCounts[id] = 0
        }
    }

    /// 获取节点当前状态
    /// - Parameter nodeID: 节点 ID
    /// - Returns: 节点状态；未注册返回 nil
    func status(of nodeID: UUID) -> SubTaskStatus? {
        statuses[nodeID]
    }

    /// 获取所有处于指定状态的节点 ID
    /// - Parameter status: 目标状态
    /// - Returns: 节点 ID 列表
    func nodeIDs(in status: SubTaskStatus) -> [UUID] {
        statuses.compactMap { $0.value == status ? $0.key : nil }
    }

    /// 获取节点的尝试次数
    /// - Parameter nodeID: 节点 ID
    /// - Returns: 尝试次数
    func attemptCount(of nodeID: UUID) -> Int {
        attemptCounts[nodeID] ?? 0
    }

    /// 标记节点为 inProgress
    /// - Parameter nodeID: 节点 ID
    /// - Throws: `StateMachineError`：节点未找到或非法迁移
    func markRunning(_ nodeID: UUID) throws {
        guard let current = statuses[nodeID] else {
            throw StateMachineError.nodeNotFound(nodeID)
        }
        // 允许 pending → inProgress，failed → inProgress（重试）
        guard current == .pending || current == .failed else {
            throw StateMachineError.illegalTransition(from: current, to: .inProgress, nodeID: nodeID)
        }
        statuses[nodeID] = .inProgress
        attemptCounts[nodeID, default: 0] += 1
    }

    /// 标记节点为 completed
    /// - Parameter nodeID: 节点 ID
    /// - Throws: `StateMachineError`：节点未找到或非法迁移
    func markCompleted(_ nodeID: UUID) throws {
        guard let current = statuses[nodeID] else {
            throw StateMachineError.nodeNotFound(nodeID)
        }
        guard current == .inProgress else {
            throw StateMachineError.illegalTransition(from: current, to: .completed, nodeID: nodeID)
        }
        statuses[nodeID] = .completed
    }

    /// 标记节点为 failed
    /// - Parameter nodeID: 节点 ID
    /// - Throws: `StateMachineError`：节点未找到或非法迁移
    func markFailed(_ nodeID: UUID) throws {
        guard let current = statuses[nodeID] else {
            throw StateMachineError.nodeNotFound(nodeID)
        }
        guard current == .inProgress else {
            throw StateMachineError.illegalTransition(from: current, to: .failed, nodeID: nodeID)
        }
        statuses[nodeID] = .failed
    }

    /// 标记节点为 skipped（依赖失败或用户跳过）
    /// - Parameter nodeID: 节点 ID
    /// - Throws: `StateMachineError`：节点未找到或非法迁移
    func markSkipped(_ nodeID: UUID) throws {
        guard let current = statuses[nodeID] else {
            throw StateMachineError.nodeNotFound(nodeID)
        }
        // 允许 pending → skipped，failed → skipped（用户跳过失败节点）
        guard current == .pending || current == .failed else {
            throw StateMachineError.illegalTransition(from: current, to: .skipped, nodeID: nodeID)
        }
        statuses[nodeID] = .skipped
    }

    /// 重置节点为 pending（用于重置整个任务状态）
    /// - Parameter nodeID: 节点 ID
    func reset(_ nodeID: UUID) {
        statuses[nodeID] = .pending
        attemptCounts[nodeID] = 0
    }

    /// 重置所有节点为 pending
    func resetAll() {
        for id in statuses.keys {
            statuses[id] = .pending
            attemptCounts[id] = 0
        }
    }

    /// 直接覆盖节点状态（绕过迁移校验，用于初始化恢复场景）
    /// - Parameters:
    ///   - nodeID: 节点 ID
    ///   - status: 目标状态
    func override(nodeID: UUID, status: SubTaskStatus) {
        statuses[nodeID] = status
        // 同时确保 attemptCounts 有值
        if attemptCounts[nodeID] == nil {
            attemptCounts[nodeID] = 0
        }
    }

    /// 当前快照：返回所有节点状态
    /// - Returns: 节点 ID → 状态字典
    func snapshot() -> [UUID: SubTaskStatus] {
        statuses
    }

    /// 是否所有节点都处于终止状态（completed / failed / skipped）
    func isAllTerminal() -> Bool {
        !statuses.isEmpty && statuses.values.allSatisfy { $0 == .completed || $0 == .failed || $0 == .skipped }
    }

    /// 已完成（含 skipped）的节点数
    var completedCount: Int {
        statuses.values.filter { $0 == .completed || $0 == .skipped }.count
    }

    /// 总节点数
    var totalCount: Int {
        statuses.count
    }
}
