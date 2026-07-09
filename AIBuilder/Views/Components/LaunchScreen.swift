import SwiftUI

/// 灵枢开屏展示：宣纸背景 + 朱砂印章 + 品牌名
struct LaunchScreen: View {
    @State private var fadeIn = false

    var body: some View {
        ZStack {
            // 宣纸背景
            Color.ricePaper
                .ignoresSafeArea()

            VStack(spacing: Spacing.xxl) {
                Spacer()

                // 朱砂印章
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(Color.vermillion)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.vermillion.opacity(0.3), radius: 10, y: 4)

                    Text("灵")
                        .font(.custom("Kaiti SC", size: 56))
                        .foregroundStyle(Color.ricePaper)
                }
                .scaleEffect(fadeIn ? 1.0 : 0.8)
                .opacity(fadeIn ? 1.0 : 0)

                VStack(spacing: Spacing.sm) {
                    Text("灵枢")
                        .font(.brandTitle)
                        .foregroundStyle(Color.inkBlack)

                    Text("LingShu · AI 对话助手")
                        .font(.brandDecorative)
                        .foregroundStyle(Color.inkGray)
                }
                .opacity(fadeIn ? 1.0 : 0)
                .offset(y: fadeIn ? 0 : 10)

                Spacer()

                Text("古之智者，枢机通灵")
                    .font(.brandDecorative)
                    .foregroundStyle(Color.inkGray.opacity(0.6))
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
        .accessibilityLabel("灵枢，AI 对话助手")
    }
}

#Preview {
    LaunchScreen()
}
