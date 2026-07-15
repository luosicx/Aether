import SwiftUI
import SwiftData
import AetherDesign
import AetherUI

struct ConversationList: View {
    @Bindable var conversationListVM: ConversationListVM
    let onSelect: (Conversation) -> Void
    let onCreate: () -> Void
    #if os(macOS)
    // Task 20: macOS 拖入对话时从 modelContext 查找会话
    @Environment(\.modelContext) private var modelContext
    #endif

    @State private var renamingConv: Conversation?
    @State private var newTitle = ""
    /// Day 9: 搜索关键词（空字符串表示不过滤）
    @State private var searchText = ""
    @State private var showDeleteConfirm = false
    @State private var deleteIndexSet: IndexSet?
    /// Task 23.1: 滑动删除时待确认的会话（与 deleteIndexSet 互斥使用，swipeActions 路径写入此值）
    @State private var pendingDeleteConv: Conversation?
    /// 批量多选模式
    @State private var isEditMode = false
    @State private var selectedConversations: Set<UUID> = []
    @State private var showBatchDeleteConfirm = false

    /// Day 9: 按搜索关键词过滤会话（标题包含匹配，不区分大小写）
    private var filteredConversations: [Conversation] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return conversationListVM.conversations }
        return conversationListVM.conversations.filter { $0.title.lowercased().contains(keyword) }
    }

    /// 当前过滤后的会话是否全部被选中
    private var allFilteredSelected: Bool {
        !filteredConversations.isEmpty && filteredConversations.allSatisfy { selectedConversations.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversationListVM.conversations.isEmpty {
                    EmptyStateView(
                        systemImage: "scroll",
                        title: "还没有对话",
                        message: "点击右上角新建对话开始聊天",
                        primaryButtonTitle: "新建对话",
                        primaryAction: { onCreate() }
                    )
                } else {
                    List {
                        // Day 9: 搜索框
                        Section {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("搜索会话标题…", text: $searchText)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("搜索会话")
                                    .accessibilityHint("输入关键词过滤会话标题")
                                    .accessibilityIdentifier("conversationSearchField")
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("清除搜索")
                                    .accessibilityHint("清空搜索关键词")
                                    .accessibilityIdentifier("clearSearchButton")
                                }
                            }
                        }
                        .listRowBackground(Color.clear)

                        // Day 9: 过滤后的会话列表（显式按 UUID 稳定化，避免依赖 @Model 的默认 Identifiable 行为）
                        ForEach(filteredConversations, id: \.id) { conversation in
                            Button {
                                if isEditMode {
                                    if selectedConversations.contains(conversation.id) {
                                        selectedConversations.remove(conversation.id)
                                    } else {
                                        selectedConversations.insert(conversation.id)
                                    }
                                } else {
                                    onSelect(conversation)
                                }
                            } label: {
                                #if os(macOS)
                                // Task 20: macOS 使用可拖拽的会话行
                                DraggableConversation(
                                    conversation: conversation,
                                    isSelected: selectedConversations.contains(conversation.id),
                                    showsCheckbox: isEditMode
                                )
                                #else
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: selectedConversations.contains(conversation.id),
                                    showsCheckbox: isEditMode
                                )
                                #endif
                            }
                            .contextMenu {
                                Button {
                                    renamingConv = conversation
                                    newTitle = conversation.title
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .accessibilityLabel("重命名")
                                .accessibilityHint("重命名此会话")
                                .accessibilityIdentifier("renameContextMenuButton")
                                // Day 9: 置顶 / 取消置顶（根据当前状态切换文案）
                                Button {
                                    conversationListVM.togglePin(conversation)
                                } label: {
                                    Label(
                                        conversation.isPinned ? "取消置顶" : "置顶",
                                        systemImage: conversation.isPinned ? "pin.slash" : "pin"
                                    )
                                }
                                .accessibilityLabel(conversation.isPinned ? "取消置顶" : "置顶")
                                .accessibilityHint(conversation.isPinned ? "取消置顶此会话" : "将此会话置顶")
                                .accessibilityIdentifier("togglePinContextMenuButton")
                                Button(role: .destructive) {
                                    conversationListVM.deleteConversation(conversation)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .accessibilityLabel("删除")
                                .accessibilityHint("删除此会话")
                                .accessibilityIdentifier("deleteContextMenuButton")
                            }
                            // Task 23.1: 左滑显示删除（红）+ 重命名（黄）按钮
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation(AnimationTokens.transition) {
                                        pendingDeleteConv = conversation
                                    }
                                    showDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .accessibilityLabel("删除会话")
                                .accessibilityHint("滑动删除此会话，需二次确认")
                                .accessibilityIdentifier("swipeDeleteConversationButton")
                                Button {
                                    withAnimation(AnimationTokens.transition) {
                                        renamingConv = conversation
                                        newTitle = conversation.title
                                    }
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .tint(.yellow)
                                .accessibilityLabel("重命名会话")
                                .accessibilityHint("滑动重命名此会话")
                                .accessibilityIdentifier("swipeRenameConversationButton")
                            }
                        }
                        // Task 23.3: 拖拽排序——移动会话顺序并更新 order 字段持久化
                        .onMove { source, destination in
                            withAnimation(AnimationTokens.transition) {
                                conversationListVM.reorder(from: source, to: destination)
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                    .safeAreaInset(edge: .bottom) {
                        if isEditMode {
                            HStack {
                                Button {
                                    if allFilteredSelected {
                                        // 取消全选
                                        for conv in filteredConversations {
                                            selectedConversations.remove(conv.id)
                                        }
                                    } else {
                                        // 全选
                                        for conv in filteredConversations {
                                            selectedConversations.insert(conv.id)
                                        }
                                    }
                                } label: {
                                    Label(
                                        allFilteredSelected ? "取消全选" : "全选",
                                        systemImage: allFilteredSelected ? "circle" : "checkmark.circle"
                                    )
                                    .font(.callout)
                                }
                                .accessibilityLabel(allFilteredSelected ? "取消全选" : "全选")
                                .accessibilityHint(allFilteredSelected ? "取消所有选中会话" : "选中所有过滤后的会话")
                                .accessibilityIdentifier("selectAllConversationsButton")
                                Spacer()
                                Button(role: .destructive) {
                                    if !selectedConversations.isEmpty {
                                        showBatchDeleteConfirm = true
                                    }
                                } label: {
                                    Text(String(format: NSLocalizedString("删除选中(%d)", comment: ""), selectedConversations.count))
                                        .font(.callout.weight(.medium))
                                }
                                .disabled(selectedConversations.isEmpty)
                                .accessibilityLabel("删除选中")
                                .accessibilityHint(String(format: NSLocalizedString("删除选中的 %d 个会话", comment: "批量删除按钮无障碍提示"), selectedConversations.count))
                                .accessibilityIdentifier("deleteSelectedConversationsButton")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(.bar)
                        }
                    }
                    #if os(macOS)
                    // Task 20: macOS 支持拖入对话——接收来自其他窗口的会话拖拽
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                    }
                    #endif
                }
            }
            .responsiveLayout()
            .navigationTitle("以太")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeadingCompat) {
                    if !conversationListVM.conversations.isEmpty {
                        Button {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedConversations.removeAll()
                            }
                        } label: {
                            Text(isEditMode ? "完成" : "编辑")
                        }
                        .accessibilityLabel(isEditMode ? "完成" : "编辑")
                        .accessibilityHint(isEditMode ? "退出批量编辑模式" : "进入批量编辑模式")
                        .accessibilityIdentifier("editConversationsButton")
                    }
                }
                ToolbarItem(placement: .topBarTrailingCompat) {
                    if !isEditMode {
                        Button {
                            onCreate()
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.medium)
                        }
                        .accessibilityLabel("新建对话")
                        .accessibilityHint("创建新对话")
                        .accessibilityIdentifier("newConversationButton")
                    }
                }
            }
            .alert("重命名对话", isPresented: Binding(
                get: { renamingConv != nil },
                set: { if !$0 { renamingConv = nil } }
            )) {
                TextField("新标题", text: $newTitle)
                Button("取消", role: .cancel) { renamingConv = nil }
                Button("确定") {
                    if let conv = renamingConv, !newTitle.isEmpty {
                        conversationListVM.renameConversation(conv, to: newTitle)
                    }
                    renamingConv = nil
                }
            }
            .alert("删除对话", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {
                    deleteIndexSet = nil
                    pendingDeleteConv = nil
                }
                Button("删除", role: .destructive) {
                    // Task 23.1: swipeActions 路径——直接删除 pendingDeleteConv
                    if let conv = pendingDeleteConv {
                        withAnimation(AnimationTokens.transition) {
                            conversationListVM.deleteConversation(conv)
                        }
                        pendingDeleteConv = nil
                    }
                    // 兼容路径——.onDelete 提供的 IndexSet（保留向后兼容）
                    if let indexSet = deleteIndexSet {
                        for index in indexSet {
                            guard index < filteredConversations.count else { continue }
                            let conv = filteredConversations[index]
                            conversationListVM.deleteConversation(conv)
                        }
                    }
                    deleteIndexSet = nil
                }
            } message: {
                Text("确定删除此对话？删除后无法恢复。", comment: "")
            }
            .alert("批量删除", isPresented: $showBatchDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    let toDelete = conversationListVM.conversations.filter { selectedConversations.contains($0.id) }
                    conversationListVM.deleteConversations(toDelete)
                    selectedConversations.removeAll()
                    isEditMode = false
                }
            } message: {
                Text(String(format: NSLocalizedString("确定删除选中的 %d 个对话？删除后无法恢复。", comment: ""), selectedConversations.count))
            }
        }
    }

    #if os(macOS)
    // MARK: - Task 20: macOS 拖入对话处理
    /// 处理拖入的对话——解析对话 ID 并在当前窗口切换到该会话。
    /// 拖拽载荷为会话 UUID 字符串（来自 `DraggableConversation.onDrag`）。
    /// - Parameter providers: 拖入的 NSItemProvider 数组
    /// - Returns: 是否接受拖入（始终返回 true，异步处理载荷）
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let idString = object as? String,
                  let conversationId = UUID(uuidString: idString) else { return }
            Task { @MainActor in
                // 先从已加载的列表中查找
                if let conv = conversationListVM.conversations.first(where: { $0.id == conversationId }) {
                    conversationListVM.autoTitleIfNeeded(for: conv)
                    onSelect(conv)
                    return
                }
                // 未在列表中找到时，从 modelContext 查找
                var descriptor = FetchDescriptor<Conversation>(
                    predicate: #Predicate { $0.id == conversationId }
                )
                descriptor.fetchLimit = 1
                if let conv = try? modelContext.fetch(descriptor).first {
                    conversationListVM.autoTitleIfNeeded(for: conv)
                    onSelect(conv)
                }
            }
        }
        return true
    }
    #endif
}
