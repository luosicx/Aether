import SwiftUI
import SwiftData
import AetherFoundation
import AetherUI
import AetherDesign

struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var modelContext
    let provider: ModelProvider
    @State private var vm: KnowledgeBaseVM
    @State private var showPicker = false
    @Environment(\.dismiss) private var dismiss
    // iPad/macOS 双栏:size class 判断
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // 双栏:当前选中的文档(用于右侧分块预览)
    @State private var selectedDocument: KnowledgeBaseVM.DocumentRow?

    init(provider: ModelProvider = .deepseek) {
        self.provider = provider
        _vm = State(initialValue: KnowledgeBaseVM(provider: provider))
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPickerView { url in
                Task { await vm.importDocument(url: url, modelContext: modelContext) }
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .overlay {
            if vm.isImporting {
                ProgressView("索引中…")
                    .padding(20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear { vm.load(modelContext: modelContext) }
    }

    // MARK: - Compact (iPhone)

    @ViewBuilder
    private var compactLayout: some View {
        NavigationStack {
            Group {
                if vm.documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            .navigationTitle("知识库")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: {
                        Image(systemName: "plus").fontWeight(.medium)
                    }
                    .accessibilityLabel("导入文档")
                    .accessibilityHint("从文件选择 PDF 或文本文档导入知识库")
                    .accessibilityIdentifier("importDocumentButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("完成")
                        .accessibilityHint("关闭知识库")
                        .accessibilityIdentifier("knowledgeBaseDoneButton")
                }
            }
            #endif
        }
    }

    // MARK: - Regular (iPad / macOS)

    @ViewBuilder
    private var regularLayout: some View {
        NavigationSplitView {
            Group {
                if vm.documents.isEmpty {
                    emptyState
                } else {
                    documentListForSplit
                }
            }
            .navigationTitle("知识库")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPicker = true } label: {
                        Image(systemName: "plus").fontWeight(.medium)
                    }
                    .accessibilityLabel("导入文档")
                    .accessibilityHint("从文件选择 PDF 或文本文档导入知识库")
                    .accessibilityIdentifier("importDocumentButton")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("完成")
                        .accessibilityHint("关闭知识库")
                        .accessibilityIdentifier("knowledgeBaseDoneButton")
                }
            }
        } detail: {
            if let doc = selectedDocument, vm.documents.contains(doc) {
                chunkPreview(for: doc)
            } else {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: "选择一个文档",
                    message: "从左侧列表选择一个文档查看详情"
                )
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        // Task 17：使用 AetherIcons.knowledge 兜底 SF Symbol
        EmptyStateView(
            systemImage: AetherIcon.knowledge.fallbackSystemName,
            title: "知识库为空",
            message: "导入 PDF 或文本文件来扩充知识库",
            primaryButtonTitle: "导入文档",
            primaryAction: { showPicker = true }
        )
    }

    // MARK: - 文档列表 (Compact)

    private var documentList: some View {
        List {
            ForEach(vm.documents) { doc in
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.source)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(String(format: NSLocalizedString("%d 个片段", comment: ""), doc.chunkCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(doc.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(doc.source)
                .accessibilityHint("查看文档分块")
                .accessibilityIdentifier("documentRow_\(doc.id)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        vm.deleteDocument(source: doc.source, modelContext: modelContext)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .accessibilityLabel("删除")
                    .accessibilityHint("从知识库删除此文档")
                    .accessibilityIdentifier("deleteDocumentButton")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - 文档列表 (Regular / Split)

    private var documentListForSplit: some View {
        List(selection: $selectedDocument) {
            ForEach(vm.documents) { doc in
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.source)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(String(format: NSLocalizedString("%d 个片段", comment: ""), doc.chunkCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(doc.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tag(doc)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(doc.source)
                .accessibilityHint("查看文档分块")
                .accessibilityIdentifier("documentRow_\(doc.id)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if selectedDocument == doc {
                            selectedDocument = nil
                        }
                        vm.deleteDocument(source: doc.source, modelContext: modelContext)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .accessibilityLabel("删除")
                    .accessibilityHint("从知识库删除此文档")
                    .accessibilityIdentifier("deleteDocumentButton")
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - 分块预览 (Regular / Detail)

    private func chunkPreview(for doc: KnowledgeBaseVM.DocumentRow) -> some View {
        ChunkPreviewList(source: doc.source, doc: doc)
    }
}

/// 文档分块预览子视图，使用 @Query 按 source 过滤，避免在 body 中直接 fetch
private struct ChunkPreviewList: View {
    let source: String
    let doc: KnowledgeBaseVM.DocumentRow

    @Query private var chunks: [DocumentChunk]

    init(source: String, doc: KnowledgeBaseVM.DocumentRow) {
        self.source = source
        self.doc = doc
        // 使用 @Query 的 predicate 参数，而非在 body 中执行 modelContext.fetch()
        _chunks = Query(
            filter: #Predicate<DocumentChunk> { $0.source == source },
            sort: \.chunkIndex
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.source)
                        .font(.title2.bold())
                    HStack(spacing: 8) {
                        Text(String(format: NSLocalizedString("%d 个片段", comment: ""), doc.chunkCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(doc.createdAt, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(chunks) { chunk in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(format: NSLocalizedString("片段 %d", comment: ""), chunk.chunkIndex + 1))
                                .font(.headline)
                            Spacer()
                            Text(chunk.weight < 1.0 ? String(format: NSLocalizedString("权重 %.1f", comment: ""), chunk.weight) : "")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(chunk.content)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle(doc.source)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
