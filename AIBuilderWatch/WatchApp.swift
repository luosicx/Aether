#if os(watchOS)
import SwiftUI
import SwiftData

/// Day 17: watchOS App 入口。配置 SwiftData ModelContainer 并展示快速对话页。
///
/// - Note: 此文件仅在 watchOS target 中编译，需用户手动创建 watchOS target 后引用。
///   iOS target 不应编译此文件（通过 `#if os(watchOS)` 条件编译保护）。
@main
struct AIBuilderWatchApp: App {
    /// SwiftData 容器，与 iOS App 共享 HealthInsight / Conversation / ChatMessage 模型
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Conversation.self, ChatMessage.self, HealthInsight.self, DocumentChunk.self, MessageFeedback.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchQuickChatView()
        }
        .modelContainer(modelContainer)
    }
}
#endif
