import SwiftUI
import AetherDesign

/// Task 20 阶段 4: 用户干预面板。
///
/// 职责：
/// - 当 DAG 执行中出现 `failed` 节点时浮现，提供三种干预动作：
///   - **跳过**：将 failed 节点标记为 skipped，级联跳过其下游依赖
///   - **重试**：重置 failed 节点为 pending，重新执行
///   - **取消**：取消整个任务，将所有未完成节点标记为 skipped
/// - **@MainActor 串行化**：动作执行期间禁用按钮，防止用户重复触发
/// - 显示失败节点信息（标题、错误原因）
///
/// 与 DAGExecutionEngine 关系：
/// - Panel 仅负责 UI 与回调触发，不直接调用引擎
/// - 上层（AgentOrchestrator）注入回调，回调内部调用 `skipFailedNode` / `retryFailedNode` / `cancelTask`
struct InterventionPanel: View {

    /// 失败的节点
    let failedNode: SubTask

    /// 跳过失败节点回调（异步，由 AgentOrchestrator.skipFailedNode 实现）
    var onSkip: () async -> Void

    /// 重试失败节点回调（异步，由 AgentOrchestrator.retryFailedNode 实现）
    var onRetry: () async -> Void

    /// 取消整个任务回调（异步，由 AgentOrchestrator.cancelTaskIntervention 实现）
    var onCancel: () async -> Void

    /// 是否正在处理（防止并发干预）
    @State private var isProcessing: Bool = false

    /// 当前选中的动作（用于显示加载状态）
    @State private var pendingAction: Action? = nil

    /// 干预动作枚举
    enum Action: String, CaseIterable {
        case skip = "跳过"
        case retry = "重试"
        case cancel = "取消"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 头部：失败提示
            HStack(spacing: Spacing.sm) {
                // v1.2: 使用 AetherIcon.error 替换 SF Symbol
                AetherIcon.error.systemImage
                    .foregroundColor(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("节点执行失败")
                        .font(.headlineAI)
                        .foregroundColor(.textPrimary)
                    Text("请选择干预方式继续任务")
                        .font(.captionAI)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }

            Divider()

            // 失败节点信息
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("失败节点")
                    .font(.captionAI)
                    .foregroundColor(.textSecondary)
                Text(failedNode.title)
                    .font(.bodyAI)
                    .foregroundColor(.textPrimary)
                if let result = failedNode.result, !result.isEmpty {
                    Text("错误：\(result)")
                        .font(.captionAI)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }
            .padding(Spacing.md)
            .background(Color.red.opacity(0.08))
            .cornerRadius(CornerRadius.small)

            // 动作按钮
            VStack(spacing: Spacing.sm) {
                actionButton(.retry, icon: "arrow.clockwise.circle.fill", color: .electricBlue)
                actionButton(.skip, icon: "forward.circle.fill", color: .orange)
                actionButton(.cancel, icon: "xmark.octagon.fill", color: .red)
            }
        }
        .padding(Spacing.lg)
        .background(Color.backgroundSecondary)
        .cornerRadius(CornerRadius.medium)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - 动作按钮

    /// 创建干预动作按钮
    /// - Parameters:
    ///   - action: 动作类型
    ///   - icon: SF Symbol 图标名
    ///   - color: 按钮主色
    /// - Returns: 按钮视图
    @ViewBuilder
    private func actionButton(_ action: Action, icon: String, color: Color) -> some View {
        Button {
            performAction(action)
        } label: {
            HStack(spacing: Spacing.sm) {
                if pendingAction == action {
                    ProgressView()
                        .tint(color)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(color)
                }
                Text(action.rawValue)
                    .font(.bodyAI)
                    .foregroundColor(.textPrimary)
                Spacer()
                if pendingAction == action {
                    Text("处理中…")
                        .font(.captionAI)
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(color.opacity(0.08))
            .cornerRadius(CornerRadius.small)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing && pendingAction != action ? 0.5 : 1.0)
        .accessibilityLabel("\(action.rawValue)失败节点")
    }

    // MARK: - 串行化执行

    /// 串行化执行干预动作
    ///
    /// 流程：
    /// 1. 标记 isProcessing=true，pendingAction=action
    /// 2. 异步触发对应回调（await）
    /// 3. 重置状态
    ///
    /// 通过 async 回调确保引擎动作完成前按钮保持禁用，实现 @MainActor 串行化。
    /// - Parameter action: 待执行的动作
    private func performAction(_ action: Action) {
        guard !isProcessing else { return }
        isProcessing = true
        pendingAction = action

        // 异步触发回调（Task 保证在 MainActor 上执行，因为 InterventionPanel 是 SwiftUI View 隐式 @MainActor）
        Task { @MainActor in
            switch action {
            case .skip:
                await onSkip()
            case .retry:
                await onRetry()
            case .cancel:
                await onCancel()
            }
            isProcessing = false
            pendingAction = nil
        }
    }
}

// MARK: - 预览

#if DEBUG
@MainActor
struct InterventionPanelPreview: PreviewProvider {
    static var previews: some View {
        let failedNode = SubTask(title: "调用外部 API", description: "获取天气数据", order: 2)
        var node = failedNode
        node.status = .failed
        node.result = "网络请求超时（30s）"
        return InterventionPanel(
            failedNode: node,
            onSkip: { @MainActor in print("跳过") },
            onRetry: { @MainActor in print("重试") },
            onCancel: { @MainActor in print("取消") }
        )
        .padding()
        .background(Color.backgroundPrimary)
    }
}
#endif
