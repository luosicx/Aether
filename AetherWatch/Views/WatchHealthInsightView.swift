#if os(watchOS)
import SwiftUI
import SwiftData

/// Day 17: watchOS 健康洞察页。展示最近一条 AI 生成的健康洞察。
///
/// - Note: 此文件仅在 watchOS target 中编译。
struct WatchHealthInsightView: View {
    /// SwiftData 上下文，查询 HealthInsight
    @Environment(\.modelContext) private var modelContext
    /// 查询结果：最近的健康洞察
    @Query(sort: \HealthInsight.timestamp, order: .reverse) private var insights: [HealthInsight]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let latest = insights.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("健康洞察", comment: "Watch 健康洞察标题"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(latest.timestamp.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("生成时间")
                            .accessibilityValue(latest.timestamp.formatted(.dateTime.month().day().hour().minute()))
                        Text(latest.content)
                            .font(.caption2)
                            .accessibilityLabel("健康洞察内容")
                            .accessibilityValue(latest.content)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .contain)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.text.square")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("暂无健康洞察", comment: "Watch 暂无健康洞察提示"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("请在 iPhone 上生成", comment: "Watch 引导用户在 iPhone 生成洞察"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("暂无健康洞察，请在 iPhone 上生成")
                    .accessibilityHint("在 iPhone 端以太 App 中生成健康洞察后查看")
                }
            }
            .navigationTitle(NSLocalizedString("健康洞察", comment: "Watch 导航标题：健康洞察"))
            .accessibilityIdentifier("watchHealthInsightView")
        }
    }
}
#endif
