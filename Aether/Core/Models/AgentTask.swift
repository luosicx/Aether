import Foundation
import SwiftData

/// Task 9: Agent 任务实体。持久化用户目标以及由 LLM 分解出的子任务列表。
///
/// 字段说明：
/// - `goal`：用户原始目标文本
/// - `subTasks`：LLM 分解出的子任务列表（JSON 编码存储）
/// - `status`：任务整体状态（pending / inProgress / completed / failed / cancelled）
/// - `conversationID`：可选的关联会话 ID，用于和 Conversation 联动
@Model
final class AgentTask {
    /// 任务唯一标识
    var id: UUID
    /// 用户原始目标
    var goal: String
    /// 子任务列表（SwiftData 以 transformable 方式存储 Codable 数组）
    var subTasks: [SubTask]
    /// 任务整体状态
    var status: AgentTaskStatus
    /// 创建时间
    var createdAt: Date
    /// 最近更新时间
    var updatedAt: Date
    /// 关联的会话 ID（可选）
    var conversationID: UUID?

    /// 创建 AgentTask 实例
    /// - Parameters:
    ///   - goal: 用户原始目标
    ///   - conversationID: 关联的会话 ID，默认 nil
    init(goal: String, conversationID: UUID? = nil) {
        self.id = UUID()
        self.goal = goal
        self.subTasks = []
        self.status = .pending
        self.createdAt = Date()
        self.updatedAt = Date()
        self.conversationID = conversationID
    }

    // MARK: - 状态变更辅助方法

    /// 标记任务为进行中，并刷新 updatedAt
    func markInProgress() {
        status = .inProgress
        updatedAt = Date()
    }

    /// 标记任务已完成，并刷新 updatedAt
    func markCompleted() {
        status = .completed
        updatedAt = Date()
    }

    /// 标记任务失败，并刷新 updatedAt
    func markFailed() {
        status = .failed
        updatedAt = Date()
    }

    /// 标记任务已取消，并刷新 updatedAt
    func cancel() {
        status = .cancelled
        updatedAt = Date()
    }

    /// 替换子任务列表，并刷新 updatedAt
    /// - Parameter subTasks: 新的子任务列表
    func updateSubTasks(_ subTasks: [SubTask]) {
        self.subTasks = subTasks
        self.updatedAt = Date()
    }

    /// 更新指定子任务的状态
    /// - Parameters:
    ///   - subTaskID: 子任务 ID
    ///   - status: 新状态
    ///   - result: 可选的执行结果，非 nil 时写入 subTask.result
    /// - Returns: 是否成功更新（找不到对应子任务时返回 false）
    @discardableResult
    func updateSubTaskStatus(id subTaskID: UUID, status: SubTaskStatus, result: String? = nil) -> Bool {
        guard let index = subTasks.firstIndex(where: { $0.id == subTaskID }) else {
            return false
        }
        subTasks[index].status = status
        if let result = result {
            subTasks[index].result = result
        }
        updatedAt = Date()
        return true
    }

    /// 返回下一个可执行的子任务（pending 且依赖全部已完成）
    /// - Returns: 下一个可执行的子任务；若无返回 nil
    func nextExecutableSubTask() -> SubTask? {
        let completedIDs = Set(subTasks.filter { $0.status == .completed }.map(\.id))
        return subTasks
            .filter { $0.status == .pending }
            .filter { subTask in
                // 依赖列表中的所有 ID 均需在 completedIDs 中
                Set(subTask.dependencies).isSubset(of: completedIDs)
            }
            .sorted { $0.order < $1.order }
            .first
    }

    /// 是否所有子任务都已完成
    var isAllSubTasksCompleted: Bool {
        !subTasks.isEmpty && subTasks.allSatisfy { $0.status == .completed }
    }
}

// MARK: - SubTask

/// 子任务结构体。JSON 编码后随 AgentTask 一起持久化。
struct SubTask: Codable, Identifiable, Hashable {
    /// 子任务唯一标识
    let id: UUID
    /// 子任务标题
    var title: String
    /// 子任务描述
    var description: String
    /// 子任务状态
    var status: SubTaskStatus
    /// 依赖的子任务 ID 列表（必须先于本子任务完成）
    var dependencies: [UUID]
    /// 使用的工具名（可选，对应 ToolRegistry 中注册的工具）
    var toolName: String?
    /// 执行结果（可选）
    var result: String?
    /// 执行顺序，数值越小越先执行
    var order: Int

    /// 创建 SubTask 实例
    /// - Parameters:
    ///   - title: 子任务标题
    ///   - description: 子任务描述，默认空字符串
    ///   - dependencies: 依赖的子任务 ID 列表，默认空数组
    ///   - toolName: 使用的工具名，默认 nil
    ///   - order: 执行顺序，默认 0
    init(title: String, description: String = "", dependencies: [UUID] = [], toolName: String? = nil, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.status = .pending
        self.dependencies = dependencies
        self.toolName = toolName
        self.result = nil
        self.order = order
    }

    /// 用于 LLM 返回的 JSON 解码：id 可选以便 LLM 不返回 id 时自动生成
    /// - SeeAlso: `GoalDecomposer.parseSubTasks(from:)`
    enum CodingKeys: String, CodingKey {
        case id, title, description, status, dependencies, toolName, result, order
    }

    /// 自定义解码：id 缺失时自动生成新 UUID；status 缺失时默认 .pending
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.status = try c.decodeIfPresent(SubTaskStatus.self, forKey: .status) ?? .pending
        self.dependencies = try c.decodeIfPresent([UUID].self, forKey: .dependencies) ?? []
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        self.result = try c.decodeIfPresent(String.self, forKey: .result)
        self.order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

// MARK: - AgentTaskStatus

/// AgentTask 整体状态枚举
enum AgentTaskStatus: String, Codable {
    /// 待执行
    case pending
    /// 进行中
    case inProgress
    /// 已完成
    case completed
    /// 已失败
    case failed
    /// 已取消
    case cancelled
}

// MARK: - SubTaskStatus

/// SubTask 状态枚举
enum SubTaskStatus: String, Codable {
    /// 待执行
    case pending
    /// 进行中
    case inProgress
    /// 已完成
    case completed
    /// 已失败
    case failed
    /// 已跳过（依赖失败或被用户跳过）
    case skipped
}
