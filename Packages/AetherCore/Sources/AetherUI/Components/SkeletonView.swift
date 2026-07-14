import SwiftUI
import AetherDesign

/// 骨架屏占位单元：呼吸动画的圆角矩形
public struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.small)
            .fill(Color.backgroundTertiary)
            .animation(reduceMotion ? nil : AnimationTokens.skeleton, value: true)
            .accessibilityHidden(true)
    }
}

#Preview {
    SkeletonView()
        .frame(height: 16)
        .padding()
}
