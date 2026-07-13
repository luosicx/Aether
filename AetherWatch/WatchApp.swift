#if os(watchOS)
import SwiftUI
import SwiftData

/// Day 17: watchOS App 入口。配置 SwiftData ModelContainer 并展示快速对话页与健康洞察页。
///
/// - Note: 此文件仅在 watchOS target 中编译，需用户手动创建 watchOS target 后引用。
///   iOS target 不应编译此文件（通过 `#if os(watchOS)` 条件编译保护）。
@main
struct AetherWatchApp: App {
    /// SwiftData 容器，与 iOS App 共享 HealthInsight / Conversation / ChatMessage 模型。
    /// 使用 App Group 容器 URL 以便 iOS / watchOS / Widget 共享同一 SQLite store。
    let modelContainer: ModelContainer

    init() {
        do {
            // 使用 App Group 共享容器 URL，确保与 iOS 端读写同一 SwiftData store。
            // AppGroupContainer 未配置时回退到默认存储位置（开发/测试兜底）。
            let config = AppGroupContainer.makeModelConfiguration()
            modelContainer = try ModelContainer(
                for: Conversation.self, ChatMessage.self, HealthInsight.self, DocumentChunk.self, MessageFeedback.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(modelContainer)
    }
}

/// Watch 根视图：TabView 在快速对话与健康洞察之间切换。
struct WatchRootView: View {
    @State private var selectedTab: WatchTab = .quickChat

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchQuickChatView()
                .tag(WatchTab.quickChat)
                .accessibilityLabel("快速对话")
                .accessibilityHint("左右滑动切换页面")
            WatchHealthInsightView()
                .tag(WatchTab.healthInsight)
                .accessibilityLabel("健康洞察")
                .accessibilityHint("左右滑动切换页面")
        }
        .tabViewStyle(.page)
        .accessibilityIdentifier("watchRootTabView")
    }
}

/// Watch Tab 类型
enum WatchTab: Hashable {
    case quickChat
    case healthInsight
}
#endif
