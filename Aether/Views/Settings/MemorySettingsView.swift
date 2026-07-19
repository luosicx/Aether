import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Task 19 阶段 4: 记忆管理设置视图。
///
/// 提供：
/// - 加密开关（默认关闭，启用后向量与元数据均加密）
/// - 导出记忆为 JSON（可选加密）
/// - 从 JSON 导入记忆
/// - 清空全部记忆（二次确认）
struct MemorySettingsView: View {
    /// ModelContext 环境（用于构造 MemoryService）
    @Environment(\.modelContext) private var modelContext
    /// 加密层单例
    @ObservedObject private var encryption = EncryptionLayerObservable.shared

    /// 导出文件选择器状态
    @State private var showExportPicker = false
    /// 导入文件选择器状态
    @State private var showImportPicker = false
    /// 清空确认 Alert
    @State private var showClearConfirm = false
    /// 操作结果 Toast
    @State private var toastMessage: String?
    /// 是否正在处理（导入/导出/清空）
    @State private var isProcessing = false

    var body: some View {
        Section {
            // 加密开关
            Toggle(isOn: $encryption.isEnabled) {
                Label("端到端加密", systemImage: "lock.shield")
            }
            .accessibilityIdentifier("memoryEncryptionToggle")
            .onChange(of: encryption.isEnabled) { _, newValue in
                if newValue {
                    if !encryption.enable() {
                        encryption.isEnabled = false
                        toastMessage = "加密启用失败，请检查 Keychain 权限"
                    }
                } else {
                    encryption.disable()
                }
            }

            // 加密说明
            if encryption.isEnabled {
                Text("已启用：所有写入的向量与元数据均经 AES-GCM 加密")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("默认关闭。启用后向量与元数据均加密存储")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("记忆加密", comment: "")
        }

        Section {
            // 导出按钮
            Button {
                showExportPicker = true
            } label: {
                Label("导出记忆", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("exportMemoriesButton")
            .disabled(isProcessing)

            // 导入按钮
            Button {
                showImportPicker = true
            } label: {
                Label("导入记忆", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("importMemoriesButton")
            .disabled(isProcessing)

            // 清空按钮（危险操作）
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清空全部记忆", systemImage: "trash")
            }
            .accessibilityIdentifier("clearMemoriesButton")
            .disabled(isProcessing)
        } header: {
            Text("数据管理", comment: "")
        } footer: {
            Text("导出：将所有记忆（含已归档）保存为 JSON 文件，可用于备份或迁移到另一台设备。导入：从 JSON 文件恢复记忆，按 ID 去重。", comment: "")
                .font(.caption)
        }
        // 导出文件选择器
        .fileExporter(
            isPresented: $showExportPicker,
            document: MemoryJSONDocument(),
            contentType: .json,
            defaultFilename: "aether_memories.json"
        ) { result in
            handleExportResult(result)
        }
        // 导入文件选择器
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        // 清空确认
        .alert("清空全部记忆", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认清空", role: .destructive) {
                Task { await clearAllMemories() }
            }
        } message: {
            Text("此操作将删除所有记忆（含已归档），且不可恢复。确定继续吗？", comment: "")
        }
        // Toast 提示
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                Text(msg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
    }

    // MARK: - 导出处理

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task { await exportMemories(to: url) }
        case .failure:
            toastMessage = "导出取消"
        }
    }

    private func exportMemories(to url: URL) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let service = MemoryService(modelContext: modelContext)
            let exporter = ExportImporter(memoryService: service)
            let count = try await exporter.exportToFile(url: url, encrypt: encryption.isEnabled)
            toastMessage = "已导出 \(count) 条记忆"
        } catch {
            toastMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 导入处理

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importMemories(from: url) }
        case .failure:
            toastMessage = "导入取消"
        }
    }

    private func importMemories(from url: URL) async {
        isProcessing = true
        defer { isProcessing = false }
        // 启用沙盒访问
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let service = MemoryService(modelContext: modelContext)
            let importer = ExportImporter(memoryService: service)
            let result = try await importer.importFromFile(url: url)
            toastMessage = "已导入 \(result.importedCount) 条（跳过 \(result.skippedCount) 条重复）"
        } catch {
            toastMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 清空处理

    private func clearAllMemories() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let service = MemoryService(modelContext: modelContext)
            let exporter = ExportImporter(memoryService: service)
            let count = try await exporter.clearAllMemories()
            toastMessage = "已清空 \(count) 条记忆"
        } catch {
            toastMessage = "清空失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - JSON Document（用于 fileExporter）

/// JSON 文档类型，用于 SwiftUI fileExporter。
struct MemoryJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // 由 ExportImporter 直接写入文件，这里返回空 FileWrapper 占位
        return FileWrapper(directoryWithFileWrappers: [:])
    }
}

// MARK: - EncryptionLayer Observable 包装

/// EncryptionLayer 的 ObservableObject 包装，用于 SwiftUI 监听 isEnabled 状态变化。
@MainActor
final class EncryptionLayerObservable: ObservableObject {
    static let shared = EncryptionLayerObservable()

    @Published var isEnabled: Bool {
        didSet {
            // 同步到 EncryptionLayer 单例
            if isEnabled != EncryptionLayer.shared.isEnabled {
                if isEnabled {
                    if !EncryptionLayer.shared.enable() {
                        isEnabled = false
                    }
                } else {
                    EncryptionLayer.shared.disable()
                }
            }
        }
    }

    private init() {
        self.isEnabled = EncryptionLayer.shared.isEnabled
    }

    /// 启用加密
    @discardableResult
    func enable() -> Bool {
        let result = EncryptionLayer.shared.enable()
        isEnabled = EncryptionLayer.shared.isEnabled
        return result
    }

    /// 禁用加密
    func disable() {
        EncryptionLayer.shared.disable()
        isEnabled = EncryptionLayer.shared.isEnabled
    }
}
