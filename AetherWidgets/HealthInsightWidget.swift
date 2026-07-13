import WidgetKit
import SwiftUI
import SwiftData

/// Task 5.4: 健康洞察 Widget。
/// 支持 Medium / Large 尺寸，使用 TimelineProvider 读取 SwiftData 中最新的 HealthInsight。
/// 定时刷新（每 2 小时），展示最新健康洞察摘要。
struct HealthInsightWidget: Widget {
    let kind: String = "HealthInsightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: HealthInsightTimelineProvider()
        ) { entry in
            HealthInsightWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(NSLocalizedString("健康洞察", comment: "Widget 名称：健康洞察"))
        .description(NSLocalizedString("查看最新的 AI 健康洞察摘要", comment: "Widget 描述：健康洞察"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// 健康洞察 Widget 的时间线条目
struct HealthInsightEntry: TimelineEntry {
    let date: Date
    /// 最新健康洞察内容（nil 表示暂无数据）
    let insightContent: String?
    /// 洞察生成时间
    let insightTimestamp: Date?
    /// 洞察类别
    let insightType: String?
}

/// 健康洞察 Widget 的 TimelineProvider。
/// 通过 SwiftData ModelContainer 读取 App Group 共享 store 中的最新 HealthInsight。
struct HealthInsightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthInsightEntry {
        HealthInsightEntry(
            date: Date(),
            insightContent: NSLocalizedString("最近睡眠质量良好，平均心率正常。建议保持规律作息。", comment: "Widget 占位洞察"),
            insightTimestamp: Date(),
            insightType: "overall"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthInsightEntry) -> Void) {
        let entry = fetchLatestInsight() ?? placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthInsightEntry>) -> Void) {
        let entry = fetchLatestInsight() ?? HealthInsightEntry(date: Date(), insightContent: nil, insightTimestamp: nil, insightType: nil)
        // 每 2 小时刷新一次
        let nextRefresh = Date().addingTimeInterval(2 * 3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// 从共享 SwiftData store 读取最新 HealthInsight
    private func fetchLatestInsight() -> HealthInsightEntry? {
        do {
            let config = AppGroupContainer.makeModelConfiguration()
            let container = try ModelContainer(
                for: HealthInsight.self,
                configurations: config
            )
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<HealthInsight>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let insights = try context.fetch(descriptor)
            guard let latest = insights.first else { return nil }
            return HealthInsightEntry(
                date: Date(),
                insightContent: latest.content,
                insightTimestamp: latest.timestamp,
                insightType: latest.insightType
            )
        } catch {
            return nil
        }
    }
}

/// 健康洞察 Widget 视图
struct HealthInsightWidgetView: View {
    let entry: HealthInsightEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    /// Medium 尺寸：标题 + 时间 + 摘要（截断）
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .font(.caption)
                    .foregroundStyle(.pink)
                Text(NSLocalizedString("健康洞察", comment: "Widget 标题"))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            if let content = entry.insightContent, let timestamp = entry.insightTimestamp {
                Text(timestamp.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(content)
                    .font(.caption2)
                    .lineLimit(4)
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "heart.text.square")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("暂无健康洞察", comment: "Widget 暂无洞察"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(10)
    }

    /// Large 尺寸：标题 + 时间 + 完整摘要
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(.pink)
                Text(NSLocalizedString("健康洞察", comment: "Widget 标题"))
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            if let content = entry.insightContent, let timestamp = entry.insightTimestamp {
                Text(timestamp.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(content)
                    .font(.caption)
                    .lineLimit(10)
                Spacer(minLength: 0)
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "heart.text.square")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("暂无健康洞察", comment: "Widget 暂无洞察"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("请在 iPhone 上生成", comment: "Widget 引导生成洞察"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(12)
    }
}
