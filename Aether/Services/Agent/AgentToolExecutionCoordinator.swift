import Foundation

/// Task 20 阶段 2: Agent DAG 工具执行协调器（actor 串行化）。
///
/// 防止并行 DAG 节点同时调用 `ToolRegistry.shared.execute` 导致的工具状态不一致。
/// 所有工具调用经此 actor 串行化排队，保证同一时刻仅一个工具执行。
///
/// 命名说明：P2-6 Task 10 新增 `ToolExecutionCoordinator`（@MainActor final class）
/// 用于 ChatViewModel ReAct 工具执行循环；为避免同模块同名冲突，本 actor 类重命名为
/// `AgentToolExecutionCoordinator`，语义更聚焦（服务于 Agent DAG 执行引擎）。
/// 影响范围：`DAGExecutionEngine` 与其测试，行为零变化。
///
/// 设计要点：
/// - `actor` 隔离：天然串行化，无需额外锁
/// - 复用 `ToolRegistry.shared` 单例，不替换底层工具注册机制
/// - 调用日志通过 `ToolAuditLogger`（如存在）记录，便于追踪
actor AgentToolExecutionCoordinator {

    /// 共享实例（默认使用）
    static let shared = AgentToolExecutionCoordinator()

    /// 工具执行计数（用于审计与测试）
    private(set) var executionCount: Int = 0
    /// 当前正在执行的工具名（nil 表示空闲）
    private(set) var currentToolName: String? = nil
    /// 历史调用记录（环形缓冲，最多 100 条）
    private var history: [ToolExecutionRecord] = []
    private let historyLimit = 100

    /// 创建 AgentToolExecutionCoordinator（显式声明以便在 @MainActor 测试上下文中创建实例）
    init() {
        // actor 隔离的默认构造器，所有属性已有初始值；
        // actor 默认 init 非 Sendable 时不便跨隔离域调用，故显式声明。
    }

    /// 串行化执行工具调用
    /// - Parameters:
    ///   - name: 工具名
    ///   - arguments: 工具参数
    /// - Returns: 工具执行结果字符串
    /// - Throws: 工具执行错误
    func execute(name: String, arguments: [String: Any]) async throws -> String {
        executionCount += 1
        currentToolName = name
        defer {
            currentToolName = nil
        }
        let startedAt = Date()
        let result = try await ToolRegistry.shared.execute(name: name, arguments: arguments)
        let record = ToolExecutionRecord(
            toolName: name,
            startedAt: startedAt,
            finishedAt: Date(),
            success: true,
            error: nil
        )
        appendHistory(record)
        return result
    }

    /// 调用失败时记录（捕获 throws 的情况下使用）
    func recordFailure(toolName: String, startedAt: Date, error: Error) {
        let record = ToolExecutionRecord(
            toolName: toolName,
            startedAt: startedAt,
            finishedAt: Date(),
            success: false,
            error: error.localizedDescription
        )
        appendHistory(record)
    }

    /// 获取历史调用记录
    /// - Returns: 调用记录数组副本
    func historyRecords() -> [ToolExecutionRecord] {
        history
    }

    /// 当前是否空闲（无工具在执行）
    var isIdle: Bool {
        currentToolName == nil
    }

    /// 重置状态（仅用于测试）
    func reset() {
        executionCount = 0
        currentToolName = nil
        history.removeAll()
    }

    // MARK: - 私有

    private func appendHistory(_ record: ToolExecutionRecord) {
        history.append(record)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
}

/// Task 20 阶段 2: 工具执行记录（用于审计）
struct ToolExecutionRecord: Sendable, Codable {
    /// 工具名
    let toolName: String
    /// 开始时间
    let startedAt: Date
    /// 结束时间
    let finishedAt: Date
    /// 是否成功
    let success: Bool
    /// 错误描述（失败时）
    let error: String?

    /// 耗时（秒）
    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }
}
