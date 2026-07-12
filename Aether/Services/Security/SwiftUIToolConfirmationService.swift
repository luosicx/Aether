import SwiftUI

/// SwiftUI 实现的用户确认服务。
///
/// 通过 `pendingRequest` 驱动 alert 弹窗，支持“允许一次”“始终允许”“拒绝”三种操作。
/// 工具执行代码可 `await requestConfirmation(...)` 挂起，直到用户做出选择。
@MainActor
final class SwiftUIToolConfirmationService: ToolConfirmationService, ObservableObject {
    /// 当前待确认的弹窗请求。
    @Published var pendingRequest: PendingRequest?

    func requestConfirmation(toolName: String, summary: String) async -> ToolConfirmationDecision {
        await withCheckedContinuation { continuation in
            let request = PendingRequest(
                toolName: toolName,
                summary: summary,
                continuation: continuation
            )
            pendingRequest = request
        }
    }

    /// 完成当前待处理请求并返回用户决定。
    ///
    /// - Parameter decision: 用户在弹窗上的选择。
    func complete(decision: ToolConfirmationDecision) {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        request.continuation.resume(returning: decision)
    }

    /// 取消当前弹窗（视为拒绝）。
    func cancel() {
        complete(decision: .deny)
    }

    /// 待确认请求的内部模型。
    struct PendingRequest: Identifiable {
        let id = UUID()
        let toolName: String
        let summary: String
        let continuation: CheckedContinuation<ToolConfirmationDecision, Never>
    }
}

// MARK: - View 扩展

extension View {
    /// 在视图上附加工具执行确认弹窗。
    ///
    /// 用法：
    /// ```swift
    /// ContentView()
    ///     .toolConfirmationAlert(service: confirmationService)
    /// ```
    func toolConfirmationAlert(service: SwiftUIToolConfirmationService) -> some View {
        modifier(ToolConfirmationAlertModifier(service: service))
    }
}

/// 呈现工具执行确认弹窗的 `ViewModifier`。
struct ToolConfirmationAlertModifier: ViewModifier {
    @StateObject var service: SwiftUIToolConfirmationService

    private var isPresented: Binding<Bool> {
        Binding(
            get: { service.pendingRequest != nil },
            set: { newValue in
                if !newValue {
                    service.cancel()
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "确认执行工具",
                isPresented: isPresented,
                presenting: service.pendingRequest
            ) { request in
                Button("允许一次") {
                    service.complete(decision: .allowOnce)
                }
                Button("始终允许") {
                    service.complete(decision: .alwaysAllow)
                }
                Button("拒绝", role: .cancel) {
                    service.complete(decision: .deny)
                }
            } message: { request in
                Text("[\(request.toolName)]\n\(request.summary)")
            }
    }
}
