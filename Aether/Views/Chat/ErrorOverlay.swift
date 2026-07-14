import SwiftUI
import AetherUI

struct ErrorOverlay: View {
    let errorMessage: String?
    let onDismiss: () -> Void
    var onRetry: (() -> Void)?
    var onSettings: (() -> Void)?

    var body: some View {
        if let error = errorMessage {
            ErrorBanner(
                message: error,
                onDismiss: onDismiss,
                onRetry: onRetry,
                onSettings: onSettings
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("错误提示")
            .accessibilityValue(error)
            .accessibilityHint("点击关闭错误提示")
        } else {
            Color.clear
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
