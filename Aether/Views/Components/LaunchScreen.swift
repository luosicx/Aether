import SwiftUI

/// 以太开屏展示：深空背景 + 发光 A 字 + 品牌名
struct LaunchScreen: View {
    @State private var fadeIn = false

    var body: some View {
        ZStack {
            // 深空背景渐变（深空黑 → 液态玻璃）
            LinearGradient(
                colors: [Color.deepSpace, Color.liquidGlass],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 星云光晕氛围（中心向外发散）
            RadialGradient(
                colors: [
                    Color.nebulaGlow.opacity(0.25),
                    Color.aetherPurple.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.xxl) {
                Spacer()

                // 发光 A 字：渐变前景 + 紫色光晕
                Text("A")
                    .font(.aetherDisplay)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.aetherPurple, Color.electricBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.aetherPurple.opacity(0.6), radius: 20, y: 0)
                    .scaleEffect(fadeIn ? 1.0 : 0.8)
                    .opacity(fadeIn ? 1.0 : 0)

                VStack(spacing: Spacing.sm) {
                    Text("以太")
                        .font(.aetherTitle)
                        .foregroundStyle(Color.starlight)

                    Text("Aether · AI Assistant")
                        .font(.aetherBody)
                        .foregroundStyle(Color.nebulaGlow)
                }
                .opacity(fadeIn ? 1.0 : 0)
                .offset(y: fadeIn ? 0 : 10)

                Spacer()

                Text("无形，无处不在，智能")
                    .font(.aetherBody)
                    .foregroundStyle(Color.nebulaGlow.opacity(0.6))
                    .padding(.bottom, Spacing.xxl)
                    .opacity(fadeIn ? 1.0 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                fadeIn = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("以太，AI 对话助手")
    }
}

#Preview {
    LaunchScreen()
}
