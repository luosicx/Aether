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
                        Text("健康洞察")
                            .font(.headline)
                        Text(latest.timestamp.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(latest.content)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.text.square")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("暂无健康洞察")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("请在 iPhone 上生成")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("健康洞察")
        }
    }
}
#endif
