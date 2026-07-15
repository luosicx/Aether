import SwiftUI
import SwiftData
import AetherDesign

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
    /// 子对话映射表：parentConversationID → 子对话列表，一次性加载后缓存，避免递归查询
    @State private var childrenMap: [UUID: [Conversation]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ConversationTreeNode(
                    conversation: rootConversation,
                    depth: 0,
                    isRoot: true,
                    expandedConversations: $expandedConversations,
                    onSelect: onSelect,
                    childrenMap: childrenMap
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
            // 一次性加载所有子对话映射表，避免子节点递归触发 DB 查询
            loadAllChildren()
        }
    }

    /// 一次性加载所有对话并按 parentConversationID 分组，子节点直接从映射表读取，避免 body 重算时重复 fetch
    func loadAllChildren() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let all = try? modelContext.fetch(descriptor) else { return }
        // 将 nil parentConversationID 映射到一个哨兵 UUID，确保根节点子对话也能正确分组
        childrenMap = Dictionary(grouping: all, by: { $0.parentConversationID ?? UUID() })
    }

    /// 使用 #Predicate 在数据库层过滤子对话，避免全量 fetch + 内存 filter
    /// - Parameter conversationID: 父对话 ID
    /// - Returns: 子对话列表，按 createdAt 升序排列
    func fetchChildren(of conversationID: UUID) -> [Conversation] {
        let parentID = conversationID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.parentConversationID == parentID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

/// 递归对话树节点——展示单个对话及其所有子节点
struct ConversationTreeNode: View {
    let conversation: Conversation
    let depth: Int
    let isRoot: Bool
    @Binding var expandedConversations: Set<UUID>
    let onSelect: (Conversation) -> Void
    /// 子对话映射表，从父视图传入，避免在 body 中直接触发 DB 查询
    let childrenMap: [UUID: [Conversation]]

    private var isExpanded: Bool {
        expandedConversations.contains(conversation.id)
    }

    /// 从映射表中读取当前节点的子对话，O(1) 字典查找，不再触发任何 DB 操作
    private var children: [Conversation] {
        childrenMap[conversation.id] ?? []
    }

    private var hasChildren: Bool {
        !children.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                            childrenMap: childrenMap
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
