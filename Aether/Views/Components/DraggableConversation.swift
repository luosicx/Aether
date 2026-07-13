import SwiftUI
import SwiftData

#if os(macOS)

// MARK: - Task 20: 多窗口对话 ID 环境值

/// 自定义 EnvironmentKey，用于在多窗口场景下向 RootView 传递初始对话 ID。
/// macOS 多窗口通过 `WindowGroup(for: UUID.self)` 打开新窗口时，
/// 将对话 ID 注入环境，ChatView 读取后自动切换到对应会话。
private struct ConversationIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// 当前窗口的初始对话 ID（nil 表示未指定，使用默认行为）
    var conversationID: UUID? {
        get { self[ConversationIDKey.self] }
        set { self[ConversationIDKey.self] = newValue }
    }
}

// MARK: - Task 20: 可拖拽会话行

/// 可拖拽的会话行组件（macOS only）。
///
/// 在 `ConversationRow` 之上添加 `.onDrag` 支持，
/// 拖拽时将 `conversation.id` 作为 `NSString` 提供给 `NSItemProvider`，
/// 使得其他窗口的 `ConversationList` 可通过 `.onDrop` 接收并切换到该会话。
struct DraggableConversation: View {
    let conversation: Conversation
    var isSelected: Bool = false
    var showsCheckbox: Bool = false

    var body: some View {
        ConversationRow(
            conversation: conversation,
            isSelected: isSelected,
            showsCheckbox: showsCheckbox
        )
        .onDrag {
            // 将对话 ID 转为字符串作为拖拽载荷
            let item = NSItemProvider(object: conversation.id.uuidString as NSString)
            return item
        }
    }
}

#endif
