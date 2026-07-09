import SwiftUI

/// 统一加载状态：骨架屏 + 进度文本
struct LoadingStateView: View {
    let text: String
    var skeletonLines: Int = 3

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(0..<skeletonLines, id: \.self) { _ in
                    SkeletonView()
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, Spacing.xl)

            Text(text)
                .font(.captionAI)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview {
    LoadingStateView(text: "AI 正在思考...")
        .frame(height: 200)
}
