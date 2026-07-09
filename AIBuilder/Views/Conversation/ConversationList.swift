import SwiftUI
import SwiftData

struct ConversationList: View {
    @Bindable var conversationListVM: ConversationListVM
    let onSelect: (Conversation) -> Void
    let onCreate: () -> Void

    @State private var renamingConv: Conversation?
    @State private var newTitle = ""
    /// Day 9: 搜索关键词（空字符串表示不过滤）
    @State private var searchText = ""
    @State private var showDeleteConfirm = false
    @State private var deleteIndexSet: IndexSet?
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
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: selectedConversations.contains(conversation.id),
                                    showsCheckbox: isEditMode
                                )
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
                        }
                        .onDelete { indexSet in
                            deleteIndexSet = indexSet
                            showDeleteConfirm = true
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
                                .accessibilityHint(String(format: "删除选中的 %d 个会话", selectedConversations.count))
                                .accessibilityIdentifier("deleteSelectedConversationsButton")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(.bar)
                        }
                    }
                }
            }
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
                }
                Button("删除", role: .destructive) {
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
                Text("确定删除此对话？删除后无法恢复。")
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
}
