import SwiftUI

/// Day 16: 端侧模型管理页。展示当前模型信息、下载进度、删除与切换模型。
/// 下载逻辑调用 OnDeviceModelDownloader.shared；进度通过轮询 actor 状态更新。
struct OnDeviceModelView: View {
    /// 设置 ViewModel，用于读写 onDeviceConfig（modelPath / modelName 等）
    @Bindable var settingsVM: SettingsViewModel

    /// 下载进度（0.0-1.0，由轮询任务从 downloader 读取）
    @State private var progress: Double = 0.0
    /// 是否正在下载
    @State private var isDownloading = false
    /// 模型是否已下载到本地
    @State private var isModelDownloaded = false
    /// 最近一次错误信息
    @State private var errorMessage: String?

    /// 可切换的端侧模型列表
    private let modelOptions = [
        "Llama-3.2-1B-Instruct-Q4_K_M",
        "Qwen2-0.5B-Instruct-Q4_K_M",
        "Phi-3-mini-4k-instruct-Q4_K_M"
    ]

    /// 模型本地保存目录
    private var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ondevice_models", isDirectory: true)
    }

    /// 当前模型本地路径
    private var modelPath: URL {
        modelDirectory.appendingPathComponent(settingsVM.onDeviceConfig.modelName)
    }

    var body: some View {
        Form {
            // 当前模型信息
            Section("当前模型") {
                HStack {
                    Text("模型名")
                    Spacer()
                    Text(settingsVM.onDeviceConfig.modelName)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("本地路径")
                    Spacer()
                    Text(isModelDownloaded ? "已下载" : "未下载")
                        .foregroundStyle(isModelDownloaded ? .green : .secondary)
                }
                HStack {
                    Text("SHA256 校验")
                    Spacer()
                    if settingsVM.onDeviceConfig.expectedSHA256.isEmpty {
                        Text("未配置").foregroundStyle(.secondary)
                    } else if isModelDownloaded {
                        Text("已通过").foregroundStyle(.green)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }

            // 下载
            Section("下载") {
                if isDownloading {
                    // 下载中：进度条 + 取消按钮
                    ProgressView(value: progress) {
                        Text("下载中…\(Int(progress * 100))%")
                    }
                    Button("取消下载", role: .destructive) {
                        Task { await cancelDownload() }
                    }
                } else {
                    Button("下载模型") {
                        Task { await startDownload() }
                    }
                    if isModelDownloaded {
                        Text("模型已就绪，约 700MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("模型文件约 700MB，建议在 Wi-Fi 下下载")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // 管理
            Section("管理") {
                Button("删除模型", role: .destructive) {
                    Task { await deleteModel() }
                }
                .disabled(!isModelDownloaded)
            }

            // 切换模型
            Section("切换模型") {
                Picker("选择模型", selection: $settingsVM.onDeviceConfig.modelName) {
                    ForEach(modelOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
        }
        .navigationTitle("端侧模型管理")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            refreshDownloadedStatus()
        }
        // 轮询下载进度：下载中时每 200ms 从 downloader 读取最新进度
        .task(id: isDownloading) {
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
                    refreshDownloadedStatus()
                    settingsVM.saveOnDeviceConfig()
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }
    }

    /// 启动下载：创建目录 → 调用 downloader → 设置 isDownloading 触发轮询
    private func startDownload() async {
        errorMessage = nil
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        isDownloading = true
        await OnDeviceModelDownloader.shared.startDownload(
            url: settingsVM.onDeviceConfig.downloadURL,
            to: modelPath,
            expectedSHA256: settingsVM.onDeviceConfig.expectedSHA256
        )
        // 下载完成后回写 modelPath 到 config
        settingsVM.onDeviceConfig.modelPath = modelPath
        settingsVM.saveOnDeviceConfig()
    }

    /// 取消下载
    private func cancelDownload() async {
        await OnDeviceModelDownloader.shared.cancelDownload()
        isDownloading = false
        progress = 0.0
    }

    /// 删除本地模型文件
    private func deleteModel() async {
        do {
            try await OnDeviceModelDownloader.shared.deleteModel(at: modelPath)
            isModelDownloaded = false
            settingsVM.onDeviceConfig.modelPath = nil
            settingsVM.saveOnDeviceConfig()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 刷新模型是否已下载状态（检查文件是否存在）
    private func refreshDownloadedStatus() {
        isModelDownloaded = FileManager.default.fileExists(atPath: modelPath.path)
        if isModelDownloaded {
            settingsVM.onDeviceConfig.modelPath = modelPath
        }
    }
}
