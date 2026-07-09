import SwiftUI

/// 工具步骤值类型快照：用于切断对 @Observable ViewModel 的观察链
struct ToolStepSnapshot: Identifiable, Equatable {
    let id: UUID
    let toolName: String
    let status: Status
    let result: String?
    /// Day 8: assistant 此轮的决策文本（Thought 段）
    let thought: String?
    /// Day 8: 工具调用的参数 JSON 字符串（Action 段）
    let arguments: String
    /// Day 8: 当前 ReAct 轮次序号（从 1 开始）
    let loopIndex: Int

    enum Status {
        case running, completed, failed
    }
}

struct StepCardView: View {
    let step: ToolStepSnapshot
    /// Day 8: Observation 段展开状态（默认折叠）
    @State private var isObservationExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部：第 N 轮 + 状态图标
            HStack(spacing: 6) {
                Text(String(format: NSLocalizedString("第 %d 轮", comment: ""), step.loopIndex))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                if step.status == .running {
                    Text("执行中…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Thought 段（assistant 决策文本，非空时显示）
            if let thought = step.thought, !thought.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thought")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Color(.tertiaryLabel))
                    Text(thought)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action 段（工具名 + 参数 JSON）
            VStack(alignment: .leading, spacing: 2) {
                Text("Action")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Color(.tertiaryLabel))
                HStack(spacing: 6) {
                    Text(step.toolName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(step.arguments)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Observation 段（result，可折叠）
            if let result = step.result, !result.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Observation")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Button {
                            if reduceMotion {
                                isObservationExpanded.toggle()
                            } else {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isObservationExpanded.toggle()
                                }
                            }
                        } label: {
                            Image(systemName: isObservationExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isObservationExpanded ? "折叠" : "展开")
                    }
                    Text(result)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(step.status == .failed ? .red : .primary)
                        .lineLimit(isObservationExpanded ? nil : 2)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(step.status == .failed ? Color.red.opacity(0.4) : Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        // Day 19: 无障碍——标注工具步骤名称与状态，提示可查看详情
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("工具步骤：%@", comment: ""), step.toolName)))
        .accessibilityValue(Text(statusText))
        .accessibilityHint("查看详情")
    }

    private var statusText: String {
        switch step.status {
        case .running: return NSLocalizedString("执行中", comment: "")
        case .completed: return NSLocalizedString("已完成", comment: "")
        case .failed: return NSLocalizedString("失败", comment: "")
        }
    }

    private var statusIcon: String {
        switch step.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}
