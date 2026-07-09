import SwiftUI

/// 灵枢品牌 Splash 动画：开屏展示 1.2 秒后淡出
struct BrandSplash: View {
    @Binding var isVisible: Bool
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            if isVisible {
                LaunchScreen()
                    .opacity(fadeOut ? 0 : 1)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                fadeOut = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                isVisible = false
                            }
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(AnimationTokens.transition, value: isVisible)
    }
}
