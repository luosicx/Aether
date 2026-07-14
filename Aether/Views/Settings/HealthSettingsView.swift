import SwiftUI
import SwiftData
import AetherDesign

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
    @State private var authorizationStatus: String = NSLocalizedString("未授权", comment: "")
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
                    Text("当前状态", comment: "")
                    Spacer()
                    Text(authorizationStatus)
                        .foregroundStyle(authorizationStatus == "已授权" ? .green : .secondary)
                }
                Button("请求授权") {
                    Task {
                        await requestAuthorization()
                    }
                }
                .accessibilityLabel("请求 HealthKit 授权")
                .accessibilityHint("授权后可读取心率、睡眠、步数等健康数据")
                .accessibilityIdentifier("requestHealthAuthButton")
                #if os(iOS)
                Button("跳转系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityLabel("跳转系统设置")
                .accessibilityHint("前往系统设置中修改健康数据权限")
                .accessibilityIdentifier("openHealthSettingsButton")
                #endif
            }

            // MARK: - 健康上下文
            Section {
                Toggle("注入健康上下文", isOn: $chatViewModel.injectHealthContext)
                    .accessibilityLabel("注入健康上下文")
                    .accessibilityHint("发送消息时注入最近健康数据")
                    .accessibilityIdentifier("injectHealthContextToggle")
            } header: {
                Text("健康上下文", comment: "")
            } footer: {
                Text("开启后发送消息时会注入最近 24 小时的睡眠/心率/步数数据，AI 将给出针对性建议。", comment: "")
                    .font(.captionAI)
            }

            // MARK: - 洞察
            Section {
                Button("立即生成洞察") {
                    Task { await generateInsight() }
                }
                .disabled(isGenerating)
                .accessibilityLabel("立即生成洞察")
                .accessibilityHint("基于最近健康数据生成洞察")
                .accessibilityIdentifier("generateHealthInsightButton")

                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("生成中...", comment: "")
                            .foregroundStyle(.secondary)
                    }
                }

                if let msg = generateMessage {
                    Text(msg)
                        .font(.captionAI)
                        .foregroundStyle(msg.contains("失败") ? .red : .green)
                }

                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text(insight.insightType)
                                .font(.captionAI)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(4)
                            Spacer()
                            Text(insight.timestamp.formatted(.dateTime.month().day().hour().minute()))
                                .font(.captionAI)
                                .foregroundStyle(.secondary)
                        }
                        Text(insight.content)
                            .font(.captionAI)
                            .lineLimit(5)
                    }
                }
            } header: {
                Text("洞察", comment: "")
            } footer: {
                Text("每天 09:00 自动生成一次，也可手动触发。", comment: "")
                    .font(.captionAI)
            }
        }
        .navigationTitle("健康管理")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("HealthSettingsView")
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
            authorizationStatus = NSLocalizedString("已授权", comment: "")
        } catch {
            authorizationStatus = NSLocalizedString("未授权", comment: "")
            generateMessage = String(format: NSLocalizedString("授权失败：%@", comment: ""), error.localizedDescription)
        }
        #endif
    }

    /// 刷新授权状态文案
    private func refreshAuthorizationStatus() {
        #if os(iOS)
        if chatViewModel.healthKitService == nil {
            chatViewModel.healthKitService = HealthKitService()
        }
        authorizationStatus = (chatViewModel.healthKitService?.isAuthorized ?? false) ? NSLocalizedString("已授权", comment: "") : NSLocalizedString("未授权", comment: "")
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
            generateMessage = NSLocalizedString("洞察已生成", comment: "")
        } catch {
            generateMessage = String(format: NSLocalizedString("生成失败：%@", comment: ""), error.localizedDescription)
        }
    }
}
