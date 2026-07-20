import AetherUI
import AetherServices
import SwiftUI
#if os(iOS)
import MessageUI
#endif

// MARK: - Day 9: 调试面板
/// 展示最近一次发送的完整 prompt、API 原始响应、embedding 维度与工具调用列表
struct DebugPanelView: View {
    @Bindable var chatViewModel: ChatViewModel
    // Day 14: 远程配置 / 遥测状态（从 actor 异步读取展示）
    @State private var configVersion: Int = 0
    @State private var fetchedAt: Date?
    @State private var remoteDefaultProvider: String = ""
    @State private var maintenanceMode: Bool = false
    @State private var telemetryBufferCount: Int = 0
    @State private var lastUploadAt: Date?
    @State private var lastUploadStatus: String = "idle"
    // Day 19: 性能指标（从 PerformanceMonitor actor 异步读取）
    @State private var performanceMetrics: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            Form {
                // Day 19: 性能指标
                Section("性能指标") {
                    if performanceMetrics.isEmpty {
                        Text("暂无性能数据", comment: "")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(performanceMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { name, elapsed in
                            HStack {
                                Text(name)
                                Spacer()
                                Text(String(format: "%.1f ms", elapsed))
                                    .foregroundStyle(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    Button("清除性能指标") {
                        Task {
                            await PerformanceMonitor.shared.clear()
                            performanceMetrics = await PerformanceMonitor.shared.getMetrics()
                        }
                    }
                    .accessibilityLabel("清除性能指标")
                    .accessibilityHint("清空本地记录的性能指标数据")
                    .accessibilityIdentifier("clearPerformanceMetricsButton")
                }

                // Day 14: 远程配置 / 遥测
                Section("远程配置 / 遥测") {
                    HStack {
                        Text("配置版本", comment: "")
                        Spacer()
                        Text("\(configVersion)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("拉取时间", comment: "")
                        Spacer()
                        Text(fetchedAt?.formatted(.dateTime) ?? String(localized: "未拉取")).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("默认供应商", comment: "")
                        Spacer()
                        Text(remoteDefaultProvider).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("维护模式", comment: "")
                        Spacer()
                        Text(maintenanceMode ? "是" : "否")
                            .foregroundStyle(maintenanceMode ? .red : .secondary)
                    }
                    HStack {
                        Text("缓冲事件数", comment: "")
                        Spacer()
                        Text("\(telemetryBufferCount)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("上次上报时间", comment: "")
                        Spacer()
                        Text(lastUploadAt?.formatted(.dateTime) ?? "从未").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("上次上报状态", comment: "")
                        Spacer()
                        Text(lastUploadStatus).foregroundStyle(.secondary)
                    }
                    Button("立即上报") {
                        Task {
                            await LogUploader.shared.uploadIfNeeded()
                            await refreshTelemetry()
                        }
                    }
                    .accessibilityLabel("立即上报")
                    .accessibilityHint("立即上传缓存的遥测日志")
                    .accessibilityIdentifier("uploadTelemetryButton")
                    Button("重新拉取配置") {
                        Task {
                            await RemoteConfigService.shared.fetch()
                            await refreshConfig()
                        }
                    }
                    .accessibilityLabel("重新拉取配置")
                    .accessibilityHint("从服务器获取最新远程配置")
                    .accessibilityIdentifier("refreshRemoteConfigButton")
                }

                // Day 13: 供应商 / 模型 / 降级信息
                Section("供应商与降级") {
                    HStack {
                        Text("当前供应商", comment: "")
                        Spacer()
                        Text(chatViewModel.lastUsedProvider?.displayName ?? String(localized: "未发送"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("选中模型", comment: "")
                        Spacer()
                        Text(chatViewModel.selectedProvider.defaultChatModel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("触发降级", comment: "")
                        Spacer()
                        Text(chatViewModel.didFallbackLastRequest ? String(localized: "是") : String(localized: "否"))
                            .foregroundStyle(chatViewModel.didFallbackLastRequest ? .orange : .secondary)
                    }
                }

                // 最近一次发送的完整 prompt JSON
                Section("最近 Prompt JSON") {
                    ScrollView {
                        Text(chatViewModel.lastDebugInfo?.promptJSON ?? "无")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 200)
                }

                // 最近一次 DeepSeek API 原始响应
                Section("API 原始响应") {
                    ScrollView {
                        Text(chatViewModel.lastDebugInfo?.apiResponse ?? String(localized: "无"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 200)
                }

                // 最近一次 embedding 向量维度
                Section("Embedding 维度") {
                    if let dim = chatViewModel.lastDebugInfo?.embeddingDimension {
                        Text(String(format: NSLocalizedString("%d 维", comment: ""), dim))
                    } else {
                        Text("无", comment: "")
                    }
                }

                // 最近一次工具调用参数与返回值
                Section("工具调用") {
                    if let calls = chatViewModel.lastDebugInfo?.toolCalls, !calls.isEmpty {
                        ForEach(calls) { call in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(call.toolName)
                                    .font(.headlineAI)
                                Text(String(format: NSLocalizedString("参数：%@", comment: ""), call.arguments))
                                    .font(.captionAI)
                                    .foregroundStyle(.secondary)
                                Text(String(format: NSLocalizedString("返回：%@", comment: ""), call.result))
                                    .font(.captionAI)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("无工具调用", comment: "")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("调试信息")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await refreshConfig()
                await refreshTelemetry()
                // Day 19: 拉取性能指标
                performanceMetrics = await PerformanceMonitor.shared.getMetrics()
            }
        }
    }

    // Day 14: 从 actor 异步读取远程配置到本地 @State
    private func refreshConfig() async {
        let config = await RemoteConfigService.shared.currentConfig
        configVersion = config.configVersion
        fetchedAt = config.fetchedAt
        remoteDefaultProvider = config.defaultProvider
        maintenanceMode = config.maintenanceMode
    }

    // Day 14: 从 actor 异步读取遥测状态到本地 @State
    private func refreshTelemetry() async {
        telemetryBufferCount = await TelemetryService.shared.bufferCount
        lastUploadAt = await LogUploader.shared.lastUploadAt
        lastUploadStatus = await LogUploader.shared.lastUploadStatus
    }
}
