import SwiftUI
import AetherDesign

/// 任务列表项数据模型
struct TaskListItem: Identifiable {
    let id = UUID()
    let isCompleted: Bool
    let text: String
}

/// Markdown 任务列表渲染视图
struct TaskListView: View {
    let items: [TaskListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.bodyAI)
                        .foregroundColor(item.isCompleted ? .accentColor : .secondary)
                        .accessibilityHidden(true)

                    if let attributed = try? AttributedString(
                        markdown: item.text,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
                    ) {
                        Text(attributed)
                            .font(.bodyAI)
                            .strikethrough(item.isCompleted, color: .secondary)
                    } else {
                        Text(item.text)
                            .font(.bodyAI)
                            .strikethrough(item.isCompleted, color: .secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Task 10.3: AgentTask 进度展示

/// AgentTask 进度展示视图。
///
/// 读取 AgentTask 显示目标，展示子任务列表和执行状态，
/// 使用不同颜色标识 pending / inProgress / completed / failed。
///
/// Task 20 阶段 4: 集成 DAGVisualizationView 展示 DAG 可视化，
/// 并在出现 failed 节点时浮现 InterventionPanel 供用户干预。
struct AgentTaskProgressView: View {
    /// 展示的 AgentTask
    let task: AgentTask

    /// Task 20: 跳过失败节点回调（由 AgentOrchestrator.skipFailedNode 注入）
    var onSkipNode: ((UUID) async -> Void)? = nil
    /// Task 20: 重试失败节点回调（由 AgentOrchestrator.retryFailedNode 注入）
    var onRetryNode: ((UUID) async -> Void)? = nil
    /// Task 20: 取消整个任务回调（由 AgentOrchestrator.cancelTaskIntervention 注入）
    var onCancelTask: (() async -> Void)? = nil

    /// Task 20: 是否显示 DAG 可视化（默认 false，由上层开启）
    var showsDAGVisualization: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 目标标题
            HStack(spacing: Spacing.sm) {
                Image(systemName: taskStatusIcon(for: task.status))
                    .font(.bodyAI)
                    .foregroundColor(taskStatusColor(for: task.status))
                    .accessibilityHidden(true)
                Text(task.goal)
                    .font(.headlineAI)
                    .foregroundColor(.textPrimary)
                Spacer()
                if showsDAGVisualization && !task.subTasks.isEmpty {
                    Text("\(task.completedCount)/\(task.subTasks.count)")
                        .font(.captionAI)
                        .foregroundColor(.textSecondary)
                }
            }

            // Task 20: DAG 可视化视图（可选）
            if showsDAGVisualization && !task.subTasks.isEmpty {
                DAGVisualizationView(task: task)
            }

            // 子任务列表
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(task.subTasks) { subTask in
                    SubTaskRow(subTask: subTask)
                }
            }

            // Task 20: failed 节点干预面板（仅当存在 failed 节点且提供回调时显示）
            if task.hasFailedSubTask, let failedNode = task.subTasks.first(where: { $0.status == .failed }),
               onSkipNode != nil, onRetryNode != nil, onCancelTask != nil {
                InterventionPanel(
                    failedNode: failedNode,
                    onSkip: { await onSkipNode?(failedNode.id) },
                    onRetry: { await onRetryNode?(failedNode.id) },
                    onCancel: { await onCancelTask?() }
                )
            }
        }
        .padding(Spacing.lg)
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }

    // MARK: - 状态样式

    /// AgentTask 整体状态对应的 SF Symbol 图标名
    private func taskStatusIcon(for status: AgentTaskStatus) -> String {
        switch status {
        case .pending:
            return "circle.dashed"
        case .inProgress:
            return "gearshape.2.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "minus.circle.fill"
        }
    }

    /// AgentTask 整体状态对应的颜色
    private func taskStatusColor(for status: AgentTaskStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .electricBlue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
}

/// 单个子任务的行视图
private struct SubTaskRow: View {
    let subTask: SubTask

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // 状态图标
            Image(systemName: subStatusIcon)
                .font(.bodyAI)
                .foregroundColor(subStatusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // 标题
                Text(subTask.title)
                    .font(.subheadlineAI)
                    .foregroundColor(.textPrimary)
                    .strikethrough(subTask.status == .completed, color: .secondary)

                // 描述（非空时显示）
                if !subTask.description.isEmpty {
                    Text(subTask.description)
                        .font(.captionAI)
                        .foregroundColor(.textSecondary)
                }

                // 执行结果（已完成且有结果时显示）
                if subTask.status == .completed, let result = subTask.result, !result.isEmpty {
                    Text(result)
                        .font(.captionAI)
                        .foregroundColor(.textTertiary)
                        .lineLimit(3)
                }
            }
        }
    }

    /// 子任务状态对应的 SF Symbol 图标名
    private var subStatusIcon: String {
        switch subTask.status {
        case .pending:
            return "circle"
        case .inProgress:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .skipped:
            return "forward.circle.fill"
        }
    }

    /// 子任务状态对应的颜色
    private var subStatusColor: Color {
        switch subTask.status {
        case .pending:
            return .secondary
        case .inProgress:
            return .electricBlue
        case .completed:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        }
    }
}
