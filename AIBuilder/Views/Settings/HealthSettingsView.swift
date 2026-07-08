import SwiftUI
import SwiftData

/// Day 17: 健康管理设置页。展示授权状态、注入开关与已生成洞察列表。
///
/// 功能：
/// - 请求 HealthKit 授权
/// - 跳转系统设置
/// - 切换注入健康上下文
/// - 立即生成洞察（调用 HealthInsightGenerator）
struct HealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var chatViewModel: ChatViewModel

    /// 授权状态文案
    @State private var authorizationStatus: String = "未授权"
    /// 是否正在生成洞察
    @State private var isGenerating: Bool = false
    /// 生成结果提示
    @State private var generateMessage: String?

    /// 查询所有健康洞察（按时间倒序）
    @Query(sort: \HealthInsight.timestamp, order: .reverse) private var insights: [HealthInsight]

    var body: some View {
        Form {
            // MARK: - 授权状态
            Section("授权状态") {
                HStack {
                    Text("当前状态")
                    Spacer()
                    Text(authorizationStatus)
                        .foregroundStyle(authorizationStatus == "已授权" ? .green : .secondary)
                }
                Button("请求授权") {
                    Task {
                        await requestAuthorization()
                    }
                }
                #if os(iOS)
                Button("跳转系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                #endif
            }

            // MARK: - 健康上下文
            Section {
                Toggle("注入健康上下文", isOn: $chatViewModel.injectHealthContext)
            } header: {
                Text("健康上下文")
            } footer: {
                Text("开启后发送消息时会注入最近 24 小时的睡眠/心率/步数数据，AI 将给出针对性建议。")
                    .font(.caption2)
            }

            // MARK: - 洞察
            Section {
                Button("立即生成洞察") {
                    Task { await generateInsight() }
                }
                .disabled(isGenerating)

                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("生成中...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let msg = generateMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("失败") ? .red : .green)
                }

                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(insight.insightType)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(4)
                            Spacer()
                            Text(insight.timestamp.formatted(.dateTime.month().day().hour().minute()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(insight.content)
                            .font(.caption)
                            .lineLimit(5)
                    }
                }
            } header: {
                Text("洞察")
            } footer: {
                Text("每天 09:00 自动生成一次，也可手动触发。")
                    .font(.caption2)
            }
        }
        .navigationTitle("健康管理")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            refreshAuthorizationStatus()
        }
    }

    /// 请求 HealthKit 授权并刷新状态
    private func requestAuthorization() async {
        #if os(iOS)
        // 注入 HealthKitService 到 ChatViewModel（若未注入）
        if chatViewModel.healthKitService == nil {
            chatViewModel.healthKitService = HealthKitService()
        }
        do {
            try await chatViewModel.healthKitService?.requestAuthorization()
            authorizationStatus = "已授权"
        } catch {
            authorizationStatus = "未授权"
            generateMessage = "授权失败：\(error.localizedDescription)"
        }
        #endif
    }

    /// 刷新授权状态文案
    private func refreshAuthorizationStatus() {
        #if os(iOS)
        if chatViewModel.healthKitService == nil {
            chatViewModel.healthKitService = HealthKitService()
        }
        authorizationStatus = (chatViewModel.healthKitService?.isAuthorized ?? false) ? "已授权" : "未授权"
        #endif
    }

    /// 立即生成健康洞察
    private func generateInsight() async {
        isGenerating = true
        generateMessage = nil
        defer { isGenerating = false }
        do {
            let generator = HealthInsightGenerator.make(modelContext: modelContext)
            let insight = try await generator.generateInsight(days: 7)
            generator.sendInsightNotification(insight)
            generateMessage = "洞察已生成"
        } catch {
            generateMessage = "生成失败：\(error.localizedDescription)"
        }
    }
}
