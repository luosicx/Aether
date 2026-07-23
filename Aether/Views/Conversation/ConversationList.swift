import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AetherDesign
import AetherUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    /// Task 15: 导出目标（驱动单个 fileExporter），nil 表示未导出
    @State private var exportTarget: ExportTarget?
    /// Task 15: PDF 生成中（异步），避免重复触发
    @State private var isGeneratingPDF = false
    /// Task 15: 分享链接 sheet
    @State private var showShareLinkSheet = false
    @State private var shareLinkConversation: Conversation?

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

    /// Task 15: fileExporter 使用的导出文档（依据 exportTarget 计算）
    private var exportDocument: ConversationExportDocument? {
        guard let target = exportTarget else { return nil }
        switch target {
        case .markdown(_, let text): return ConversationExportDocument(text: text)
        case .pdf(_, let data): return ConversationExportDocument(pdf: data)
        }
    }

    /// Task 15: fileExporter 使用的内容类型
    private var exportContentType: UTType {
        if case .pdf = exportTarget { return .pdf }
        return .plainText
    }

    /// Task 15: fileExporter 默认文件名（使用会话标题）
    private var exportDefaultFilename: String? {
        switch exportTarget {
        case .markdown(let conv, _), .pdf(let conv, _): return conv.title
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversationListVM.conversations.isEmpty {
                    // Task 17：使用 AetherIcons.bubble 兜底 SF Symbol
                    EmptyStateView(
                        systemImage: AetherIcon.bubble.fallbackSystemName,
                        title: "开始新对话",
                        message: "点击右上角 + 按钮创建新会话",
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
                                // Task 15: 导出子菜单（Markdown / PDF / 分享链接）
                                Divider()
                                Menu {
                                    Button {
                                        exportAsMarkdown(conversation)
                                    } label: {
                                        Label("导出为 Markdown", systemImage: "doc.richtext")
                                    }
                                    .accessibilityLabel("导出为 Markdown")
                                    .accessibilityHint("将此会话导出为 Markdown 文件")
                                    .accessibilityIdentifier("exportMarkdownContextMenuButton")
                                    Button {
                                        exportAsPDF(conversation)
                                    } label: {
                                        Label("导出为 PDF", systemImage: "doc.pdf")
                                    }
                                    .disabled(isGeneratingPDF)
                                    .accessibilityLabel("导出为 PDF")
                                    .accessibilityHint("将此会话导出为 PDF 文件")
                                    .accessibilityIdentifier("exportPDFContextMenuButton")
                                    Button {
                                        shareLinkConversation = conversation
                                        showShareLinkSheet = true
                                    } label: {
                                        Label("分享链接", systemImage: "link")
                                    }
                                    .accessibilityLabel("分享链接")
                                    .accessibilityHint("生成此会话的 DeepLink 分享链接")
                                    .accessibilityIdentifier("shareLinkContextMenuButton")
                                } label: {
                                    Label("导出", systemImage: "square.and.arrow.up")
                                }
                                .accessibilityLabel("导出")
                                .accessibilityHint("导出或分享此会话")
                                .accessibilityIdentifier("exportContextMenuMenu")
                                Divider()
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
            // v1.1 Phase D: 动态星空背景叠加
            .background(StarfieldBackgroundView().opacity(0.4).allowsHitTesting(false))
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
            // Task 15: 导出文件保存面板（Markdown / PDF 共用单个 fileExporter）
            .fileExporter(
                isPresented: Binding(
                    get: { exportTarget != nil },
                    set: { presented in if !presented { exportTarget = nil } }
                ),
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportDefaultFilename
            ) { result in
                if case .failure = result {
                    exportTarget = nil
                }
            }
            // Task 15: 分享链接 sheet
            .sheet(isPresented: $showShareLinkSheet) {
                if let conv = shareLinkConversation {
                    ShareLinkSheet(conversation: conv)
                }
            }
        }
    }

    // MARK: - Task 15: 导出动作
    /// 导出为 Markdown：同步生成后触发 fileExporter
    private func exportAsMarkdown(_ conversation: Conversation) {
        let exporter = ConversationExporter()
        let text = exporter.exportAsMarkdown(conversation: conversation)
        exportTarget = .markdown(conversation, text)
    }

    /// 导出为 PDF：异步生成 PDF Data，完成后触发 fileExporter
    private func exportAsPDF(_ conversation: Conversation) {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        let exporter = ConversationExporter()
        Task {
            let data = await exporter.exportAsPDF(conversation: conversation)
            isGeneratingPDF = false
            if let data = data {
                exportTarget = .pdf(conversation, data)
            }
        }
    }

    /// Task 15: 导出目标枚举，驱动 fileExporter 的文档与内容类型
    private enum ExportTarget {
        case markdown(Conversation, String)
        case pdf(Conversation, Data)
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

// MARK: - Task 15: 分享链接 Sheet
/// 展示会话 DeepLink，支持系统分享与拷贝到剪贴板
private struct ShareLinkSheet: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    private var shareURL: URL? {
        ConversationExporter().exportAsShareLink(conversation: conversation)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("对话分享链接")
                    .font(.headline)
                if let url = shareURL {
                    Text(url.absoluteString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("分享链接地址")
                        .accessibilityValue(url.absoluteString)
                    ShareLink(item: url) {
                        Label("分享…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("分享链接")
                    .accessibilityHint("通过系统分享面板分享此链接")
                    Button {
                        copyToClipboard(url.absoluteString)
                    } label: {
                        Label("拷贝链接", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("拷贝链接")
                    .accessibilityHint("将链接复制到剪贴板")
                } else {
                    Text("无法生成分享链接")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("分享链接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityLabel("关闭")
                }
            }
        }
    }

    /// 跨平台拷贝文本到系统剪贴板
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Task 15: 导出文件 Document
/// 支持 Markdown 纯文本与 PDF 数据的 FileDocument，供 fileExporter 保存
struct ConversationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .pdf] }

    private let textContent: String?
    private let pdfData: Data?

    init(text: String) {
        textContent = text
        pdfData = nil
    }
    init(pdf: Data) {
        textContent = nil
        pdfData = pdf
    }
    init(configuration: ReadConfiguration) throws {
        if configuration.contentType == .pdf, let data = configuration.file.regularFileContents {
            pdfData = data
            textContent = nil
        } else {
            pdfData = nil
            textContent = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let pdf = pdfData {
            return FileWrapper(regularFileWithContents: pdf)
        }
        return FileWrapper(regularFileWithContents: Data((textContent ?? "").utf8))
    }
}
