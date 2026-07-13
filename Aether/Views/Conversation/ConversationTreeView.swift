import SwiftUI
import SwiftData

/// Task 21: 对话树视图——递归展示对话分支与版本关系。
/// 以根对话为起点，按 parentConversationID 链展示所有子对话，
/// 使用缩进和连线标识父子层级，点击节点可切换到对应对话。
struct ConversationTreeView: View {
    /// 根对话（树的起点）
    let rootConversation: Conversation
    /// 点击对话节点时的回调
    let onSelect: (Conversation) -> Void

    @Environment(\.modelContext) private var modelContext
    /// 当前展开的对话节点集合
    @State private var expandedConversations: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ConversationTreeNode(
                    conversation: rootConversation,
                    depth: 0,
                    isRoot: true,
                    expandedConversations: $expandedConversations,
                    onSelect: onSelect,
                    fetchChildren: fetchChildren
                )
            }
            .padding(.vertical, Spacing.md)
        }
        .navigationTitle("对话版本树")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            // 默认展开根节点
            expandedConversations.insert(rootConversation.id)
        }
    }

    /// 获取指定对话的所有直接子对话（parentConversationID 匹配）
    /// - Parameter conversationID: 父对话 ID
    /// - Returns: 子对话列表，按 createdAt 升序排列
    func fetchChildren(of conversationID: UUID) -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        return all.filter { $0.parentConversationID == conversationID }
    }
}

/// 递归对话树节点——展示单个对话及其所有子节点
struct ConversationTreeNode: View {
    let conversation: Conversation
    let depth: Int
    let isRoot: Bool
    @Binding var expandedConversations: Set<UUID>
    let onSelect: (Conversation) -> Void
    let fetchChildren: (UUID) -> [Conversation]

    private var isExpanded: Bool {
        expandedConversations.contains(conversation.id)
    }

    var body: some View {
        // 缓存子节点查询结果，避免在 body 中重复触发 DB fetch
        // 原先 children/hasChildren 计算属性每次访问都会全表查询，body 重算时被多次访问
        let children = fetchChildren(conversation.id)
        let hasChildren = !children.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            nodeRow(hasChildren: hasChildren)
            if isExpanded && hasChildren {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        ConversationTreeNode(
                            conversation: child,
                            depth: depth + 1,
                            isRoot: false,
                            expandedConversations: $expandedConversations,
                            onSelect: onSelect,
                            fetchChildren: fetchChildren
                        )
                    }
                }
                .padding(.leading, 24)
                .overlay(alignment: .leading) {
                    // 竖向连线
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1)
                        .padding(.leading, 11)
                }
            }
        }
    }

    /// 单个对话节点行
    private func nodeRow(hasChildren: Bool) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            HStack(spacing: Spacing.sm) {
                // 展开/收起按钮
                if hasChildren {
                    Button {
                        toggleExpansion()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.captionAI)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    // 无子节点时显示圆点占位
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(width: 16)
                }

                // 对话图标
                Image(systemName: isRoot ? "bubble.left.and.bubble.right.fill" : "arrow.triangle.branch")
                    .font(.captionAI)
                    .foregroundStyle(isRoot ? Color.aetherPurple : Color.electricBlue)

                // 对话标题
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.bodyAI)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if !isRoot {
                        Text(String(format: "分叉于 %@", formattedDate(conversation.createdAt)))
                            .font(.captionAI)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 消息数标签
                if !conversation.messages.isEmpty {
                    Text("\(conversation.messages.count)")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(isRoot ? Color.aetherPurple.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("对话节点：\(conversation.title)")
        .accessibilityHint("点击切换到该对话")
    }

    private func toggleExpansion() {
        if isExpanded {
            expandedConversations.remove(conversation.id)
        } else {
            expandedConversations.insert(conversation.id)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
