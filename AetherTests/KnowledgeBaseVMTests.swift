import XCTest
import SwiftData
@testable import Aether

/// KnowledgeBaseVM 单元测试
@MainActor
final class KnowledgeBaseVMTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var vm: KnowledgeBaseVM!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, UserPreference.self, DocumentChunk.self,
            configurations: config
        )
        context = ModelContext(container)
        vm = KnowledgeBaseVM()
    }

    override func tearDownWithError() throws {
        vm = nil
        context = nil
        container = nil
    }

    /// Helper：为指定 source 插入 N 个 chunk，createdAt 从 baseTime 起递增
    private func insertChunks(source: String, count: Int, baseTime: TimeInterval) {
        for i in 0..<count {
            let chunk = DocumentChunk(
                content: "chunk \(i) of \(source)",
                embedding: [Float(i)],
                source: source,
                chunkIndex: i
            )
            chunk.createdAt = Date(timeIntervalSince1970: baseTime + Double(i))
            context.insert(chunk)
        }
        try? context.save()
    }

    /// load 聚合 chunkCount 并按 createdAt 降序
    func testLoadAggregatesChunkCountAndSorts() {
        // Source A：3 chunks，createdAt 较旧（1000-1002）
        insertChunks(source: "A.pdf", count: 3, baseTime: 1000)
        // Source B：2 chunks，createdAt 较新（2000-2001）
        insertChunks(source: "B.pdf", count: 2, baseTime: 2000)

        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.count, 2, "应聚合为 2 个文档")

        // 按 createdAt 降序：B（max=2001）在前，A（max=1002）在后
        XCTAssertEqual(vm.documents.map(\.source), ["B.pdf", "A.pdf"],
                       "应按 createdAt 降序排序")

        // chunkCount 正确
        let docB = vm.documents.first { $0.source == "B.pdf" }
        XCTAssertEqual(docB?.chunkCount, 2, "B.pdf 应聚合 2 chunks")
        let docA = vm.documents.first { $0.source == "A.pdf" }
        XCTAssertEqual(docA?.chunkCount, 3, "A.pdf 应聚合 3 chunks")

        // createdAt 字段应取该 source 下所有 chunk 的最大值
        XCTAssertEqual(docB?.createdAt, Date(timeIntervalSince1970: 2001),
                       "B 的 createdAt 应为其所有 chunk 的最大 createdAt")
        XCTAssertEqual(docA?.createdAt, Date(timeIntervalSince1970: 1002),
                       "A 的 createdAt 应为其所有 chunk 的最大 createdAt")
    }

    /// deleteDocument(source:) 删除指定 source 的所有 chunks
    func testDeleteDocumentRemovesAllChunks() throws {
        insertChunks(source: "A.pdf", count: 3, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 2, baseTime: 2000)

        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 2)

        // 删除 source A
        vm.deleteDocument(source: "A.pdf", modelContext: context)

        // vm.documents 应只剩 B
        XCTAssertEqual(vm.documents.count, 1, "删除 A 后应只剩 1 个文档")
        XCTAssertEqual(vm.documents.first?.source, "B.pdf")

        // context 中 A 的所有 chunks 应被删除
        let allChunks = try context.fetch(FetchDescriptor<DocumentChunk>())
        let remainingA = allChunks.filter { $0.source == "A.pdf" }
        XCTAssertEqual(remainingA.count, 0, "context 中 A 的所有 chunks 应被删除")

        // B 的 chunks 应保留
        let remainingB = allChunks.filter { $0.source == "B.pdf" }
        XCTAssertEqual(remainingB.count, 2, "B 的 chunks 应保留")
    }

    /// importDocument 在 DeepSeek 无 Qwen Key 时实时解析失败，显示友好错误（不发送 404 请求）
    func testImportDocumentDeepSeekNoQwenKeyShowsFriendlyError() async {
        // KnowledgeBaseVM 默认 provider = .deepseek，测试环境中 Keychain 无 Qwen Key
        // resolveEmbedding 应返回 nil，importDocument 应设置友好错误
        let vm = KnowledgeBaseVM(provider: .deepseek)

        // 创建临时文件
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).txt")
        try? "这是一段测试文本".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "DeepSeek 无 Qwen Key 时应设置错误消息")
        XCTAssertTrue(
            vm.errorMessage?.contains("DeepSeek 不支持知识库嵌入") == true,
            "错误消息应包含'DeepSeek 不支持知识库嵌入'，实际：\(vm.errorMessage ?? "nil")"
        )
        XCTAssertFalse(vm.isImporting, "应未进入导入状态")
    }

    // MARK: - load 边界情况

    /// load 在空 context 上应返回空文档列表
    func testLoadOnEmptyContextReturnsEmptyDocuments() {
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 0, "空 context 时 documents 应为空")
        XCTAssertTrue(vm.documents.isEmpty, "空 context 时 documents 应为空数组")
    }

    /// load 单个 source 单个 chunk 时应聚合为 1 个文档
    func testLoadSingleSourceSingleChunk() {
        insertChunks(source: "only.pdf", count: 1, baseTime: 5000)

        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.count, 1, "单个 source 应聚合为 1 个文档")
        XCTAssertEqual(vm.documents.first?.source, "only.pdf")
        XCTAssertEqual(vm.documents.first?.chunkCount, 1, "chunkCount 应为 1")
    }

    /// load 多次调用应幂等（不累积重复行）
    func testLoadIsIdempotent() {
        insertChunks(source: "A.pdf", count: 2, baseTime: 1000)

        vm.load(modelContext: context)
        let countAfterFirstLoad = vm.documents.count

        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.count, countAfterFirstLoad, "多次 load 不应累积重复行")
        XCTAssertEqual(vm.documents.count, 1, "应始终为 1 个文档")
    }

    /// load 后插入新 chunk 再 load，应反映新增的 chunk
    func testLoadReflectsNewChunksAfterReload() {
        insertChunks(source: "A.pdf", count: 1, baseTime: 1000)
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.first?.chunkCount, 1, "初次 load chunkCount 应为 1")

        // 再插入同 source 的 chunk
        insertChunks(source: "A.pdf", count: 2, baseTime: 2000)
        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.count, 1, "仍为 1 个文档")
        XCTAssertEqual(vm.documents.first?.chunkCount, 3, "重新 load 后 chunkCount 应为 3")
    }

    // MARK: - deleteDocument 边界情况

    /// deleteDocument 删除不存在的 source 应为 no-op（不修改 documents、不抛错）
    func testDeleteNonExistentSourceIsNoOp() {
        insertChunks(source: "A.pdf", count: 2, baseTime: 1000)
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 1)

        // 删除不存在的 source
        vm.deleteDocument(source: "nonexistent.pdf", modelContext: context)

        XCTAssertEqual(vm.documents.count, 1, "删除不存在的 source 后 documents 应不变")
        XCTAssertEqual(vm.documents.first?.source, "A.pdf", "剩余文档应为 A.pdf")
    }

    /// deleteDocument 在空 documents 上调用应为 no-op
    func testDeleteOnEmptyDocumentsIsNoOp() {
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 0)

        vm.deleteDocument(source: "anything.pdf", modelContext: context)

        XCTAssertEqual(vm.documents.count, 0, "空 documents 上删除应保持为空")
    }

    /// deleteDocument 删除全部 source 后 documents 应为空
    func testDeleteAllSourcesResultsInEmptyDocuments() {
        insertChunks(source: "A.pdf", count: 1, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 2)

        vm.deleteDocument(source: "A.pdf", modelContext: context)
        vm.deleteDocument(source: "B.pdf", modelContext: context)

        XCTAssertEqual(vm.documents.count, 0, "删除所有 source 后 documents 应为空")
    }

    /// deleteDocument 后再 load 应从 context 重建（已删除的 source 不再出现）
    func testDeleteDocumentPersistsAcrossReload() {
        insertChunks(source: "A.pdf", count: 2, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)
        vm.load(modelContext: context)

        vm.deleteDocument(source: "A.pdf", modelContext: context)

        // 重新 load，A.pdf 不应再出现
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.count, 1, "重新 load 后 A.pdf 不应出现")
        XCTAssertEqual(vm.documents.first?.source, "B.pdf", "仅剩 B.pdf")
    }

    // MARK: - importDocument 不可读文件

    /// importDocument 文件内容为空时应设置错误消息
    func testImportDocumentEmptyContentSetsErrorMessage() async {
        let vm = KnowledgeBaseVM(provider: .deepseek)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty_\(UUID().uuidString).txt")
        try? "".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "空文件应设置错误消息")
        XCTAssertTrue(vm.errorMessage?.contains(String(format: NSLocalizedString("无法读取文档内容：%@", comment: ""), tempURL.lastPathComponent)) ?? false,
                      "错误消息应包含'无法读取文档内容'，实际：\(vm.errorMessage ?? "nil")")
        XCTAssertFalse(vm.isImporting, "应未进入导入状态")
    }

    /// importDocument 不存在的文件应设置错误消息
    func testImportDocumentNonExistentFileSetsErrorMessage() async {
        let vm = KnowledgeBaseVM(provider: .deepseek)
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_file_\(UUID().uuidString).txt")

        await vm.importDocument(url: nonExistentURL, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "不存在的文件应设置错误消息")
        XCTAssertTrue(vm.errorMessage?.contains(String(format: NSLocalizedString("无法读取文档内容：%@", comment: ""), nonExistentURL.lastPathComponent)) ?? false,
                      "错误消息应包含'无法读取文档内容'，实际：\(vm.errorMessage ?? "nil")")
        XCTAssertFalse(vm.isImporting, "应未进入导入状态")
    }

    // MARK: - provider 属性

    /// KnowledgeBaseVM(provider: .deepseek) 的 provider 应为 .deepseek
    func testProviderPropertyDeepSeek() {
        let vm = KnowledgeBaseVM(provider: .deepseek)
        XCTAssertEqual(vm.provider, .deepseek, "provider 应为 .deepseek")
    }

    /// KnowledgeBaseVM(provider: .qwen) 的 provider 应为 .qwen
    func testProviderPropertyQwen() {
        let vm = KnowledgeBaseVM(provider: .qwen)
        XCTAssertEqual(vm.provider, .qwen, "provider 应为 .qwen")
    }

    /// KnowledgeBaseVM 默认 provider 应为 .deepseek
    func testProviderPropertyDefault() {
        XCTAssertEqual(vm.provider, .deepseek, "默认 provider 应为 .deepseek")
    }

    // MARK: - 初始状态

    /// 新建的 KnowledgeBaseVM 初始状态应为空
    func testInitialState() {
        XCTAssertEqual(vm.documents.count, 0, "初始 documents 应为空")
        XCTAssertFalse(vm.isImporting, "初始 isImporting 应为 false")
        XCTAssertNil(vm.errorMessage, "初始 errorMessage 应为 nil")
    }

    // MARK: - DocumentRow 标识

    /// DocumentRow 的 id 应等于 source
    func testDocumentRowIdEqualsSource() {
        insertChunks(source: "test.pdf", count: 1, baseTime: 1000)
        vm.load(modelContext: context)

        let row = vm.documents.first
        XCTAssertEqual(row?.id, "test.pdf", "DocumentRow.id 应等于 source")
        XCTAssertEqual(row?.source, "test.pdf")
    }

    /// 多个 source 的 DocumentRow id 应互不相同
    func testDocumentRowIdsAreUnique() {
        insertChunks(source: "A.pdf", count: 1, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)
        vm.load(modelContext: context)

        let ids = Set(vm.documents.map(\.id))
        XCTAssertEqual(ids.count, 2, "不同 source 的 DocumentRow id 应互不相同")
    }

    // MARK: - importDocument Qwen 供应商路径

    /// importDocument 使用 Qwen 供应商时，resolveEmbedding 成功但 apiKey 为空，应提示 "请先在设置中配置 API Key"
    func testImportDocumentQwenProviderEmptyApiKeyShowsError() async {
        // Qwen 供应商：resolveEmbedding 返回非 nil，但测试环境 Keychain 无 Qwen Key
        let vm = KnowledgeBaseVM(provider: .qwen)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen_test_\(UUID().uuidString).txt")
        try? "这是 Qwen 供应商测试文档内容".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "Qwen 供应商无 API Key 时应设置错误消息")
        XCTAssertTrue(
            vm.errorMessage?.contains(NSLocalizedString("请先在设置中配置 API Key", comment: "")) == true,
            "错误消息应包含'请先在设置中配置 API Key'，实际：\(vm.errorMessage ?? "nil")"
        )
        XCTAssertFalse(vm.isImporting, "apiKey 为空时不应进入导入状态")
    }

    /// importDocument 使用 Qwen 供应商且文件不可读时，应先提示 "无法读取文档内容"（在 resolveEmbedding 之前）
    func testImportDocumentQwenProviderUnreadableFileShowsContentError() async {
        let vm = KnowledgeBaseVM(provider: .qwen)
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_qwen_\(UUID().uuidString).txt")

        await vm.importDocument(url: nonExistentURL, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "不可读文件应设置错误消息")
        XCTAssertTrue(
            vm.errorMessage?.contains(String(format: NSLocalizedString("无法读取文档内容：%@", comment: ""), nonExistentURL.lastPathComponent)) == true,
            "错误消息应包含'无法读取文档内容'（在 apiKey 检查之前），实际：\(vm.errorMessage ?? "nil")"
        )
    }

    // MARK: - importDocument PDF 扩展名路径

    /// importDocument 对 .pdf 扩展名文件应走 PDFExtractor 路径，非真实 PDF 返回无法读取
    func testImportDocumentPDFExtensionNonPDFFileShowsError() async {
        let vm = KnowledgeBaseVM(provider: .deepseek)
        // 创建一个扩展名为 .pdf 但内容为纯文本的文件（非真实 PDF）
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake_\(UUID().uuidString).pdf")
        try? "这不是一个真实的 PDF 文件".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        XCTAssertNotNil(vm.errorMessage, "非真实 PDF 文件应设置错误消息")
        XCTAssertTrue(
            vm.errorMessage?.contains(String(format: NSLocalizedString("无法读取文档内容：%@", comment: ""), tempURL.lastPathComponent)) == true,
            "错误消息应包含'无法读取文档内容'，实际：\(vm.errorMessage ?? "nil")"
        )
        XCTAssertFalse(vm.isImporting, "PDF 解析失败时不应进入导入状态")
    }

    // MARK: - importDocument isImporting 状态

    /// importDocument 在内容为空时不应设置 isImporting = true
    func testImportDocumentEmptyContentDoesNotSetImporting() async {
        let vm = KnowledgeBaseVM(provider: .deepseek)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty_importing_\(UUID().uuidString).txt")
        try? "".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        XCTAssertFalse(vm.isImporting, "内容为空时 isImporting 应保持 false")
        XCTAssertNotNil(vm.errorMessage, "应设置错误消息")
    }

    // MARK: - load 不设置 errorMessage

    /// load 成功时不应设置 errorMessage（保持 nil）
    func testLoadDoesNotSetErrorMessage() {
        insertChunks(source: "A.pdf", count: 2, baseTime: 1000)
        vm.errorMessage = "之前的错误"

        vm.load(modelContext: context)

        // load 不应主动清除或设置 errorMessage（它只管理 documents）
        XCTAssertEqual(vm.documents.count, 1, "应加载 1 个文档")
        // errorMessage 由 importDocument 管理，load 不应触碰
    }

    // MARK: - load 多 source 排序

    /// load 应按 createdAt 降序排序三个 source
    func testLoadSortsThreeSourcesByCreatedAtDescending() {
        insertChunks(source: "C.pdf", count: 1, baseTime: 1000)
        insertChunks(source: "A.pdf", count: 1, baseTime: 3000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)

        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.map(\.source), ["A.pdf", "B.pdf", "C.pdf"],
                       "应按 createdAt 降序：A(3000) → B(2000) → C(1000)")
    }

    /// load 单个 source 多个 chunk 时 createdAt 应取最大值
    func testLoadSingleSourceMultipleChunksMaxCreatedAt() {
        // 5 个 chunk，createdAt 从 1000 到 1004
        insertChunks(source: "multi.pdf", count: 5, baseTime: 1000)

        vm.load(modelContext: context)

        XCTAssertEqual(vm.documents.count, 1, "应聚合为 1 个文档")
        XCTAssertEqual(vm.documents.first?.chunkCount, 5, "chunkCount 应为 5")
        XCTAssertEqual(vm.documents.first?.createdAt, Date(timeIntervalSince1970: 1004),
                       "createdAt 应为最大值 1004")
    }

    // MARK: - deleteDocument 后列表状态

    /// deleteDocument 后剩余文档应保持正确顺序
    func testDeleteDocumentPreservesOrderOfRemaining() {
        insertChunks(source: "A.pdf", count: 1, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)
        insertChunks(source: "C.pdf", count: 1, baseTime: 3000)
        vm.load(modelContext: context)
        XCTAssertEqual(vm.documents.map(\.source), ["C.pdf", "B.pdf", "A.pdf"])

        // 删除中间的 B
        vm.deleteDocument(source: "B.pdf", modelContext: context)

        XCTAssertEqual(vm.documents.count, 2, "删除 B 后应剩 2 个文档")
        XCTAssertEqual(vm.documents.map(\.source), ["C.pdf", "A.pdf"],
                       "删除 B 后剩余文档应保持降序排列")
    }

    /// deleteDocument 删除第一个文档后剩余列表正确
    func testDeleteDocumentFirstElement() {
        insertChunks(source: "A.pdf", count: 1, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)
        vm.load(modelContext: context)
        // 排序后：B, A

        vm.deleteDocument(source: "B.pdf", modelContext: context)

        XCTAssertEqual(vm.documents.count, 1, "删除 B 后应剩 1 个文档")
        XCTAssertEqual(vm.documents.first?.source, "A.pdf", "应剩 A.pdf")
    }

    /// deleteDocument 删除最后一个文档后剩余列表正确
    func testDeleteDocumentLastElement() {
        insertChunks(source: "A.pdf", count: 1, baseTime: 1000)
        insertChunks(source: "B.pdf", count: 1, baseTime: 2000)
        vm.load(modelContext: context)

        vm.deleteDocument(source: "A.pdf", modelContext: context)

        XCTAssertEqual(vm.documents.count, 1, "删除 A 后应剩 1 个文档")
        XCTAssertEqual(vm.documents.first?.source, "B.pdf", "应剩 B.pdf")
    }

    // MARK: - importDocument 不同扩展名

    /// importDocument 对 .txt 扩展名文件应走 String(contentsOf:) 路径读取文本
    func testImportDocumentTXTExtensionReadsContent() async {
        let vm = KnowledgeBaseVM(provider: .qwen)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("txt_test_\(UUID().uuidString).txt")
        try? "TXT 文件测试内容".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        // .txt 能读取内容，但 Qwen 无 API Key → 应提示 "请先在设置中配置 API Key"
        XCTAssertNotNil(vm.errorMessage, "应设置错误消息")
        XCTAssertTrue(
            vm.errorMessage?.contains(NSLocalizedString("请先在设置中配置 API Key", comment: "")) == true,
            ".txt 文件读取成功但无 API Key 应提示配置 API Key，实际：\(vm.errorMessage ?? "nil")"
        )
    }

    /// importDocument 对 .md 扩展名文件应走 String(contentsOf:) 路径读取文本
    func testImportDocumentMDExtensionReadsContent() async {
        let vm = KnowledgeBaseVM(provider: .qwen)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("md_test_\(UUID().uuidString).md")
        try? "# Markdown 标题".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importDocument(url: tempURL, modelContext: context)

        // .md 走 String(contentsOf:) 路径，读取成功但无 API Key
        XCTAssertNotNil(vm.errorMessage, "应设置错误消息")
        XCTAssertTrue(
            vm.errorMessage?.contains(NSLocalizedString("请先在设置中配置 API Key", comment: "")) == true,
            ".md 文件读取成功但无 API Key 应提示配置 API Key，实际：\(vm.errorMessage ?? "nil")"
        )
    }

    // MARK: - load 后 documents 属性

    /// load 后 documents 应包含正确的 DocumentRow 字段（source 和 chunkCount 一致）
    func testLoadDocumentRowFieldsCorrect() {
        insertChunks(source: "doc1.pdf", count: 3, baseTime: 1000)
        insertChunks(source: "doc2.pdf", count: 5, baseTime: 2000)

        vm.load(modelContext: context)

        let doc1 = vm.documents.first { $0.source == "doc1.pdf" }
        XCTAssertEqual(doc1?.source, "doc1.pdf", "source 应为 doc1.pdf")
        XCTAssertEqual(doc1?.chunkCount, 3, "chunkCount 应为 3")
        XCTAssertEqual(doc1?.id, "doc1.pdf", "id 应等于 source")

        let doc2 = vm.documents.first { $0.source == "doc2.pdf" }
        XCTAssertEqual(doc2?.source, "doc2.pdf", "source 应为 doc2.pdf")
        XCTAssertEqual(doc2?.chunkCount, 5, "chunkCount 应为 5")
        XCTAssertEqual(doc2?.id, "doc2.pdf", "id 应等于 source")
    }
}
