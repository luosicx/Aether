import SwiftUI

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(opacity(for: index))
                    .offset(y: offset(for: index))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        #if os(iOS)
        .clipShape(RoundedCornerShape(radius: 16, corners: [.topLeft, .topRight, .bottomRight]))
        #else
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 16, bottomLeading: 0, bottomTrailing: 16, topTrailing: 16)))
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI 正在输入")
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let t = (phase - Double(index) * 0.25).truncatingRemainder(dividingBy: 1.0)
        let normalized = t < 0 ? t + 1 : t
        return 0.3 + 0.7 * sin(normalized * .pi)
    }

    private func offset(for index: Int) -> CGFloat {
        let t = (phase - Double(index) * 0.25).truncatingRemainder(dividingBy: 1.0)
        let normalized = t < 0 ? t + 1 : t
        return -3 * sin(normalized * .pi)
    }
}
