import SwiftUI

struct ErrorOverlay: View {
    let errorMessage: String?
    let onDismiss: () -> Void

    var body: some View {
        if let error = errorMessage {
            ErrorBanner(message: error, onDismiss: onDismiss)
        } else {
            Color.clear
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
        }
    }
}
