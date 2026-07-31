#if os(visionOS)
import SwiftUI
import AetherDesign

/// v2.0 visionOS 3D 消息气泡组件骨架。
///
/// 使用玻璃材质效果（glassMaterial），沿 Z 轴排列（由父视图 SpatialChatView 通过 offset(z:) 控制）。
///
/// 降级说明：
/// 当前为 SwiftUI 视图骨架，玻璃材质通过 .glassEffect() 实现（visionOS 26+）；
/// 后续将替换为 RealityKit Material 的 glassMaterial 3D 实现，
/// 由 ModelEntity 持有真正的 3D 材质与几何体。
struct SpatialMessageBubble: View {
    /// 消息模型（SwiftData @Model）
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if message.role == "user" {
                Spacer()
            }

            VStack(alignment: alignmentForRole, spacing: Spacing.xs) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                Text(roleLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 320, alignment: alignmentForRole)
            // 玻璃材质效果占位（glassMaterial）
            .glassEffect()
            .cornerRadius(CornerRadius.large)

            if message.role != "user" {
                Spacer()
            }
        }
    }

    /// 根据角色决定文本对齐方向
    private var alignmentForRole: Alignment {
        message.role == "user" ? .trailing : .leading
    }

    /// 角色显示标签
    private var roleLabel: String {
        switch message.role {
        case "user": return "你"
        case "assistant": return "Aether"
        case "system": return "系统"
        case "tool": return "工具"
        default: return message.role
        }
    }
}
#endif
