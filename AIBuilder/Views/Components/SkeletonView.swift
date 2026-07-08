import SwiftUI

struct SkeletonView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .opacity(isAnimating ? 1 : 0.4)
            }
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("加载中")
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            } else {
                isAnimating = true
            }
        }
    }
}
