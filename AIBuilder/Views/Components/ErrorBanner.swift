import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    var onRetry: (() -> Void)?
    var onSettings: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
            if let onRetry {
                Button("重试") { onRetry() }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.aetherPurple)
                    .accessibilityLabel("重试")
            }
            if let onSettings {
                Button("前往设置") { onSettings() }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.aetherPurple)
                    .accessibilityLabel("前往设置")
            }
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .frame(maxWidth: .infinity)  // 水平占满，但高度只包裹内容
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: message)
    }
}
