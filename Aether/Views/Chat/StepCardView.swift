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
        HStack(alignment: .top, spacing: 10) {
            // 发光时间轴：节点 + 连线（aetherPurple/nebulaGlow 带光晕）
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.aetherGradient)
                    .frame(width: 10, height: 10)
                    .shadow(color: Color.nebulaGlow.opacity(0.6), radius: 4)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.nebulaGlow.opacity(0.7), Color.aetherPurple.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2)
                    .shadow(color: Color.aetherPurple.opacity(0.35), radius: 3)
            }
            .frame(width: 10)
            .padding(.top, 14)

            // 步骤卡片内容（毛玻璃质感）
            VStack(alignment: .leading, spacing: 8) {
                // 顶部：第 N 轮 + 状态图标
                HStack(spacing: 6) {
                    Text(String(format: NSLocalizedString("第 %d 轮", comment: ""), step.loopIndex))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Color.starlight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.aetherGradient, in: Capsule())
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .shadow(color: statusColor.opacity(0.4), radius: 3)
                    if step.status == .running {
                        Text("执行中…")
                            .font(.caption2)
                            .foregroundColor(Color.duskGray)
                    }
                    Spacer()
                }

                // Thought 段（assistant 决策文本，非空时显示）
                if let thought = step.thought, !thought.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thought")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(Color.duskGray)
                        Text(thought)
                            .font(.caption)
                            .foregroundColor(Color.starlight)
                    }
                }

                // Action 段（工具名 + 参数 JSON）
                VStack(alignment: .leading, spacing: 2) {
                    Text("Action")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Color.duskGray)
                    HStack(spacing: 6) {
                        Text(step.toolName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.starlight)
                        Text(step.arguments)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Color.duskGray)
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
                                .foregroundColor(Color.duskGray)
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
                                    .foregroundColor(Color.nebulaGlow)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isObservationExpanded ? "折叠" : "展开")
                        }
                        Text(result)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(step.status == .failed ? .red : Color.starlight)
                            .lineLimit(isObservationExpanded ? nil : 2)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // 毛玻璃基底：ultraThinMaterial + liquidGlass 叠加；失败态叠加红色微染
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                        .fill(Color.liquidGlass.opacity(0.45))
                    if step.status == .failed {
                        RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .stroke(Color.aetherPurple.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: Color.aetherPurple.opacity(0.1), radius: 8, y: 3)
        }
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
