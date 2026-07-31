#if os(visionOS)
import SwiftUI
import RealityKit
import AetherDesign

/// v2.0 visionOS 专属 3D 对话界面骨架。
///
/// 接入已有的 ChatViewModel，使用 RealityView 作为 3D 容器。
///
/// 降级说明：
/// 当前为骨架实现，消息气泡以 SwiftUI 视图沿 Z 轴（depth）排列。
/// RealityView 容器已就位但未渲染真正的 3D Entity 树，
/// 实际 3D 渲染（RealityKit Mesh / Material / Animation）待后续深度集成。
/// 后续将替换 RealityView 内部 content 为 AnchorEntity + ModelEntity 构建的 3D 消息气泡。
struct SpatialChatView: View {
    /// 接入已有的 ChatViewModel（@Observable + @MainActor）
    @Bindable var viewModel: ChatViewModel

    /// Z 轴每条消息的深度间距（米），消息沿 depth 排列
    private let depthSpacing: CGFloat = 0.15

    /// 降级标识：当前为骨架，未接入 RealityKit 3D 渲染
    static let isSkeleton = true

    var body: some View {
        RealityView { content in
            // 降级说明：RealityView 容器已就位，当前不渲染 3D Entity。
            // 后续在此构建 RealityKit AnchorEntity + ModelEntity 实现 3D 消息气泡。
            _ = content
        }
        .frame(width: 800, height: 600)
        .overlay(alignment: .center) {
            spatialMessageStack
        }
        // 简单的捏合手势占位（SpatialTapGesture），后续接入消息选择与聚焦
        .gesture(
            SpatialTapGesture()
                .onEnded { _ in
                    // 占位：空间点击/捏合手势回调，待接入消息选择逻辑
                    viewModel.feedbackToast = "空间点击已捕获（骨架）"
                }
        )
    }

    /// 消息列表沿 Z 轴 depth 排列（降级实现：SwiftUI ZStack + offset(z:)）
    /// 每条消息沿 Z 轴向后偏移 depthSpacing，形成深度层次
    private var spatialMessageStack: some View {
        ZStack {
            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                SpatialMessageBubble(message: message)
                    .zIndex(Double(index))
                    .offset(z: depthSpacing * CGFloat(index))
            }
        }
    }
}
#endif
