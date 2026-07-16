import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

/// Task 5.5: 最近会话 Widget。
/// 支持 Medium 尺寸，显示最近 3 条会话标题，点击 deeplink（aether://conversation/<uuid>）进入对应会话。
struct RecentConversationsWidget: Widget {
    let kind: String = "RecentConversationsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: RecentConversationsTimelineProvider()
        ) { entry in
            RecentConversationsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(NSLocalizedString("最近会话", comment: "Widget 名称：最近会话"))
        .description(NSLocalizedString("查看最近 3 条对话，点击进入", comment: "Widget 描述：最近会话"))
        .supportedFamilies([.systemMedium])
    }
}

/// 最近会话 Widget 的时间线条目
struct RecentConversationsEntry: TimelineEntry {
    let date: Date
    /// 最近 3 条会话（id + title）
    let conversations: [ConversationSummary]
}

/// 会话摘要数据（用于 Widget 显示）
struct ConversationSummary: Identifiable, Hashable {
    let id: UUID
    let title: String
    let lastMessage: String?
}

/// 最近会话 Widget 的 TimelineProvider。
/// 通过 SwiftData ModelContainer 读取 App Group 共享 store 中最近的 Conversation。
struct RecentConversationsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentConversationsEntry {
        RecentConversationsEntry(date: Date(), conversations: [
            ConversationSummary(id: UUID(), title: NSLocalizedString("新对话", comment: "Widget 占位会话 1"), lastMessage: nil),
            ConversationSummary(id: UUID(), title: NSLocalizedString("关于 Swift 的讨论", comment: "Widget 占位会话 2"), lastMessage: nil),
            ConversationSummary(id: UUID(), title: NSLocalizedString("健康建议", comment: "Widget 占位会话 3"), lastMessage: nil)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentConversationsEntry) -> Void) {
        let entry = fetchRecentConversations() ?? placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentConversationsEntry>) -> Void) {
        let entry = fetchRecentConversations() ?? RecentConversationsEntry(date: Date(), conversations: [])
        // 每 30 分钟刷新一次
        let nextRefresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// 从共享 SwiftData store 读取最近 3 条会话
    private func fetchRecentConversations() -> RecentConversationsEntry? {
        do {
            let config = AppGroupContainer.makeModelConfiguration()
            let container = try ModelContainer(
                for: Conversation.self,
                configurations: config
            )
            let context = ModelContext(container)
            // 排序：isPinned > createdAt（isPinned 为 Bool，无法用 Foundation.SortDescriptor，
            // 改为先按 createdAt 倒序获取，再在内存中按 isPinned > createdAt 排序）
            var descriptor = FetchDescriptor<Conversation>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 20
            let conversations = try context.fetch(descriptor)
            let sorted = conversations.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.createdAt > rhs.createdAt
            }
            let summaries = sorted.prefix(3).map { conv in
                ConversationSummary(
                    id: conv.id,
                    title: conv.title,
                    lastMessage: conv.messages.last?.content
                )
            }
            return RecentConversationsEntry(date: Date(), conversations: Array(summaries))
        } catch {
            return nil
        }
    }
}

/// 最近会话 Widget 视图
struct RecentConversationsWidgetView: View {
    let entry: RecentConversationsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(NSLocalizedString("最近会话", comment: "Widget 标题"))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            if entry.conversations.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "plus.bubble")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("暂无会话", comment: "Widget 暂无会话"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.conversations) { conv in
                    Link(destination: conversationURL(for: conv.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if let last = conv.lastMessage {
                                Text(last)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }

    /// 构造 deeplink URL：aether://conversation/<uuid>
    private func conversationURL(for id: UUID) -> URL {
        URL(string: "aether://conversation/\(id.uuidString)") ?? URL(string: "aether://conversation")!
    }
}
