import SwiftUI

/// Day 16: 端侧模型管理页（模型目录版）。
/// 顶部选择下载源（国内 ModelScope / 国外 HuggingFace），下方列出可用模型，
/// 每个模型支持独立下载、断点续传、删除。下载逻辑调用 OnDeviceModelDownloader.shared；
/// 进度通过轮询 actor 状态更新，并以 downloadingModelId 跟踪当前下载中的模型。
struct OnDeviceModelView: View {
    /// 设置 ViewModel，用于读写 onDeviceConfig（downloadSource / modelPath / modelName 等）
    @Bindable var settingsVM: SettingsViewModel

    /// 下载进度（0.0-1.0，由轮询任务从 downloader 读取）
    @State private var progress: Double = 0.0
    /// 是否正在下载
    @State private var isDownloading = false
    /// 独立的 task id，用于触发 .task 轮询，避免在 task 闭包内修改 isDownloading 导致重建
    @State private var downloadTaskId: Int = 0
    /// 当前下载中的模型 ID（用于在列表中定位进度条与取消按钮）
    @State private var downloadingModelId: String?
    /// 已下载到本地的模型 ID 集合
    @State private var downloadedModelIds: Set<String> = []
    /// 最近一次错误信息
    @State private var errorMessage: String?
    /// 是否存在断点续传数据（决定是否展示「继续下载」按钮）
    @State private var hasResumeData = false
    /// 删除确认弹窗展示状态
    @State private var showDeleteConfirm = false
    /// 待删除的模型（确认弹窗用）
    @State private var pendingDeleteModel: OnDeviceModelEntry?
    /// 模型预加载中（下载完成后后台加载模型到内存）
    @State private var isPreloadingModel = false

    /// 模型本地保存目录
    private var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ondevice_models", isDirectory: true)
    }

    var body: some View {
        Form {
            // 下载源
            Section {
                Picker(selection: $settingsVM.onDeviceConfig.downloadSource) {
                    ForEach(DownloadSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                } label: {
                    Text("下载源")
                }
                .accessibilityLabel("下载源")
                .accessibilityHint("选择国内 ModelScope 或国外 HuggingFace 下载源")
                .accessibilityIdentifier("downloadSourcePicker")
            } header: {
                Text("下载源")
            }

            // 可用模型列表
            Section {
                if downloadedModelIds.isEmpty {
                    EmptyStateView(
                        systemImage: "cpu",
                        title: "尚未下载端侧模型",
                        message: "下载端侧模型以在无网络时使用 AI 推理"
                    )
                    .frame(height: 240)
                    .listRowBackground(Color.clear)
                }
                ForEach(OnDeviceModelCatalog.models) { model in
                    modelCard(for: model)
                }
            } header: {
                Text("可用模型")
            }

            // 错误信息
            if let msg = errorMessage {
                Section {
                    Text(msg)
                        .font(.captionAI)
                        .foregroundStyle(.red)
                }
            }

            // 模型预加载状态（后台加载中提示）
            if isPreloadingModel {
                Section {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在加载模型…")
                            .font(.captionAI)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("modelPreloadingIndicator")
                }
            }
        }
        .navigationTitle("端侧模型管理")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("OnDeviceModelView")
        .onAppear {
            refreshDownloadedStatus()
        }
        // 轮询下载进度：下载中时每 200ms 从 downloader 读取最新进度。
        // 使用独立 downloadTaskId 作为 task id，避免在闭包内修改 isDownloading 导致 task 被取消并重建
        .task(id: downloadTaskId) {
            guard isDownloading else { return }
            while !Task.isCancelled {
                progress = await OnDeviceModelDownloader.shared.progress
                isDownloading = await OnDeviceModelDownloader.shared.isDownloading
                if !isDownloading {
                    // 下载结束：检查错误并刷新状态
                    if let err = await OnDeviceModelDownloader.shared.lastError {
                        errorMessage = err.errorDescription
                    } else {
                        errorMessage = nil
                    }
                    hasResumeData = await OnDeviceModelDownloader.shared.hasResumeData
                    refreshDownloadedStatus()
                    settingsVM.saveOnDeviceConfig()
                    // 下载成功（无续传数据）时清除当前下载模型标记；
                    // 存在续传数据时保留 downloadingModelId 以便展示「继续下载」按钮
                    if !hasResumeData {
                        downloadingModelId = nil
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }
        // 删除确认弹窗
        .confirmationDialog(
            pendingDeleteModel.map { model in
                String(format: NSLocalizedString("确认删除「%@」？删除后需重新下载。", comment: ""), model.name)
            } ?? "",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("确认删除", role: .destructive) {
                if let model = pendingDeleteModel {
                    Task { await deleteModel(model: model) }
                }
                pendingDeleteModel = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteModel = nil
            }
        }
    }

    /// 单个模型卡片：名称 + 状态徽章 / 描述 / 体积 + 校验状态 / 操作按钮
    @ViewBuilder
    private func modelCard(for model: OnDeviceModelEntry) -> some View {
        let isDownloaded = downloadedModelIds.contains(model.id)
        let isThisDownloading = isDownloading && downloadingModelId == model.id
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.name).bold()
                Spacer()
                if isDownloaded {
                    Text("已下载✓")
                        .font(.captionAI)
                        .foregroundStyle(.green)
                } else {
                    Text("未下载")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                }
            }
            Text(model.description)
                .font(.captionAI)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(format: NSLocalizedString("约 %d MB", comment: ""), model.estimatedSizeMB))
                    .font(.captionAI)
                    .foregroundStyle(.secondary)
                Spacer()
                if isDownloaded {
                    Text("已校验")
                        .font(.captionAI)
                        .foregroundStyle(.green)
                } else if model.sha256.isEmpty {
                    Text("未配置")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.captionAI)
                        .foregroundStyle(.secondary)
                }
            }
            // 操作按钮：根据下载状态切换
            if isThisDownloading {
                ProgressView(value: progress) {
                    Text(String(format: NSLocalizedString("下载中…%d%%", comment: ""), Int(progress * 100)))
                }
                Button("取消下载", role: .destructive) {
                    Task { await cancelDownload() }
                }
                .accessibilityLabel("取消下载")
                .accessibilityHint("取消当前模型下载")
                .accessibilityIdentifier("cancelDownloadButton")
            } else {
                HStack {
                    if isDownloaded {
                        Button("删除", role: .destructive) {
                            pendingDeleteModel = model
                            showDeleteConfirm = true
                        }
                        .accessibilityLabel("删除模型")
                        .accessibilityHint("删除本地模型文件以释放空间")
                        .accessibilityIdentifier("deleteModelButton")
                    } else {
                        if hasResumeData && downloadingModelId == model.id {
                            Button("继续下载") {
                                Task { await resumeDownload() }
                            }
                            .accessibilityLabel("继续下载")
                            .accessibilityHint("从断点继续下载模型")
                            .accessibilityIdentifier("resumeDownloadButton")
                        }
                        Button("下载") {
                            Task { await startDownload(model: model) }
                        }
                        .accessibilityLabel("下载模型")
                        .accessibilityHint("开始下载端侧推理模型文件")
                        .accessibilityIdentifier("downloadModelButton")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 启动下载：创建目录 → 调用 downloader → 设置 isDownloading 触发轮询
    private func startDownload(model: OnDeviceModelEntry) async {
        errorMessage = nil
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        isDownloading = true
        downloadingModelId = model.id
        downloadTaskId += 1 // 触发 .task(id: downloadTaskId) 轮询
        guard let url = model.url(for: settingsVM.onDeviceConfig.downloadSource) else {
            errorMessage = "模型下载地址无效"
            isDownloading = false
            downloadingModelId = nil
            return
        }
        // 国内源：主地址为 ModelScope，无需镜像；国外源：主地址为 HuggingFace，镜像回退到 ModelScope
        let mirrorURL: URL? = settingsVM.onDeviceConfig.downloadSource == .international ? model.modelScopeURL : nil
        await OnDeviceModelDownloader.shared.startDownload(
            url: url,
            to: modelPath(for: model),
            expectedSHA256: model.sha256,
            mirrorURL: mirrorURL
        )
        // 下载完成后回写 modelPath / modelName 到 config
        settingsVM.onDeviceConfig.modelPath = modelPath(for: model)
        settingsVM.onDeviceConfig.modelName = model.name
        settingsVM.saveOnDeviceConfig()
        // 下载成功时预加载模型到内存（后台执行，不阻塞 UI）
        let downloadError = await OnDeviceModelDownloader.shared.lastError
        if downloadError == nil {
            preloadModel(at: modelPath(for: model), expectedSHA256: model.sha256)
        }
    }

    /// 继续下载：使用断点续传数据从中断处恢复下载
    private func resumeDownload() async {
        guard let modelId = downloadingModelId, let model = OnDeviceModelCatalog.find(id: modelId) else { return }
        errorMessage = nil
        isDownloading = true
        downloadTaskId += 1 // 触发 .task(id: downloadTaskId) 轮询
        await OnDeviceModelDownloader.shared.resumeDownload()
        settingsVM.onDeviceConfig.modelPath = modelPath(for: model)
        settingsVM.saveOnDeviceConfig()
        // 下载成功时预加载模型到内存（后台执行，不阻塞 UI）
        let downloadError = await OnDeviceModelDownloader.shared.lastError
        if downloadError == nil {
            preloadModel(at: modelPath(for: model), expectedSHA256: model.sha256)
        }
    }

    /// 取消下载
    private func cancelDownload() async {
        await OnDeviceModelDownloader.shared.cancelDownload()
        isDownloading = false
        progress = 0.0
    }

    /// 删除本地模型文件
    private func deleteModel(model: OnDeviceModelEntry) async {
        do {
            try await OnDeviceModelDownloader.shared.deleteModel(at: modelPath(for: model))
            downloadedModelIds.remove(model.id)
            if settingsVM.onDeviceConfig.modelName == model.name {
                settingsVM.onDeviceConfig.modelPath = nil
                settingsVM.saveOnDeviceConfig()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 预加载模型到内存（后台 Task 执行，不阻塞 UI）。
    /// 下载完成后调用：先加载模型权重，再预加载 tokenizer，全程在后台进行。
    /// 加载状态通过 isPreloadingModel 展示给用户，加载失败仅记录错误不影响下载完成状态。
    private func preloadModel(at path: URL, expectedSHA256: String) {
        isPreloadingModel = true
        Task {
            do {
                try await MLXInferenceEngine.shared.loadModel(path: path, expectedSHA256: expectedSHA256)
                await MLXInferenceEngine.shared.preloadTokenizer()
            } catch {
                errorMessage = error.localizedDescription
            }
            isPreloadingModel = false
        }
    }

    /// 计算指定模型的本地保存路径
    private func modelPath(for model: OnDeviceModelEntry) -> URL {
        modelDirectory.appendingPathComponent(model.id)
    }

    /// 刷新已下载模型集合（遍历目录检查文件存在性）
    private func refreshDownloadedStatus() {
        downloadedModelIds = Set(OnDeviceModelCatalog.models.filter { model in
            FileManager.default.fileExists(atPath: modelPath(for: model).path)
        }.map { $0.id })
    }
}
